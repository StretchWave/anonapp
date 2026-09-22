-- ============================================================
-- AnonApp — Migration 00001: Profiles Table
-- ============================================================
-- This migration creates the profiles table linked to Supabase
-- Auth users. Every new account gets a row here during signup.
--
-- Run in the Supabase SQL Editor or via Supabase CLI migrations.
-- ============================================================

-- Profiles table
CREATE TABLE IF NOT EXISTS public.profiles (
  id          UUID        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  username    TEXT        UNIQUE NOT NULL
                          CHECK (char_length(username) BETWEEN 3 AND 30),
  display_name TEXT       CHECK (display_name IS NULL OR char_length(display_name) <= 50),
  contact_code TEXT       UNIQUE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_seen   TIMESTAMPTZ
);

-- Index for username lookups and search
CREATE INDEX IF NOT EXISTS idx_profiles_username
  ON public.profiles (lower(username));

-- Index for contact code lookups
CREATE INDEX IF NOT EXISTS idx_profiles_contact_code
  ON public.profiles (contact_code)
  WHERE contact_code IS NOT NULL;

-- ── Row Level Security ─────────────────────────────────────────
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Any authenticated user can read profiles (needed for user search).
CREATE POLICY "profiles_select_authenticated"
  ON public.profiles
  FOR SELECT
  USING (auth.role() = 'authenticated');

-- Users can only insert their own profile row (during registration).
CREATE POLICY "profiles_insert_own"
  ON public.profiles
  FOR INSERT
  WITH CHECK (auth.uid() = id);

-- Users can only update their own profile.
CREATE POLICY "profiles_update_own"
  ON public.profiles
  FOR UPDATE
  USING (auth.uid() = id);

-- Users cannot delete profiles (cascade from auth.users handles it).
-- No DELETE policy = denied by default with RLS enabled.

-- ── Helper function: generate contact code ─────────────────────
-- Generates a random 8-character alphanumeric code.
CREATE OR REPLACE FUNCTION public.generate_contact_code()
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
  chars TEXT := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; -- No I/O/0/1 to avoid confusion
  result TEXT := '';
  i INT;
BEGIN
  FOR i IN 1..8 LOOP
    result := result || substr(chars, floor(random() * length(chars) + 1)::int, 1);
  END LOOP;
  RETURN result;
END;
$$;

-- ── Trigger: auto-generate contact code on insert ──────────────
CREATE OR REPLACE FUNCTION public.profiles_before_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  -- Auto-generate contact_code if not provided
  IF NEW.contact_code IS NULL THEN
    NEW.contact_code := public.generate_contact_code();
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_profiles_before_insert
  BEFORE INSERT ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.profiles_before_insert();
