import { createClient } from "@supabase/supabase-js";

interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

interface WebhookRecord {
  id: string;
  conversation_id: string;
  sender_id: string;
  message_type?: string;
  created_at: string;
  expires_at?: string | null;
  deleted_at?: string | null;
}

interface WebhookPayload {
  type: string;
  table: string;
  record: WebhookRecord;
}

// In-memory cached Google OAuth2 token for FCM HTTP v1
let cachedOAuthToken: { token: string; expiresAt: number } | null = null;

function base64UrlEncode(str: string | Uint8Array): string {
  const binary =
    typeof str === "string" ? new TextEncoder().encode(str) : str;
  let base64 = btoa(String.fromCharCode(...binary));
  return base64.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToBinary(pem: string): Uint8Array {
  const cleanPem = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/-----BEGIN RSA PRIVATE KEY-----/g, "")
    .replace(/-----END RSA PRIVATE KEY-----/g, "")
    .replace(/\s+/g, "");
  const binaryString = atob(cleanPem);
  const bytes = new Uint8Array(binaryString.length);
  for (let i = 0; i < binaryString.length; i++) {
    bytes[i] = binaryString.charCodeAt(i);
  }
  return bytes;
}

async function getFCMAccessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedOAuthToken && cachedOAuthToken.expiresAt > now + 60) {
    return cachedOAuthToken.token;
  }

  const header = { alg: "RS256", typ: "JWT" };
  const claimSet = {
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    exp: now + 3600,
    iat: now,
  };

  const encodedHeader = base64UrlEncode(JSON.stringify(header));
  const encodedClaim = base64UrlEncode(JSON.stringify(claimSet));
  const unsignedToken = `${encodedHeader}.${encodedClaim}`;

  const keyBytes = pemToBinary(sa.private_key);
  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    keyBytes,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"]
  );

  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    cryptoKey,
    new TextEncoder().encode(unsignedToken)
  );

  const jwt = `${unsignedToken}.${base64UrlEncode(new Uint8Array(signature))}`;

  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`Failed to obtain FCM access token: ${response.status} ${errorText}`);
  }

  const data = await response.json();
  const token = data.access_token as string;
  const expiresIn = (data.expires_in as number) || 3600;

  cachedOAuthToken = { token, expiresAt: now + expiresIn };
  return token;
}

function maskToken(token: string): string {
  if (!token || token.length < 10) return "***";
  return `${token.slice(0, 6)}...${token.slice(-4)}`;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { "Content-Type": "application/json" },
    });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const webhookSecret = Deno.env.get("WEBHOOK_SECRET");
  const fcmServiceAccountJson = Deno.env.get("FCM_SERVICE_ACCOUNT_JSON");

  if (!supabaseUrl || !serviceRoleKey) {
    console.error("[PushServer] Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");
    return new Response(JSON.stringify({ error: "Server configuration error" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }

  // Webhook Authentication check
  const authHeader = req.headers.get("Authorization") ?? "";
  const customSecret = req.headers.get("x-webhook-secret") ?? "";

  const isServiceRoleAuthorized =
    authHeader === `Bearer ${serviceRoleKey}` ||
    authHeader.endsWith(serviceRoleKey);
  const isSecretAuthorized = webhookSecret && customSecret === webhookSecret;

  if (!isServiceRoleAuthorized && !isSecretAuthorized && webhookSecret) {
    console.warn("[PushServer] Unauthorized webhook request rejected");
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  let payload: WebhookPayload;
  try {
    payload = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON payload" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  const record = payload.record;
  if (!record || !record.id || !record.conversation_id || !record.sender_id) {
    console.warn("[PushServer] Incomplete message record, skipping");
    return new Response(JSON.stringify({ message: "Incomplete record ignored" }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  }

  // 1. Message freshness & validity checks
  if (record.deleted_at) {
    console.log(`[PushServer] Message ${record.id} is deleted, skipping notification`);
    return new Response(JSON.stringify({ message: "Deleted message ignored" }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  }

  if (record.expires_at) {
    const expiry = new Date(record.expires_at).getTime();
    if (Date.now() >= expiry) {
      console.log(`[PushServer] Message ${record.id} has already expired, skipping notification`);
      return new Response(JSON.stringify({ message: "Expired message ignored" }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }
  }

  if (record.message_type === "system") {
    return new Response(JSON.stringify({ message: "System message ignored" }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  }

  if (!fcmServiceAccountJson) {
    console.error("[PushServer] FCM_SERVICE_ACCOUNT_JSON is not configured in secrets");
    return new Response(
      JSON.stringify({ error: "FCM service account secret missing" }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }

  let serviceAccount: ServiceAccount;
  try {
    serviceAccount = JSON.parse(fcmServiceAccountJson);
  } catch (e) {
    console.error("[PushServer] Failed to parse FCM_SERVICE_ACCOUNT_JSON:", e);
    return new Response(
      JSON.stringify({ error: "Invalid service account JSON" }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // 2. Resolve conversation members (excluding the sender)
  const { data: members, error: membersError } = await supabase
    .from("conversation_members")
    .select("user_id")
    .eq("conversation_id", record.conversation_id)
    .neq("user_id", record.sender_id);

  if (membersError || !members || members.length === 0) {
    console.log(`[PushServer] No recipient members found for conversation ${record.conversation_id}`);
    return new Response(JSON.stringify({ message: "No recipients" }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  }

  const rawRecipientIds = members.map((m) => m.user_id as string);

  // 3. Filter out recipients affected by block relationships
  const { data: blocks } = await supabase
    .from("blocked_users")
    .select("blocker_id, blocked_id")
    .or(
      `and(blocker_id.eq.${record.sender_id},blocked_id.in.(${rawRecipientIds.join(",")})),and(blocked_id.eq.${record.sender_id},blocker_id.in.(${rawRecipientIds.join(",")}))`
    );

  const blockedSet = new Set<string>();
  if (blocks) {
    for (const b of blocks) {
      if (b.blocker_id === record.sender_id) blockedSet.add(b.blocked_id);
      if (b.blocked_id === record.sender_id) blockedSet.add(b.blocker_id);
    }
  }

  const eligibleRecipientIds = rawRecipientIds.filter((id) => !blockedSet.has(id));
  if (eligibleRecipientIds.length === 0) {
    console.log(`[PushServer] All recipients are blocked or blocking sender ${record.sender_id}`);
    return new Response(JSON.stringify({ message: "All recipients blocked" }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  }

  // 4. Query active devices registered to eligible recipients
  const { data: devices, error: devicesError } = await supabase
    .from("user_devices")
    .select("id, user_id, fcm_token, platform, discreet, notifications_enabled")
    .in("user_id", eligibleRecipientIds)
    .eq("notifications_enabled", true);

  if (devicesError || !devices || devices.length === 0) {
    console.log(`[PushServer] No active devices found for recipients: ${eligibleRecipientIds.length}`);
    return new Response(JSON.stringify({ message: "No active devices" }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  }

  // 5. Query sender username for discreet = false notifications
  let senderUsername: string | null = null;
  try {
    const { data: profile } = await supabase
      .from("profiles")
      .select("username")
      .eq("id", record.sender_id)
      .maybeSingle();
    if (profile && profile.username) {
      senderUsername = profile.username;
    }
  } catch (_) {}

  // 6. Obtain FCM OAuth2 token
  let fcmAccessToken: string;
  try {
    fcmAccessToken = await getFCMAccessToken(serviceAccount);
  } catch (err) {
    console.error("[PushServer] Error minting FCM token:", err);
    return new Response(
      JSON.stringify({ error: "FCM authentication error" }),
      { status: 502, headers: { "Content-Type": "application/json" } }
    );
  }

  // 7. Resolve privacy-safe body preview based on message type
  let previewBody: string;
  switch (record.message_type) {
    case "image":
      previewBody = "📷 Photo";
      break;
    case "view_once_image":
      previewBody = "🔒 Photo (View once)";
      break;
    case "audio":
      previewBody = "🎤 Voice message";
      break;
    case "document":
      previewBody = "📄 Document";
      break;
    default:
      previewBody = "New message received";
      break;
  }

  const fcmEndpoint = `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`;
  const results: { deviceId: string; status: string; error?: string }[] = [];

  for (const device of devices) {
    // Idempotency: skip if already sent or pending
    const { data: existingDelivery } = await supabase
      .from("push_deliveries")
      .select("id, status")
      .eq("message_id", record.id)
      .eq("device_id", device.id)
      .maybeSingle();

    if (existingDelivery && (existingDelivery.status === "sent" || existingDelivery.status === "pending")) {
      console.log(`[PushServer] Message ${record.id} already delivered to device ${device.id}, skipping duplicate`);
      continue;
    }

    // Determine title & body based on user's discreet setting
    const isDiscreet = Boolean(device.discreet);
    const notifTitle = isDiscreet
      ? "AnonApp"
      : senderUsername
      ? `@${senderUsername}`
      : "AnonApp";
    const notifBody = isDiscreet ? "New message received" : previewBody;

    // Construct FCM v1 payload: Notification + Data (Strictly generic; NO plaintext or ciphertext!)
    const fcmPayload = {
      message: {
        token: device.fcm_token,
        notification: {
          title: notifTitle,
          body: notifBody,
        },
        data: {
          message_id: record.id,
          conversation_id: record.conversation_id,
          sender_id: record.sender_id,
          message_type: record.message_type || "text",
          sender_username: senderUsername || "",
        },
        android: {
          priority: "HIGH",
          notification: {
            channel_id: "anonapp_messages",
            icon: "ic_stat_notification",
            click_action: "FLUTTER_NOTIFICATION_CLICK",
            tag: `anonapp_conv_${record.conversation_id}`,
          },
        },
      },
    };

    console.log(
      `[PushServer] Sending FCM to device ${device.id} (token: ${maskToken(device.fcm_token)}) for message ${record.id}`
    );

    try {
      const fcmResponse = await fetch(fcmEndpoint, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${fcmAccessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(fcmPayload),
      });

      if (fcmResponse.ok) {
        const responseData = await fcmResponse.json();
        console.log(`[PushServer] FCM sent successfully to device ${device.id}: ${responseData.name}`);

        await supabase.from("push_deliveries").upsert(
          {
            message_id: record.id,
            device_id: device.id,
            recipient_user_id: device.user_id,
            status: "sent",
            fcm_message_name: responseData.name,
            updated_at: new Date().toISOString(),
          },
          { onConflict: "message_id,device_id" }
        );

        results.push({ deviceId: device.id, status: "sent" });
      } else {
        const errJson = await fcmResponse.json().catch(() => ({}));
        const status = fcmResponse.status;
        const errorCode =
          errJson?.error?.details?.[0]?.errorCode ||
          errJson?.error?.status ||
          `HTTP_${status}`;
        const errorMessage = errJson?.error?.message || "FCM send error";

        console.error(
          `[PushServer] FCM error for device ${device.id} (${maskToken(device.fcm_token)}): ${errorCode} - ${errorMessage}`
        );

        // Deactivate invalid or unregistered tokens immediately
        const isUnregistered =
          errorCode === "UNREGISTERED" ||
          errorCode === "NOT_FOUND" ||
          errorMessage.includes("Requested entity was not found") ||
          errorMessage.includes("registration token is not a valid FCM registration token");

        if (isUnregistered) {
          console.log(`[PushServer] Deactivating invalid token for device ${device.id}`);
          await supabase
            .from("user_devices")
            .update({ notifications_enabled: false, updated_at: new Date().toISOString() })
            .eq("id", device.id);
        }

        await supabase.from("push_deliveries").upsert(
          {
            message_id: record.id,
            device_id: device.id,
            recipient_user_id: device.user_id,
            status: isUnregistered ? "invalid_token" : "failed",
            error_code: errorCode,
            error_message: errorMessage,
            updated_at: new Date().toISOString(),
          },
          { onConflict: "message_id,device_id" }
        );

        results.push({
          deviceId: device.id,
          status: isUnregistered ? "invalid_token" : "failed",
          error: errorCode,
        });
      }
    } catch (sendErr) {
      console.error(`[PushServer] Network error dispatching to device ${device.id}:`, sendErr);
      results.push({
        deviceId: device.id,
        status: "failed",
        error: String(sendErr),
      });
    }
  }

  return new Response(
    JSON.stringify({
      message: "Push dispatch complete",
      message_id: record.id,
      recipients: eligibleRecipientIds.length,
      devicesTargeted: devices.length,
      results,
    }),
    { status: 200, headers: { "Content-Type": "application/json" } }
  );
});
