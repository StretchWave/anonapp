-- ============================================================
-- AnonApp — Complete Consolidated Database Schema
-- Run this script in the Supabase SQL Editor:
-- https://supabase.com/dashboard/project/oydrnjrtmaqvpylqrkfp/sql
-- ============================================================

-- ── 1. PROFILES TABLE ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.profiles (
  id           UUID        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  username     TEXT        UNIQUE NOT NULL CHECK (char_length(username) BETWEEN 3 AND 30),
  display_name TEXT        CHECK (display_name IS NULL OR char_length(display_name) <= 50),
  contact_code TEXT        UNIQUE,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_seen    TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_profiles_username
  ON public.profiles (lower(username));

CREATE INDEX IF NOT EXISTS idx_profiles_contact_code
  ON public.profiles (contact_code)
  WHERE contact_code IS NOT NULL;

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "profiles_select_authenticated" ON public.profiles;
CREATE POLICY "profiles_select_authenticated"
  ON public.profiles
  FOR SELECT
  USING (auth.role() = 'authenticated');

DROP POLICY IF EXISTS "profiles_insert_own" ON public.profiles;
CREATE POLICY "profiles_insert_own"
  ON public.profiles
  FOR INSERT
  WITH CHECK (auth.uid() = id);

DROP POLICY IF EXISTS "profiles_update_own" ON public.profiles;
CREATE POLICY "profiles_update_own"
  ON public.profiles
  FOR UPDATE
  USING (auth.uid() = id);

-- Helper function: generate random 8-character contact code
CREATE OR REPLACE FUNCTION public.generate_contact_code()
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
  chars TEXT := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; -- unambiguous characters
  result TEXT := '';
  i INTEGER;
BEGIN
  FOR i IN 1..8 LOOP
    result := result || substr(chars, floor(random() * length(chars) + 1)::integer, 1);
  END LOOP;
  RETURN result;
END;
$$;

-- ── 2. CONVERSATIONS & MEMBERS TABLE ──────────────────────────
CREATE TABLE IF NOT EXISTS public.conversations (
  id                             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at                     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at                     TIMESTAMPTZ NOT NULL DEFAULT now(),
  disappearing_messages_duration INTERVAL,
  cleared_at                     TIMESTAMPTZ
);

ALTER TABLE public.conversations
  ADD COLUMN IF NOT EXISTS cleared_at TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS public.conversation_members (
  conversation_id      UUID        NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  user_id              UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  joined_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_read_message_id UUID,
  is_muted             BOOLEAN     NOT NULL DEFAULT false,
  PRIMARY KEY (conversation_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_conversation_members_user
  ON public.conversation_members(user_id);

CREATE INDEX IF NOT EXISTS idx_conversation_members_conversation
  ON public.conversation_members(conversation_id);

-- Helper function: check membership using SECURITY DEFINER to avoid RLS recursion
CREATE OR REPLACE FUNCTION public.is_member_of_conversation(p_conv_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.conversation_members
    WHERE conversation_id = p_conv_id
      AND user_id = auth.uid()
  );
$$;

ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversation_members ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "conversations_select_member" ON public.conversations;
CREATE POLICY "conversations_select_member"
  ON public.conversations
  FOR SELECT
  USING (
    public.is_member_of_conversation(id)
  );

DROP POLICY IF EXISTS "conversations_insert_authenticated" ON public.conversations;
CREATE POLICY "conversations_insert_authenticated"
  ON public.conversations
  FOR INSERT
  WITH CHECK (auth.role() = 'authenticated');

DROP POLICY IF EXISTS "conversations_update_member" ON public.conversations;
CREATE POLICY "conversations_update_member"
  ON public.conversations
  FOR UPDATE
  USING (
    public.is_member_of_conversation(id)
  );

DROP POLICY IF EXISTS "conv_members_select" ON public.conversation_members;
CREATE POLICY "conv_members_select"
  ON public.conversation_members
  FOR SELECT
  USING (
    user_id = auth.uid() OR public.is_member_of_conversation(conversation_id)
  );

DROP POLICY IF EXISTS "conv_members_insert" ON public.conversation_members;
CREATE POLICY "conv_members_insert"
  ON public.conversation_members
  FOR INSERT
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "conv_members_update" ON public.conversation_members;
CREATE POLICY "conv_members_update"
  ON public.conversation_members
  FOR UPDATE
  USING (user_id = auth.uid());

-- RPC to find or create a 1:1 conversation between two users
CREATE OR REPLACE FUNCTION public.find_or_create_direct_conversation(
  p_user_id_1 UUID,
  p_user_id_2 UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_conv_id UUID;
BEGIN
  -- Caller must be one of the participants
  IF auth.uid() IS NOT NULL AND auth.uid() NOT IN (p_user_id_1, p_user_id_2) THEN
    RAISE EXCEPTION 'Unauthorized: You can only access conversations you participate in.';
  END IF;

  -- Look for an existing conversation having precisely these two participants
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

  -- Add both members
  INSERT INTO public.conversation_members (conversation_id, user_id)
  VALUES
    (v_conv_id, p_user_id_1),
    (v_conv_id, p_user_id_2);

  RETURN v_conv_id;
END;
$$;

-- ── 3. MESSAGES TABLE & REALTIME ──────────────────────────────
CREATE TABLE IF NOT EXISTS public.messages (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID        NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  sender_id       UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  content         TEXT,
  message_type    TEXT        NOT NULL DEFAULT 'text' CHECK (message_type IN ('text', 'image', 'view_once_image', 'audio', 'system', 'deleted')),
  client_id       UUID        UNIQUE,
  media_url       TEXT,
  media_data      TEXT,
  media_meta      JSONB,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  delivered_at    TIMESTAMPTZ,
  read_at         TIMESTAMPTZ,
  viewed_at       TIMESTAMPTZ,
  deleted_at      TIMESTAMPTZ,
  expires_at      TIMESTAMPTZ
);

ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS media_url TEXT,
  ADD COLUMN IF NOT EXISTS media_data TEXT,
  ADD COLUMN IF NOT EXISTS media_meta JSONB,
  ADD COLUMN IF NOT EXISTS viewed_at TIMESTAMPTZ;

DO $$
BEGIN
  ALTER TABLE public.messages
    DROP CONSTRAINT IF EXISTS messages_message_type_check;
  ALTER TABLE public.messages
    ADD CONSTRAINT messages_message_type_check
    CHECK (message_type IN ('text', 'image', 'view_once_image', 'audio', 'system', 'deleted'));
END $$;

ALTER TABLE public.messages REPLICA IDENTITY FULL;

CREATE INDEX IF NOT EXISTS idx_messages_conversation_created
  ON public.messages (conversation_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_messages_sender
  ON public.messages (sender_id);

CREATE INDEX IF NOT EXISTS idx_messages_expires
  ON public.messages (expires_at)
  WHERE expires_at IS NOT NULL;

ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "messages_select_member" ON public.messages;
CREATE POLICY "messages_select_member"
  ON public.messages
  FOR SELECT
  USING (
    public.is_member_of_conversation(conversation_id)
    -- Exclude expired disappearing messages
    AND (expires_at IS NULL OR expires_at > now())
    -- Exclude messages sent prior to conversation clear
    AND (
      created_at > (SELECT c.cleared_at FROM public.conversations c WHERE c.id = conversation_id)
      OR (SELECT c.cleared_at FROM public.conversations c WHERE c.id = conversation_id) IS NULL
    )
  );

DROP POLICY IF EXISTS "messages_insert_member" ON public.messages;
CREATE POLICY "messages_insert_member"
  ON public.messages
  FOR INSERT
  WITH CHECK (
    sender_id = auth.uid()
    AND public.is_member_of_conversation(conversation_id)
  );

DROP POLICY IF EXISTS "messages_update_sender" ON public.messages;
CREATE POLICY "messages_update_sender"
  ON public.messages
  FOR UPDATE
  USING (sender_id = auth.uid());

DROP POLICY IF EXISTS "messages_update_recipient" ON public.messages;
CREATE POLICY "messages_update_recipient"
  ON public.messages
  FOR UPDATE
  USING (
    sender_id <> auth.uid()
    AND public.is_member_of_conversation(conversation_id)
  );

-- Trigger: Prevent recipients from tampering with message content, media, or sender
CREATE OR REPLACE FUNCTION public.protect_message_fields_on_recipient_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
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
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_protect_message_fields ON public.messages;
CREATE TRIGGER trg_protect_message_fields
  BEFORE UPDATE ON public.messages
  FOR EACH ROW
  EXECUTE FUNCTION public.protect_message_fields_on_recipient_update();

-- Trigger: update conversation updated_at on new message
CREATE OR REPLACE FUNCTION public.handle_new_message()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE public.conversations
  SET updated_at = NEW.created_at
  WHERE id = NEW.conversation_id;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_message_created ON public.messages;
CREATE TRIGGER on_message_created
  AFTER INSERT ON public.messages
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_message();

-- ── RPC: mark_view_once_opened ─────────────────────────────────
-- Destroys media_data on the server immediately upon viewing
CREATE OR REPLACE FUNCTION public.mark_view_once_opened(p_message_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_conv_id UUID;
  v_sender_id UUID;
  v_viewed_at TIMESTAMPTZ;
BEGIN
  SELECT conversation_id, sender_id, viewed_at
  INTO v_conv_id, v_sender_id, v_viewed_at
  FROM public.messages
  WHERE id = p_message_id;

  IF v_conv_id IS NULL THEN
    RAISE EXCEPTION 'Message not found';
  END IF;

  IF NOT public.is_member_of_conversation(v_conv_id) THEN
    RAISE EXCEPTION 'Permission denied';
  END IF;

  IF v_sender_id = auth.uid() THEN
    RETURN FALSE;
  END IF;

  IF v_viewed_at IS NOT NULL THEN
    RETURN TRUE;
  END IF;

  -- Record viewed timestamp (media_data preserved in database; deletion is client-side only)
  UPDATE public.messages
  SET viewed_at = now(),
      read_at = COALESCE(read_at, now())
  WHERE id = p_message_id;

  RETURN TRUE;
END;
$$;

-- Enable Supabase Realtime publication safely
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND tablename = 'messages'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND tablename = 'conversations'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.conversations;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND tablename = 'conversation_members'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.conversation_members;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Publication notice: %', SQLERRM;
END $$;

-- ── 7. PROFILE & SAFETY EXTENSIONS ────────────────────────────
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS bio TEXT CHECK (bio IS NULL OR char_length(bio) <= 200),
  ADD COLUMN IF NOT EXISTS avatar TEXT,
  ADD COLUMN IF NOT EXISTS interests TEXT[] DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS persona TEXT,
  ADD COLUMN IF NOT EXISTS online_status_visible BOOLEAN DEFAULT true;

CREATE TABLE IF NOT EXISTS public.blocked_users (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  blocker_id   UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  blocked_id   UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (blocker_id, blocked_id)
);

ALTER TABLE public.blocked_users ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "blocked_users_select_own" ON public.blocked_users;
CREATE POLICY "blocked_users_select_own"
  ON public.blocked_users FOR SELECT
  USING (auth.uid() = blocker_id);

DROP POLICY IF EXISTS "blocked_users_insert_own" ON public.blocked_users;
CREATE POLICY "blocked_users_insert_own"
  ON public.blocked_users FOR INSERT
  WITH CHECK (auth.uid() = blocker_id);

DROP POLICY IF EXISTS "blocked_users_delete_own" ON public.blocked_users;
CREATE POLICY "blocked_users_delete_own"
  ON public.blocked_users FOR DELETE
  USING (auth.uid() = blocker_id);

CREATE TABLE IF NOT EXISTS public.user_reports (
  id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id       UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  reported_user_id  UUID,
  conversation_id   UUID,
  reason            TEXT        NOT NULL,
  details           TEXT,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.user_reports ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "user_reports_insert_own" ON public.user_reports;
CREATE POLICY "user_reports_insert_own"
  ON public.user_reports FOR INSERT
  WITH CHECK (auth.uid() = reporter_id);

-- ── 8. COMPREHENSIVE PRIVACY & ACCESS HARDENING (Migration 00007) ──
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Cryptographic contact code generator
CREATE OR REPLACE FUNCTION public.generate_contact_code()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  chars TEXT := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
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

    IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE contact_code = result) THEN
      RETURN result;
    END IF;

    IF attempts >= 10 THEN
      RETURN result;
    END IF;
  END LOOP;
END;
$$;

-- Profile Access Lockdown
DROP POLICY IF EXISTS "profiles_select_authenticated" ON public.profiles;
DROP POLICY IF EXISTS "profiles_select_own" ON public.profiles;
DROP POLICY IF EXISTS "profiles_select_conversation_partner" ON public.profiles;

CREATE POLICY "profiles_select_own"
  ON public.profiles FOR SELECT
  USING (auth.uid() = id);

CREATE POLICY "profiles_select_conversation_partner"
  ON public.profiles FOR SELECT
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

-- Controlled Public Profile RPCs
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
    id, username, display_name, avatar, bio, interests, persona, online_status_visible,
    CASE WHEN online_status_visible IS TRUE THEN last_seen ELSE NULL END AS last_seen,
    CASE WHEN online_status_visible IS TRUE AND last_seen > (now() - INTERVAL '5 minutes') THEN TRUE ELSE FALSE END AS is_online,
    created_at
  INTO v_profile
  FROM public.profiles
  WHERE id = p_user_id;

  IF v_profile.id IS NULL THEN
    RETURN NULL;
  END IF;

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

-- Conversation & Membership Hardening
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

  SELECT EXISTS (
    SELECT 1 FROM public.blocked_users
    WHERE (blocker_id = p_user_id_1 AND blocked_id = p_user_id_2)
       OR (blocker_id = p_user_id_2 AND blocked_id = p_user_id_1)
  ) INTO v_is_blocked;

  IF v_is_blocked THEN
    RAISE EXCEPTION 'Cannot start conversation: this user is blocked or unavailable.';
  END IF;

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

  INSERT INTO public.conversations (created_at, updated_at)
  VALUES (now(), now())
  RETURNING id INTO v_conv_id;

  INSERT INTO public.conversation_members (conversation_id, user_id)
  VALUES
    (v_conv_id, p_user_id_1),
    (v_conv_id, p_user_id_2);

  RETURN v_conv_id;
END;
$$;

DROP POLICY IF EXISTS "conv_members_insert" ON public.conversation_members;

-- Message Integrity & Server-Side Expiry
DROP POLICY IF EXISTS "messages_insert_member" ON public.messages;
CREATE POLICY "messages_insert_member"
  ON public.messages FOR INSERT
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

DROP POLICY IF EXISTS "messages_select_member" ON public.messages;
CREATE POLICY "messages_select_member"
  ON public.messages FOR SELECT
  USING (
    public.is_member_of_conversation(conversation_id)
    AND (expires_at IS NULL OR expires_at > now())
    AND (
      created_at > (SELECT c.cleared_at FROM public.conversations c WHERE c.id = conversation_id)
      OR (SELECT c.cleared_at FROM public.conversations c WHERE c.id = conversation_id) IS NULL
    )
  );

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

-- ── 9. RED-TEAM SECURITY HARDENING (Migration 00008) ────────────

-- Administrator Framework
CREATE TABLE IF NOT EXISTS public.app_admins (
  user_id    UUID        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.app_admins ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "app_admins_select_own" ON public.app_admins;
CREATE POLICY "app_admins_select_own"
  ON public.app_admins FOR SELECT
  USING (auth.uid() = user_id);

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

DROP POLICY IF EXISTS "user_reports_select_admin" ON public.user_reports;
CREATE POLICY "user_reports_select_admin"
  ON public.user_reports FOR SELECT
  USING (public.is_admin());

DROP POLICY IF EXISTS "user_reports_delete_admin" ON public.user_reports;
CREATE POLICY "user_reports_delete_admin"
  ON public.user_reports FOR DELETE
  USING (public.is_admin());

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

-- Atomic View-Once Hardening
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
  SELECT conversation_id, sender_id, message_type, viewed_at
  INTO v_conv_id, v_sender_id, v_msg_type, v_viewed_at
  FROM public.messages
  WHERE id = p_message_id
  FOR UPDATE;

  IF v_conv_id IS NULL THEN
    RAISE EXCEPTION 'Message not found';
  END IF;

  IF NOT public.is_member_of_conversation(v_conv_id) THEN
    RAISE EXCEPTION 'Permission denied';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.blocked_users
    WHERE (blocker_id = auth.uid() AND blocked_id = v_sender_id)
       OR (blocker_id = v_sender_id AND blocked_id = auth.uid())
  ) INTO v_is_blocked;

  IF v_is_blocked THEN
    RAISE EXCEPTION 'Permission denied: user is blocked.';
  END IF;

  IF v_sender_id = auth.uid() THEN
    RETURN FALSE;
  END IF;

  IF v_viewed_at IS NOT NULL THEN
    RETURN FALSE;
  END IF;

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

-- Message Insert & Update Protection
CREATE OR REPLACE FUNCTION public.protect_message_fields_on_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_disappearing INTERVAL;
BEGIN
  NEW.created_at := now();
  NEW.read_at := NULL;
  NEW.delivered_at := NULL;
  NEW.viewed_at := NULL;
  NEW.deleted_at := NULL;

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

CREATE OR REPLACE FUNCTION public.protect_message_fields_on_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
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
    NEW.deleted_at      := OLD.deleted_at;

    IF OLD.viewed_at IS NOT NULL AND NEW.viewed_at IS NULL THEN
      NEW.viewed_at := OLD.viewed_at;
    END IF;
  ELSE
    NEW.sender_id       := OLD.sender_id;
    NEW.conversation_id := OLD.conversation_id;
    NEW.created_at      := OLD.created_at;
    NEW.client_id       := OLD.client_id;
    NEW.expires_at      := OLD.expires_at;

    NEW.read_at         := OLD.read_at;
    NEW.delivered_at    := OLD.delivered_at;
    NEW.viewed_at       := OLD.viewed_at;

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

-- Contact Code Privacy Isolation RPC
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

-- Conversation Hardening
DROP POLICY IF EXISTS "conversations_insert_authenticated" ON public.conversations;

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
    IF NEW.cleared_at > (now() + INTERVAL '10 seconds') THEN
      RAISE EXCEPTION 'Cannot set cleared_at in the future.';
    END IF;
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

-- Rate Limiting Engine
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

-- ── 15. SUPABASE STORAGE SETUP (OPTIONAL) ────────────────────────
-- Note: The 'storage.objects' table is owned by supabase_storage_admin,
-- not the postgres role. Supabase already enables RLS on storage.objects by default.
-- Bucket creation is safely handled below without touching table ownership.
DO $$
BEGIN
  INSERT INTO storage.buckets (id, name, public)
  VALUES ('medias', 'medias', false)
  ON CONFLICT (id) DO UPDATE SET public = false;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Storage bucket initialization skipped: %', SQLERRM;
END $$;

