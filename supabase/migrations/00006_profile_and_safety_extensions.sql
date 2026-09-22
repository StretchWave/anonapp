-- ============================================================
-- Migration 00006: Profile & Safety Extensions
-- Adds bio, avatar preset, interests, persona, and online visibility
-- Adds blocked_users and user_reports tables with RLS
-- ============================================================

-- 1. Extend profiles table
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS bio TEXT CHECK (bio IS NULL OR char_length(bio) <= 200),
  ADD COLUMN IF NOT EXISTS avatar TEXT,
  ADD COLUMN IF NOT EXISTS interests TEXT[] DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS persona TEXT,
  ADD COLUMN IF NOT EXISTS online_status_visible BOOLEAN DEFAULT true;

-- 2. Blocked Users table
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

-- 3. Anonymous User Reports table
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
