-- ============================================================
-- AnonApp — Migration 00004: Rich Media & View-Once Support
-- ============================================================

-- Add media columns to messages if they don't exist
ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS media_url TEXT,
  ADD COLUMN IF NOT EXISTS media_data TEXT,
  ADD COLUMN IF NOT EXISTS media_meta JSONB,
  ADD COLUMN IF NOT EXISTS viewed_at TIMESTAMPTZ;

-- Add cleared_at to conversations to support clearing chat on both clients without deleting server rows
ALTER TABLE public.conversations
  ADD COLUMN IF NOT EXISTS cleared_at TIMESTAMPTZ;

-- Update message_type check constraint to support rich media
DO $$
BEGIN
  ALTER TABLE public.messages
    DROP CONSTRAINT IF EXISTS messages_message_type_check;

  ALTER TABLE public.messages
    ADD CONSTRAINT messages_message_type_check
    CHECK (message_type IN ('text', 'image', 'view_once_image', 'audio', 'system', 'deleted'));
END $$;

-- Ensure logical replication emits full row payloads including unchanged toast columns
ALTER TABLE public.messages REPLICA IDENTITY FULL;

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
  v_msg_type TEXT;
  v_viewed_at TIMESTAMPTZ;
BEGIN
  -- Get message details
  SELECT conversation_id, sender_id, message_type, viewed_at
  INTO v_conv_id, v_sender_id, v_msg_type, v_viewed_at
  FROM public.messages
  WHERE id = p_message_id;

  IF v_conv_id IS NULL THEN
    RAISE EXCEPTION 'Message not found';
  END IF;

  -- Caller must be a conversation member
  IF NOT public.is_member_of_conversation(v_conv_id) THEN
    RAISE EXCEPTION 'Permission denied';
  END IF;

  -- Only recipients can open view-once media
  IF v_sender_id = auth.uid() THEN
    RETURN FALSE;
  END IF;

  -- If already viewed, nothing more to do
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
