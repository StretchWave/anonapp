-- ============================================================
-- AnonApp — Migration 00009: Document Sharing Support
-- ============================================================

-- Update message_type check constraint to include 'document'
DO $$
BEGIN
  ALTER TABLE public.messages
    DROP CONSTRAINT IF EXISTS messages_message_type_check;

  ALTER TABLE public.messages
    ADD CONSTRAINT messages_message_type_check
    CHECK (message_type IN ('text', 'image', 'view_once_image', 'audio', 'document', 'system', 'deleted'));
END $$;
