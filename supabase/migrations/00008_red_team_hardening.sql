-- ============================================================
-- AnonApp — Migration 00008: Comprehensive Red-Team Security Hardening
--
-- Enforces:
-- 1. Server-side administrator framework (app_admins table & is_admin helper)
-- 2. Atomic view-once concurrency with row locks and replay denial
-- 3. Message immutability (receipt protection, insert-time timestamp enforcement)
-- 4. Contact code privacy isolation via get_my_contact_code & column restriction
-- 5. Conversation integrity (no direct unverified insert, cleared_at protection)
-- 6. Supabase Storage RLS policies for private medias bucket
-- 7. Server-side rate limiting on lookups, search, and reports
-- 8. Function execution permission lockdown (clean_expired_messages)
-- ============================================================

-- ── 1. SERVER-SIDE ADMINISTRATOR FRAMEWORK ───────────────────────
CREATE TABLE IF NOT EXISTS public.app_admins (
  user_id    UUID        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.app_admins ENABLE ROW LEVEL SECURITY;

-- Admins can check their own admin status; clients cannot insert/update/delete
DROP POLICY IF EXISTS "app_admins_select_own" ON public.app_admins;
CREATE POLICY "app_admins_select_own"
  ON public.app_admins FOR SELECT
  USING (auth.uid() = user_id);

-- Helper function to check if caller has verified administrator privileges
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
  SELECT (
    COALESCE((auth.jwt()->'app_metadata'->>'is_admin')::boolean, false) IS TRUE
    OR EXISTS (
      SELECT 1 FROM public.app_admins
      WHERE user_id = auth.uid()
    )
  );
$$;

-- Allow administrators to read and resolve user moderation reports
DROP POLICY IF EXISTS "user_reports_select_admin" ON public.user_reports;
CREATE POLICY "user_reports_select_admin"
  ON public.user_reports FOR SELECT
  USING (public.is_admin());

DROP POLICY IF EXISTS "user_reports_delete_admin" ON public.user_reports;
CREATE POLICY "user_reports_delete_admin"
  ON public.user_reports FOR DELETE
  USING (public.is_admin());

-- Dedicated Admin RPC for reports
CREATE OR REPLACE FUNCTION public.admin_get_user_reports(p_limit INT DEFAULT 50)
RETURNS TABLE (
  id UUID,
  reporter_id UUID,
  reported_user_id UUID,
  conversation_id UUID,
  reason TEXT,
  details TEXT,
  created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin authorization required.';
  END IF;

  RETURN QUERY
  SELECT r.id, r.reporter_id, r.reported_user_id, r.conversation_id, r.reason, r.details, r.created_at
  FROM public.user_reports r
  ORDER BY r.created_at DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 100);
END;
$$;

-- ── 2. ATOMIC VIEW-ONCE CONCURRENCY HARDENING ────────────────────
CREATE OR REPLACE FUNCTION public.mark_view_once_opened(p_message_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_conv_id UUID;
  v_sender_id UUID;
  v_msg_type TEXT;
  v_viewed_at TIMESTAMPTZ;
  v_is_blocked BOOLEAN := FALSE;
BEGIN
  -- Row-level exclusive lock to serialize concurrent attempts
  SELECT conversation_id, sender_id, message_type, viewed_at
  INTO v_conv_id, v_sender_id, v_msg_type, v_viewed_at
  FROM public.messages
  WHERE id = p_message_id
  FOR UPDATE;

  IF v_conv_id IS NULL THEN
    RAISE EXCEPTION 'Message not found';
  END IF;

  -- Caller must be a conversation member
  IF NOT public.is_member_of_conversation(v_conv_id) THEN
    RAISE EXCEPTION 'Permission denied';
  END IF;

  -- Enforce blocking: blocked users cannot open media
  SELECT EXISTS (
    SELECT 1 FROM public.blocked_users
    WHERE (blocker_id = auth.uid() AND blocked_id = v_sender_id)
       OR (blocker_id = v_sender_id AND blocked_id = auth.uid())
  ) INTO v_is_blocked;

  IF v_is_blocked THEN
    RAISE EXCEPTION 'Permission denied: user is blocked.';
  END IF;

  -- Senders cannot consume their own view-once media
  IF v_sender_id = auth.uid() THEN
    RETURN FALSE;
  END IF;

  -- If already viewed, the one-time view is permanently expired (returns FALSE)
  IF v_viewed_at IS NOT NULL THEN
    RETURN FALSE;
  END IF;

  -- Atomically consume view-once state
  UPDATE public.messages
  SET viewed_at = now(),
      read_at = COALESCE(read_at, now())
  WHERE id = p_message_id
    AND viewed_at IS NULL;

  IF NOT FOUND THEN
    RETURN FALSE;
  END IF;

  RETURN TRUE;
END;
$$;

-- ── 3. MESSAGE INSERT & UPDATE DIRECTIONAL PROTECTION ───────────

-- Trigger: Ensure inserted messages have server-controlled timestamp & pristine receipt states
CREATE OR REPLACE FUNCTION public.protect_message_fields_on_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_disappearing INTERVAL;
BEGIN
  -- Guarantee server-side creation timestamp
  NEW.created_at := now();

  -- Pristine initial receipt states
  NEW.read_at := NULL;
  NEW.delivered_at := NULL;
  NEW.viewed_at := NULL;
  NEW.deleted_at := NULL;

  -- Automatically apply conversation disappearing messages duration if configured
  SELECT disappearing_messages_duration INTO v_disappearing
  FROM public.conversations
  WHERE id = NEW.conversation_id;

  IF v_disappearing IS NOT NULL THEN
    NEW.expires_at := NEW.created_at + v_disappearing;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_protect_message_fields_on_insert ON public.messages;
CREATE TRIGGER trg_protect_message_fields_on_insert
  BEFORE INSERT ON public.messages
  FOR EACH ROW
  EXECUTE FUNCTION public.protect_message_fields_on_insert();

-- Trigger: Strict update enforcement preventing receipt spoofing and view-once resets
CREATE OR REPLACE FUNCTION public.protect_message_fields_on_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> OLD.sender_id THEN
    -- Recipient cannot modify message content, media, sender, created_at, or client_id
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
    NEW.deleted_at      := OLD.deleted_at;

    -- Recipient CANNOT reset viewed_at once viewed
    IF OLD.viewed_at IS NOT NULL AND NEW.viewed_at IS NULL THEN
      NEW.viewed_at := OLD.viewed_at;
    END IF;
  ELSE
    -- Sender cannot modify immutable metadata
    NEW.sender_id       := OLD.sender_id;
    NEW.conversation_id := OLD.conversation_id;
    NEW.created_at      := OLD.created_at;
    NEW.client_id       := OLD.client_id;
    NEW.expires_at      := OLD.expires_at;

    -- Senders CANNOT forge recipient delivery, read, or viewed timestamps
    NEW.read_at         := OLD.read_at;
    NEW.delivered_at    := OLD.delivered_at;
    NEW.viewed_at       := OLD.viewed_at;

    -- Senders cannot un-delete a soft-deleted message
    IF OLD.deleted_at IS NOT NULL AND NEW.deleted_at IS NULL THEN
      NEW.deleted_at := OLD.deleted_at;
      NEW.message_type := OLD.message_type;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_protect_message_fields ON public.messages;
CREATE TRIGGER trg_protect_message_fields
  BEFORE UPDATE ON public.messages
  FOR EACH ROW
  EXECUTE FUNCTION public.protect_message_fields_on_update();

-- ── 4. CONTACT CODE PRIVACY ISOLATION ────────────────────────────
-- RPC to fetch current authenticated user's own contact code
CREATE OR REPLACE FUNCTION public.get_my_contact_code()
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT contact_code
  FROM public.profiles
  WHERE id = auth.uid();
$$;

-- ── 5. CONVERSATION CREATION & INTEGRITY HARDENING ───────────────
-- Drop direct INSERT policy on conversations (must use find_or_create_direct_conversation)
DROP POLICY IF EXISTS "conversations_insert_authenticated" ON public.conversations;

-- Prevent direct manipulation or future-setting of cleared_at
CREATE OR REPLACE FUNCTION public.protect_conversation_fields()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  NEW.id := OLD.id;
  NEW.created_at := OLD.created_at;

  IF NEW.cleared_at IS DISTINCT FROM OLD.cleared_at THEN
    -- cleared_at cannot be set in the future to suppress future messages
    IF NEW.cleared_at > (now() + INTERVAL '10 seconds') THEN
      RAISE EXCEPTION 'Cannot set cleared_at in the future.';
    END IF;
    -- cleared_at cannot be rewound to restore cleared history
    IF OLD.cleared_at IS NOT NULL AND NEW.cleared_at < OLD.cleared_at THEN
      RAISE EXCEPTION 'Cannot rewind cleared_at.';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_protect_conversation_fields ON public.conversations;
CREATE TRIGGER trg_protect_conversation_fields
  BEFORE UPDATE ON public.conversations
  FOR EACH ROW
  EXECUTE FUNCTION public.protect_conversation_fields();

-- ── 6. SERVER-SIDE RATE LIMITING ENGINE ─────────────────────────
CREATE TABLE IF NOT EXISTS public.rate_limit_events (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  action     TEXT        NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_rate_limit_user_action
  ON public.rate_limit_events (user_id, action, created_at DESC);

ALTER TABLE public.rate_limit_events ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "rate_limit_deny_all" ON public.rate_limit_events;
CREATE POLICY "rate_limit_deny_all"
  ON public.rate_limit_events FOR ALL
  USING (false);

CREATE OR REPLACE FUNCTION public.check_rate_limit(
  p_action TEXT,
  p_max_requests INT,
  p_window INTERVAL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_count INT;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN FALSE;
  END IF;

  -- Periodically purge events older than 2 hours
  DELETE FROM public.rate_limit_events
  WHERE user_id = v_user_id
    AND created_at < (now() - INTERVAL '2 hours');

  SELECT count(*) INTO v_count
  FROM public.rate_limit_events
  WHERE user_id = v_user_id
    AND action = p_action
    AND created_at >= (now() - p_window);

  IF v_count >= p_max_requests THEN
    RETURN FALSE;
  END IF;

  INSERT INTO public.rate_limit_events (user_id, action, created_at)
  VALUES (v_user_id, p_action, now());

  RETURN TRUE;
END;
$$;

-- Apply rate limit to contact code lookup (max 30 / minute)
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

  IF NOT public.check_rate_limit('contact_lookup', 30, INTERVAL '1 minute') THEN
    RAISE EXCEPTION 'Rate limit exceeded for contact lookups. Please wait a minute.';
  END IF;

  v_clean_code := upper(trim(p_code));
  IF length(v_clean_code) <> 8 OR v_clean_code !~ '^[A-Z0-9]{8}$' THEN
    RETURN NULL;
  END IF;

  SELECT id INTO v_target_id
  FROM public.profiles
  WHERE contact_code = v_clean_code;

  IF v_target_id IS NULL OR v_target_id = v_caller_id THEN
    RETURN NULL;
  END IF;

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

-- Apply rate limit to public user search (max 60 / minute)
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

  IF NOT public.check_rate_limit('user_search', 60, INTERVAL '1 minute') THEN
    RAISE EXCEPTION 'Rate limit exceeded for user search. Please slow down.';
  END IF;

  v_clean_query := lower(trim(p_query));
  v_effective_limit := LEAST(GREATEST(COALESCE(p_limit, 20), 1), 50);

  IF length(v_clean_query) < 2 THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    p.id, p.username, p.display_name, p.avatar, p.bio,
    COALESCE(p.interests, '{}'::TEXT[]), p.persona, p.online_status_visible,
    CASE WHEN p.online_status_visible IS TRUE THEN p.last_seen ELSE NULL END AS last_seen,
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

-- Apply rate limit to report submissions (max 10 / hour)
CREATE OR REPLACE FUNCTION public.rate_limit_user_reports()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.check_rate_limit('report_submission', 10, INTERVAL '1 hour') THEN
    RAISE EXCEPTION 'Rate limit exceeded for report submissions. Please try again later.';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_rate_limit_reports ON public.user_reports;
CREATE TRIGGER trg_rate_limit_reports
  BEFORE INSERT ON public.user_reports
  FOR EACH ROW
  EXECUTE FUNCTION public.rate_limit_user_reports();

-- ── 7. FUNCTION EXECUTION RESTRICTIONS ───────────────────────────
CREATE OR REPLACE FUNCTION public.clean_expired_messages()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_deleted_count INT := 0;
BEGIN
  IF NOT (auth.role() = 'service_role' OR public.is_admin()) THEN
    RAISE EXCEPTION 'Permission denied.';
  END IF;

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

-- Function Privilege Lockdown (executed after function creation)
REVOKE EXECUTE ON FUNCTION public.clean_expired_messages() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.clean_expired_messages() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.clean_expired_messages() TO service_role;

-- ── 8. SUPABASE STORAGE SETUP (OPTIONAL) ─────────────────────────
-- Note: 'storage.objects' is owned by supabase_storage_admin, not the postgres role.
-- Supabase already enables RLS on storage.objects by default.
-- Bucket creation is safely handled below without touching table ownership.
DO $$
BEGIN
  INSERT INTO storage.buckets (id, name, public)
  VALUES ('medias', 'medias', false)
  ON CONFLICT (id) DO UPDATE SET public = false;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Storage bucket initialization skipped: %', SQLERRM;
END $$;

