-- ============================================================
-- Migration 00005: Security Hardening & Access Control Lockdown
-- ============================================================

-- 1. Restrict find_or_create_direct_conversation caller authorization
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

-- 2. Lock down conversation_members INSERT so arbitrary injection is blocked
DROP POLICY IF EXISTS "conv_members_insert" ON public.conversation_members;
CREATE POLICY "conv_members_insert"
  ON public.conversation_members
  FOR INSERT
  WITH CHECK (user_id = auth.uid());

-- 3. Trigger: Prevent recipients from tampering with message content, media, or sender
CREATE OR REPLACE FUNCTION public.protect_message_fields_on_recipient_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- When the updater is not the sender, protect immutable fields
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

-- 4. Enforce Disappearing Messages & Server-side Clear Chat in RLS
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
