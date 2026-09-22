-- ============================================================
-- AnonApp — Migration 00010: Push Notifications & Device Registry
--
-- Architecture:
--   messages INSERT -> Database Webhook -> Supabase Edge Function (send-push) -> FCM HTTP v1 -> Android System Tray
--
-- Tables:
--   1. public.user_devices: Device registrations per user
--   2. public.push_deliveries: Delivery tracking & idempotency log
-- ============================================================

-- ── 1. USER DEVICES TABLE ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.user_devices (
  id                    UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id               UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  installation_id       TEXT        NOT NULL,
  fcm_token             TEXT        NOT NULL,
  platform              TEXT        NOT NULL DEFAULT 'android' CHECK (platform IN ('android', 'ios', 'web')),
  device_model          TEXT,
  os_version            TEXT,
  app_version           TEXT,
  notifications_enabled BOOLEAN     NOT NULL DEFAULT true,
  discreet              BOOLEAN     NOT NULL DEFAULT false,
  last_seen_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_token_refresh_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_user_device_installation UNIQUE (user_id, installation_id)
);

-- Indexes for quick lookup during message dispatch
CREATE INDEX IF NOT EXISTS idx_user_devices_user_active
  ON public.user_devices (user_id)
  WHERE notifications_enabled = true;

CREATE INDEX IF NOT EXISTS idx_user_devices_fcm_token
  ON public.user_devices (fcm_token);

-- Auto-update updated_at timestamp trigger
CREATE OR REPLACE FUNCTION public.handle_user_devices_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_user_devices_updated_at ON public.user_devices;
CREATE TRIGGER trg_user_devices_updated_at
  BEFORE UPDATE ON public.user_devices
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_user_devices_updated_at();

-- ── Row Level Security: user_devices ──────────────────────────
ALTER TABLE public.user_devices ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "user_devices_select_own" ON public.user_devices;
CREATE POLICY "user_devices_select_own"
  ON public.user_devices
  FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "user_devices_insert_own" ON public.user_devices;
CREATE POLICY "user_devices_insert_own"
  ON public.user_devices
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "user_devices_update_own" ON public.user_devices;
CREATE POLICY "user_devices_update_own"
  ON public.user_devices
  FOR UPDATE
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "user_devices_delete_own" ON public.user_devices;
CREATE POLICY "user_devices_delete_own"
  ON public.user_devices
  FOR DELETE
  USING (auth.uid() = user_id);


-- ── 2. PUSH DELIVERIES TABLE (Idempotency & Auditing) ──────────
CREATE TABLE IF NOT EXISTS public.push_deliveries (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id        UUID        NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
  device_id         UUID        NOT NULL REFERENCES public.user_devices(id) ON DELETE CASCADE,
  recipient_user_id UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status            TEXT        NOT NULL CHECK (status IN ('pending', 'sent', 'failed', 'invalid_token')),
  fcm_message_name  TEXT,
  error_code        TEXT,
  error_message     TEXT,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_push_delivery_msg_device UNIQUE (message_id, device_id)
);

CREATE INDEX IF NOT EXISTS idx_push_deliveries_lookup
  ON public.push_deliveries (message_id, device_id);

CREATE INDEX IF NOT EXISTS idx_push_deliveries_recipient
  ON public.push_deliveries (recipient_user_id, created_at DESC);

-- RLS: push_deliveries
ALTER TABLE public.push_deliveries ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "push_deliveries_select_own" ON public.push_deliveries;
CREATE POLICY "push_deliveries_select_own"
  ON public.push_deliveries
  FOR SELECT
  USING (auth.uid() = recipient_user_id);

-- ── 3. OPTIONAL PG_NET DATABASE WEBHOOK TRIGGER ───────────────
-- When pg_net extension is enabled, this trigger calls the send-push
-- Edge Function automatically on message INSERT.
-- Alternatively, configure via Supabase Dashboard:
-- Database -> Webhooks -> Create Webhook on `public.messages` INSERT -> Edge Function `send-push`
CREATE OR REPLACE FUNCTION public.notify_send_push()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_payload JSONB;
  v_request_id BIGINT;
  v_supabase_url TEXT;
  v_anon_key TEXT;
BEGIN
  -- Discard messages marked deleted immediately or expired
  IF NEW.deleted_at IS NOT NULL OR (NEW.expires_at IS NOT NULL AND NEW.expires_at <= now()) THEN
    RETURN NEW;
  END IF;

  -- Discard system messages
  IF NEW.message_type = 'system' THEN
    RETURN NEW;
  END IF;

  v_payload := jsonb_build_object(
    'type', 'INSERT',
    'table', 'messages',
    'schema', 'public',
    'record', jsonb_build_object(
      'id', NEW.id,
      'conversation_id', NEW.conversation_id,
      'sender_id', NEW.sender_id,
      'message_type', NEW.message_type,
      'created_at', NEW.created_at,
      'expires_at', NEW.expires_at,
      'deleted_at', NEW.deleted_at
    )
  );

  -- Safe execution if pg_net extension exists
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_net') THEN
    SELECT current_setting('app.settings.supabase_url', true) INTO v_supabase_url;
    SELECT current_setting('app.settings.service_role_key', true) INTO v_anon_key;

    IF v_supabase_url IS NOT NULL AND v_anon_key IS NOT NULL THEN
      PERFORM net.http_post(
        url := v_supabase_url || '/functions/v1/send-push',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || v_anon_key
        ),
        body := v_payload,
        timeout_milliseconds := 5000
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_messages_send_push ON public.messages;
CREATE TRIGGER trg_messages_send_push
  AFTER INSERT ON public.messages
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_send_push();
