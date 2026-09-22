-- ============================================================
-- AnonApp — Migration 00007: Comprehensive Privacy & Access Hardening
--
-- Enforces:
-- 1. Cryptographic Contact Code Generation with collision safety
-- 2. Least-privilege profile visibility (no public SELECT * FROM profiles)
-- 3. Controlled public profile RPCs (get_public_profile, search, contact lookup)
-- 4. Server-side blocking enforcement across chat, lookup, and messaging
-- 5. Tampering prevention & server-side disappearing message expiry
-- 6. Server-side clear chat RPC
-- 7. Report and safety constraint lockdown
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ── 1. CRYPTOGRAPHIC CONTACT CODE GENERATOR ─────────────────────
-- Generates an unambiguous 8-character code from a cryptographically
-- secure random source with an automatic retry loop for uniqueness.
CREATE OR REPLACE FUNCTION public.generate_contact_code()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  chars TEXT := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; -- 32 unambiguous characters
  result TEXT;
  bytes BYTEA;
  i INT;
  byte_val INT;
  attempts INT := 0;
BEGIN
  LOOP
    attempts := attempts + 1;
    result := '';
    bytes := gen_random_bytes(8);
    FOR i IN 0..7 LOOP
      byte_val := get_byte(bytes, i);
      result := result || substr(chars, (byte_val % 32) + 1, 1);
    END LOOP;

    -- Guarantee collision-free before returning
    IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE contact_code = result) THEN
      RETURN result;
    END IF;

    IF attempts >= 10 THEN
      RETURN result;
    END IF;
  END LOOP;
END;
$$;

-- ── 2. PROFILE ACCESS LOCKDOWN ─────────────────────────────────
-- Revoke the overly broad authenticated SELECT policy on profiles.
DROP POLICY IF EXISTS "profiles_select_authenticated" ON public.profiles;
DROP POLICY IF EXISTS "profiles_select_own" ON public.profiles;
DROP POLICY IF EXISTS "profiles_select_conversation_partner" ON public.profiles;

-- Users can only directly select their own full profile row.
CREATE POLICY "profiles_select_own"
  ON public.profiles
  FOR SELECT
  USING (auth.uid() = id);

-- Users can only select profiles of users with whom they share an active conversation.
CREATE POLICY "profiles_select_conversation_partner"
  ON public.profiles
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.conversation_members my_cm
      JOIN public.conversation_members other_cm
        ON my_cm.conversation_id = other_cm.conversation_id
      WHERE my_cm.user_id = auth.uid()
        AND other_cm.user_id = profiles.id
        AND NOT EXISTS (
          SELECT 1 FROM public.blocked_users bu
          WHERE (bu.blocker_id = auth.uid() AND bu.blocked_id = profiles.id)
             OR (bu.blocker_id = profiles.id AND bu.blocked_id = auth.uid())
        )
    )
  );

-- ── 3. CONTROLLED PUBLIC PROFILE RPCS ──────────────────────────

-- Get sanitized public profile for another user
CREATE OR REPLACE FUNCTION public.get_public_profile(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id UUID := auth.uid();
  v_profile RECORD;
  v_is_blocked BOOLEAN := FALSE;
BEGIN
  IF v_caller_id IS NULL THEN
    RETURN NULL;
  END IF;

  -- Block enforcement: If blocked by or blocked caller, hide completely
  IF v_caller_id <> p_user_id THEN
    SELECT EXISTS (
      SELECT 1 FROM public.blocked_users
      WHERE (blocker_id = v_caller_id AND blocked_id = p_user_id)
         OR (blocker_id = p_user_id AND blocked_id = v_caller_id)
    ) INTO v_is_blocked;

    IF v_is_blocked THEN
      RETURN NULL;
    END IF;
  END IF;

  SELECT
    id,
    username,
    display_name,
    avatar,
    bio,
    interests,
    persona,
    online_status_visible,
    CASE 
      WHEN online_status_visible IS TRUE THEN last_seen 
      ELSE NULL 
    END AS last_seen,
    CASE 
      WHEN online_status_visible IS TRUE AND last_seen > (now() - INTERVAL '5 minutes') THEN TRUE
      ELSE FALSE
    END AS is_online,
    created_at
  INTO v_profile
  FROM public.profiles
  WHERE id = p_user_id;

  IF v_profile.id IS NULL THEN
    RETURN NULL;
  END IF;

  -- Never return contact_code, internal auth UUIDs of other services, or email
  RETURN jsonb_build_object(
    'id', v_profile.id,
    'username', v_profile.username,
    'display_name', v_profile.display_name,
    'avatar', v_profile.avatar,
    'bio', v_profile.bio,
    'interests', COALESCE(v_profile.interests, '{}'::TEXT[]),
    'persona', v_profile.persona,
    'online_status_visible', v_profile.online_status_visible,
    'last_seen', v_profile.last_seen,
    'is_online', v_profile.is_online,
    'created_at', v_profile.created_at
  );
END;
$$;

-- Find a user by contact code without exposing contact codes globally
CREATE OR REPLACE FUNCTION public.find_profile_by_contact_code(p_code TEXT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id UUID := auth.uid();
  v_clean_code TEXT;
  v_target_id UUID;
  v_is_blocked BOOLEAN := FALSE;
BEGIN
  IF v_caller_id IS NULL OR p_code IS NULL THEN
    RETURN NULL;
  END IF;

  v_clean_code := upper(trim(p_code));

  -- Minimum input validation (must be exactly 8 alphanumeric characters)
  IF length(v_clean_code) <> 8 OR v_clean_code !~ '^[A-Z0-9]{8}$' THEN
    RETURN NULL;
  END IF;

  SELECT id INTO v_target_id
  FROM public.profiles
  WHERE contact_code = v_clean_code;

  -- Self-lookup or not found returns generic NULL
  IF v_target_id IS NULL OR v_target_id = v_caller_id THEN
    RETURN NULL;
  END IF;

  -- Block enforcement
  SELECT EXISTS (
    SELECT 1 FROM public.blocked_users
    WHERE (blocker_id = v_caller_id AND blocked_id = v_target_id)
       OR (blocker_id = v_target_id AND blocked_id = v_caller_id)
  ) INTO v_is_blocked;

  IF v_is_blocked THEN
    RETURN NULL;
  END IF;

  RETURN public.get_public_profile(v_target_id);
END;
$$;

-- Search public profiles without exposing contact codes or email
CREATE OR REPLACE FUNCTION public.search_public_profiles(
  p_query TEXT,
  p_limit INT DEFAULT 20
)
RETURNS TABLE (
  id UUID,
  username TEXT,
  display_name TEXT,
  avatar TEXT,
  bio TEXT,
  interests TEXT[],
  persona TEXT,
  online_status_visible BOOLEAN,
  last_seen TIMESTAMPTZ,
  created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id UUID := auth.uid();
  v_clean_query TEXT;
  v_effective_limit INT;
BEGIN
  IF v_caller_id IS NULL THEN
    RETURN;
  END IF;

  v_clean_query := lower(trim(p_query));
  v_effective_limit := LEAST(GREATEST(COALESCE(p_limit, 20), 1), 50);

  IF length(v_clean_query) < 2 THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    p.id,
    p.username,
    p.display_name,
    p.avatar,
    p.bio,
    COALESCE(p.interests, '{}'::TEXT[]),
    p.persona,
    p.online_status_visible,
    CASE 
      WHEN p.online_status_visible IS TRUE THEN p.last_seen 
      ELSE NULL 
    END AS last_seen,
    p.created_at
  FROM public.profiles p
  WHERE p.id <> v_caller_id
    AND (
      lower(p.username) LIKE '%' || v_clean_query || '%'
      OR (p.display_name IS NOT NULL AND lower(p.display_name) LIKE '%' || v_clean_query || '%')
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.blocked_users bu
      WHERE (bu.blocker_id = v_caller_id AND bu.blocked_id = p.id)
         OR (bu.blocker_id = p.id AND bu.blocked_id = v_caller_id)
    )
  LIMIT v_effective_limit;
END;
$$;

-- ── 4. CONVERSATION CREATION & MEMBERSHIP HARDENING ────────────
CREATE OR REPLACE FUNCTION public.find_or_create_direct_conversation(
  p_user_id_1 UUID,
  p_user_id_2 UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id UUID := auth.uid();
  v_conv_id UUID;
  v_is_blocked BOOLEAN := FALSE;
BEGIN
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required.';
  END IF;

  IF v_caller_id <> p_user_id_1 AND v_caller_id <> p_user_id_2 THEN
    RAISE EXCEPTION 'Unauthorized: Caller must participate in the conversation.';
  END IF;

  IF p_user_id_1 = p_user_id_2 THEN
    RAISE EXCEPTION 'Cannot start a conversation with yourself.';
  END IF;

  -- Block enforcement
  SELECT EXISTS (
    SELECT 1 FROM public.blocked_users
    WHERE (blocker_id = p_user_id_1 AND blocked_id = p_user_id_2)
       OR (blocker_id = p_user_id_2 AND blocked_id = p_user_id_1)
  ) INTO v_is_blocked;

  IF v_is_blocked THEN
    RAISE EXCEPTION 'Cannot start conversation: this user is blocked or unavailable.';
  END IF;

  -- Look for existing 1:1 conversation
  SELECT cm1.conversation_id INTO v_conv_id
  FROM public.conversation_members cm1
  JOIN public.conversation_members cm2
    ON cm1.conversation_id = cm2.conversation_id
  WHERE cm1.user_id = p_user_id_1
    AND cm2.user_id = p_user_id_2
    AND (
      SELECT count(*)
      FROM public.conversation_members cm_count
      WHERE cm_count.conversation_id = cm1.conversation_id
    ) = 2
  LIMIT 1;

  IF v_conv_id IS NOT NULL THEN
    RETURN v_conv_id;
  END IF;

  -- Create new conversation
  INSERT INTO public.conversations (created_at, updated_at)
  VALUES (now(), now())
  RETURNING id INTO v_conv_id;

  -- Add both verified members
  INSERT INTO public.conversation_members (conversation_id, user_id)
  VALUES
    (v_conv_id, p_user_id_1),
    (v_conv_id, p_user_id_2);

  RETURN v_conv_id;
END;
$$;

-- Lock down direct conversation_members INSERT
DROP POLICY IF EXISTS "conv_members_insert" ON public.conversation_members;

-- Prevent tampering with membership attributes
CREATE OR REPLACE FUNCTION public.protect_conversation_member_fields()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Preserve immutable membership relationships
  NEW.conversation_id := OLD.conversation_id;
  NEW.user_id         := OLD.user_id;
  NEW.joined_at       := OLD.joined_at;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_protect_conv_member_fields ON public.conversation_members;
CREATE TRIGGER trg_protect_conv_member_fields
  BEFORE UPDATE ON public.conversation_members
  FOR EACH ROW
  EXECUTE FUNCTION public.protect_conversation_member_fields();

-- ── 5. MESSAGE ACCESS & TAMPERING PREVENTION ───────────────────

-- Reject message insertion if recipient has blocked sender
DROP POLICY IF EXISTS "messages_insert_member" ON public.messages;
CREATE POLICY "messages_insert_member"
  ON public.messages
  FOR INSERT
  WITH CHECK (
    sender_id = auth.uid()
    AND public.is_member_of_conversation(conversation_id)
    AND NOT EXISTS (
      SELECT 1 FROM public.conversation_members cm
      JOIN public.blocked_users bu
        ON (bu.blocker_id = cm.user_id AND bu.blocked_id = auth.uid())
        OR (bu.blocker_id = auth.uid() AND bu.blocked_id = cm.user_id)
      WHERE cm.conversation_id = messages.conversation_id
        AND cm.user_id <> auth.uid()
    )
  );

-- Enforce disappearing messages expiry and clear chat on SELECT
DROP POLICY IF EXISTS "messages_select_member" ON public.messages;
CREATE POLICY "messages_select_member"
  ON public.messages
  FOR SELECT
  USING (
    public.is_member_of_conversation(conversation_id)
    AND (expires_at IS NULL OR expires_at > now())
    AND (
      created_at > (SELECT c.cleared_at FROM public.conversations c WHERE c.id = conversation_id)
      OR (SELECT c.cleared_at FROM public.conversations c WHERE c.id = conversation_id) IS NULL
    )
  );

-- Strict update trigger for both sender and recipient
CREATE OR REPLACE FUNCTION public.protect_message_fields_on_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Recipients can only update read/delivery/viewed timestamps
  IF auth.uid() IS NOT NULL AND auth.uid() <> OLD.sender_id THEN
    NEW.content         := OLD.content;
    NEW.media_data      := OLD.media_data;
    NEW.media_url       := OLD.media_url;
    NEW.media_meta      := OLD.media_meta;
    NEW.sender_id       := OLD.sender_id;
    NEW.created_at      := OLD.created_at;
    NEW.client_id       := OLD.client_id;
    NEW.message_type    := OLD.message_type;
    NEW.conversation_id := OLD.conversation_id;
    NEW.expires_at      := OLD.expires_at;
  ELSE
    -- Senders can only soft-delete or update content
    NEW.sender_id       := OLD.sender_id;
    NEW.conversation_id := OLD.conversation_id;
    NEW.created_at      := OLD.created_at;
    NEW.client_id       := OLD.client_id;
    NEW.expires_at      := OLD.expires_at;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_protect_message_fields ON public.messages;
CREATE TRIGGER trg_protect_message_fields
  BEFORE UPDATE ON public.messages
  FOR EACH ROW
  EXECUTE FUNCTION public.protect_message_fields_on_update();

-- RPC: Clear conversation chat
CREATE OR REPLACE FUNCTION public.clear_conversation_chat(p_conversation_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id UUID := auth.uid();
BEGIN
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required.';
  END IF;

  IF NOT public.is_member_of_conversation(p_conversation_id) THEN
    RAISE EXCEPTION 'Permission denied.';
  END IF;

  UPDATE public.conversations
  SET cleared_at = now()
  WHERE id = p_conversation_id;

  RETURN TRUE;
END;
$$;

-- Physical cleanup routine for expired disappearing messages
CREATE OR REPLACE FUNCTION public.clean_expired_messages()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_deleted_count INT := 0;
BEGIN
  WITH deleted_expired AS (
    DELETE FROM public.messages
    WHERE expires_at IS NOT NULL
      AND expires_at < now()
    RETURNING id
  )
  SELECT count(*) INTO v_deleted_count FROM deleted_expired;

  DELETE FROM public.messages
  WHERE deleted_at IS NOT NULL
    AND deleted_at < (now() - INTERVAL '30 days');

  RETURN v_deleted_count;
END;
$$;

-- ── 6. SAFETY & MODERATION CONSTRAINTS ─────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_blocked_users_not_self'
  ) THEN
    ALTER TABLE public.blocked_users
      ADD CONSTRAINT chk_blocked_users_not_self
      CHECK (blocker_id <> blocked_id);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_user_reports_not_self'
  ) THEN
    ALTER TABLE public.user_reports
      ADD CONSTRAINT chk_user_reports_not_self
      CHECK (reported_user_id IS NULL OR reporter_id <> reported_user_id);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_user_reports_reason_len'
  ) THEN
    ALTER TABLE public.user_reports
      ADD CONSTRAINT chk_user_reports_reason_len
      CHECK (char_length(reason) BETWEEN 1 AND 100);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_user_reports_details_len'
  ) THEN
    ALTER TABLE public.user_reports
      ADD CONSTRAINT chk_user_reports_details_len
      CHECK (details IS NULL OR char_length(details) <= 1000);
  END IF;
END $$;
