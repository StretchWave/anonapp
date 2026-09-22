-- ============================================================
-- AnonApp — Migration 00002: Conversations & Memberships
-- ============================================================

-- ── Conversations table ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.conversations (
  id                            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at                    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at                    TIMESTAMPTZ NOT NULL DEFAULT now(),
  disappearing_messages_duration INTERVAL
);

-- ── Conversation members table ─────────────────────────────────
CREATE TABLE IF NOT EXISTS public.conversation_members (
  conversation_id  UUID        NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  user_id          UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  joined_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_read_message_id UUID,
  is_muted         BOOLEAN     NOT NULL DEFAULT false,
  PRIMARY KEY (conversation_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_conversation_members_user
  ON public.conversation_members(user_id);

CREATE INDEX IF NOT EXISTS idx_conversation_members_conversation
  ON public.conversation_members(conversation_id);

-- ── RLS: Conversations ─────────────────────────────────────────
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;

-- Users can only see conversations they are members of.
CREATE POLICY "conversations_select_member"
  ON public.conversations
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.conversation_members
      WHERE conversation_members.conversation_id = conversations.id
        AND conversation_members.user_id = auth.uid()
    )
  );

-- Any authenticated user can create a conversation.
CREATE POLICY "conversations_insert_authenticated"
  ON public.conversations
  FOR INSERT
  WITH CHECK (auth.role() = 'authenticated');

-- Members can update conversation settings (e.g., disappearing messages).
CREATE POLICY "conversations_update_member"
  ON public.conversations
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.conversation_members
      WHERE conversation_members.conversation_id = conversations.id
        AND conversation_members.user_id = auth.uid()
    )
  );

-- ── RLS: Conversation Members ──────────────────────────────────
ALTER TABLE public.conversation_members ENABLE ROW LEVEL SECURITY;

-- Members can see other members of their conversations.
CREATE POLICY "conv_members_select"
  ON public.conversation_members
  FOR SELECT
  USING (
    user_id = auth.uid() OR
    EXISTS (
      SELECT 1 FROM public.conversation_members cm
      WHERE cm.conversation_id = conversation_members.conversation_id
        AND cm.user_id = auth.uid()
    )
  );

-- Authenticated users can add members (creating a chat invitation).
CREATE POLICY "conv_members_insert"
  ON public.conversation_members
  FOR INSERT
  WITH CHECK (auth.role() = 'authenticated');

-- Members can update their own membership (mute, read state).
CREATE POLICY "conv_members_update_own"
  ON public.conversation_members
  FOR UPDATE
  USING (user_id = auth.uid());

-- ── Auto-update conversations.updated_at trigger ───────────────
CREATE OR REPLACE FUNCTION public.update_conversation_timestamp()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE public.conversations
  SET updated_at = now()
  WHERE id = NEW.conversation_id;
  RETURN NEW;
END;
$$;

-- This trigger fires when a new member is added, keeping updated_at fresh.
CREATE TRIGGER trg_conv_members_update_timestamp
  AFTER INSERT ON public.conversation_members
  FOR EACH ROW
  EXECUTE FUNCTION public.update_conversation_timestamp();

-- ── Helper: find or create 1:1 conversation ────────────────────
-- Returns the existing conversation ID between two users, or creates one.
CREATE OR REPLACE FUNCTION public.find_or_create_direct_conversation(
  p_user_id_1 UUID,
  p_user_id_2 UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_conversation_id UUID;
BEGIN
  -- Check if a 1:1 conversation already exists between these two users.
  SELECT cm1.conversation_id INTO v_conversation_id
  FROM public.conversation_members cm1
  INNER JOIN public.conversation_members cm2
    ON cm1.conversation_id = cm2.conversation_id
  WHERE cm1.user_id = p_user_id_1
    AND cm2.user_id = p_user_id_2
  -- Only match conversations with exactly 2 members (1:1).
  AND (
    SELECT count(*) FROM public.conversation_members cm3
    WHERE cm3.conversation_id = cm1.conversation_id
  ) = 2
  LIMIT 1;

  IF v_conversation_id IS NOT NULL THEN
    RETURN v_conversation_id;
  END IF;

  -- Create a new conversation.
  INSERT INTO public.conversations DEFAULT VALUES
  RETURNING id INTO v_conversation_id;

  -- Add both members.
  INSERT INTO public.conversation_members (conversation_id, user_id)
  VALUES
    (v_conversation_id, p_user_id_1),
    (v_conversation_id, p_user_id_2);

  RETURN v_conversation_id;
END;
$$;
