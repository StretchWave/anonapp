-- ============================================================
-- AnonApp — Migration 00003: Messages & Realtime
-- ============================================================

-- ── Messages table ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.messages (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID        NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  sender_id       UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  content         TEXT,
  message_type    TEXT        NOT NULL DEFAULT 'text' CHECK (message_type IN ('text', 'system', 'deleted')),
  client_id       UUID        UNIQUE, -- For client-side idempotency and optimistic UI matching
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  delivered_at    TIMESTAMPTZ,
  read_at         TIMESTAMPTZ,
  deleted_at      TIMESTAMPTZ,
  expires_at      TIMESTAMPTZ
);

-- ── Indexes ────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_messages_conversation_created
  ON public.messages (conversation_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_messages_sender
  ON public.messages (sender_id);

CREATE INDEX IF NOT EXISTS idx_messages_expires
  ON public.messages (expires_at)
  WHERE expires_at IS NOT NULL;

-- ── Row Level Security ─────────────────────────────────────────
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

-- Members can select messages from their conversations
CREATE POLICY "messages_select_member"
  ON public.messages
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.conversation_members
      WHERE conversation_members.conversation_id = messages.conversation_id
        AND conversation_members.user_id = auth.uid()
    )
  );

-- Members can insert messages in their conversations as themselves
CREATE POLICY "messages_insert_member"
  ON public.messages
  FOR INSERT
  WITH CHECK (
    sender_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.conversation_members
      WHERE conversation_members.conversation_id = messages.conversation_id
        AND conversation_members.user_id = auth.uid()
    )
  );

-- Sender can update their own messages (for soft delete or edits)
CREATE POLICY "messages_update_sender"
  ON public.messages
  FOR UPDATE
  USING (sender_id = auth.uid());

-- Recipients can update delivery/read timestamps
CREATE POLICY "messages_update_recipient"
  ON public.messages
  FOR UPDATE
  USING (
    sender_id <> auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.conversation_members
      WHERE conversation_members.conversation_id = messages.conversation_id
        AND conversation_members.user_id = auth.uid()
    )
  );

-- ── Trigger: update conversation updated_at on new message ─────
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

-- ── Add foreign key on conversation_members for last_read_message_id ──
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'fk_conversation_members_last_read'
  ) THEN
    ALTER TABLE public.conversation_members
      ADD CONSTRAINT fk_conversation_members_last_read
      FOREIGN KEY (last_read_message_id) REFERENCES public.messages(id) ON DELETE SET NULL;
  END IF;
END $$;

-- ── Enable Supabase Realtime publication ───────────────────────
ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;
ALTER PUBLICATION supabase_realtime ADD TABLE public.conversations;
ALTER PUBLICATION supabase_realtime ADD TABLE public.conversation_members;
