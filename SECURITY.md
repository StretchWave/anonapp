# AnonApp — Security, Privacy & Anonymity Architecture

This document describes the security model, privacy safeguards, and architectural constraints implemented in AnonApp.

---

## 1. Pseudonymous Privacy Model vs. Cryptographic Anonymity

AnonApp operates under a **pseudonymous privacy model**, not absolute cryptographic anonymity.

- **What other users see**: Only your chosen `@username`, optional display name, avatar preset, bio, and selected interests.
- **What is kept private from other users**: Real-world identity, email address, password hashes, internal auth UUIDs, contact codes of third parties, blocked lists, and moderation reports.
- **What the backend knows**: The Supabase service infrastructure manages authenticated sessions and stores message payloads, metadata, and timestamps necessary for real-time delivery and service operation.

> [!NOTE]
> AnonApp guarantees that ordinary users cannot discover your real-world identity or enumerate other users' contact credentials. It does **not** claim to be an untraceable, metadata-free Tor network.

---

## 2. Least-Privilege Profile Access & Database RLS

Prior to Migration `00007`, authenticated users could execute `SELECT * FROM profiles`. Under the hardened architecture:

1. **Direct Profile SELECT**:
   - `profiles_select_own`: Authenticated users can only select their own full row (`auth.uid() = id`).
   - `profiles_select_conversation_partner`: Users can only read profiles of users with whom they share an active conversation, provided neither user has blocked the other.
2. **Controlled Discovery RPCs**:
   - `get_public_profile(p_user_id)`: Returns only public attributes (`username`, `display_name`, `avatar`, `bio`, `interests`, `persona`, and conditional `last_seen`). Returns `NULL` if blocked.
   - `find_profile_by_contact_code(p_code)`: Validates 8-character format, enforces blocking, and returns minimal public info without revealing the target's contact code or private settings.
   - `search_public_profiles(p_query, p_limit)`: Rate-limited, paginated discovery query that excludes blocked users and the caller.

---

## 3. Cryptographic Contact Code Generation

- **Source**: Contact codes are generated using PostgreSQL `pgcrypto` cryptographic randomness (`gen_random_bytes(8)`).
- **Alphabet**: 32 unambiguous characters (`ABCDEFGHJKLMNPQRSTUVWXYZ23456789`), excluding visually ambiguous characters (`0`, `O`, `1`, `I`).
- **Collision Resistance**: 8 characters across 32 symbols yields $32^8 \approx 1.1 \text{ trillion}$ unique combinations. Generation executes in an automated collision-retry loop guaranteed by a `UNIQUE` database constraint.

---

## 4. Server-Side Blocking Enforcement

Blocking is enforced at the database layer (PostgreSQL RLS and RPCs), not merely filtered client-side:

| Area | Enforcement Mechanism |
|---|---|
| **Direct Messaging** | `messages_insert_member` RLS policy blocks message creation if either party has blocked the other. |
| **Chat Creation** | `find_or_create_direct_conversation` RPC rejects conversation initiation between blocked pairs with an exception. |
| **Contact Code Lookup** | `find_profile_by_contact_code` returns generic `NULL` if blocked. |
| **Search & Discovery** | `search_public_profiles` filters out blocked users from candidate pools. |
| **Block List Privacy** | `blocked_users` RLS permits users to read only their own blocks (`auth.uid() = blocker_id`). Users can never see who has blocked them. |

---

## 5. Message Integrity, Tampering Prevention & Expiry

1. **Immutability Triggers**:
   - Recipients updating a message (e.g. Setting `read_at` or `viewed_at`) are prohibited from altering `content`, `media_data`, `sender_id`, `created_at`, `client_id`, or `expires_at`.
   - Senders can only soft-delete (`deleted_at = now()`, `message_type = 'deleted'`) and cannot tamper with historical metadata.
2. **Disappearing Messages Expiry**:
   - `messages_select_member` enforces `(expires_at IS NULL OR expires_at > now())` on every `SELECT`.
   - Expired messages are hidden server-side from all clients.
   - `clean_expired_messages()` function physically deletes expired messages and historical soft-deleted records.
3. **Clear Chat**:
   - `clear_conversation_chat(p_conversation_id)` verifies membership and sets `cleared_at = now()`.
   - RLS hides all prior messages from member queries.

---

## 6. Safety & User Reports

- **Impersonation Prevention**: `user_reports` enforces `reporter_id = auth.uid()` via RLS.
- **Constraints**: Database constraints prevent self-reporting (`reporter_id <> reported_user_id`) and enforce text length bounds on reason and details.
- **Read Isolation**: Normal clients have zero `SELECT`, `UPDATE`, or `DELETE` permissions on `user_reports`. Reports are strictly write-only for clients, reserved for administrative review.

---

## 7. Ephemeral Web Sessions ("Forget Login on Close")

- **Web Storage Separation**:
  - When **Remember Login** is **OFF**: Auth tokens are stored strictly in `window.sessionStorage`. Closing the tab or browser causes the browser engine to destroy `sessionStorage`, automatically logging out the user.
  - When **Remember Login** is **ON**: Auth tokens are stored in `window.localStorage`.
- **Live Migration**: Toggling the setting in Security settings migrates the active session between storage tiers in real time.

---

## 8. Current Encryption Status & True E2EE Roadmap

### Current Model
Text messages are encrypted locally using AES-256-GCM before transmission. Conversation participants derive symmetric keys locally.

### Roadmap to True End-to-End Encryption (Signal / Double Ratchet Protocol)
To achieve true, zero-knowledge cryptographic E2EE that withstands server compromise, the following enhancements are planned:
1. **Asymmetric Identity Keys & Prekeys**: Each client publishes signed prekeys and one-time prekeys to the database.
2. **Double Ratchet Protocol**: Session keys ratchet forward per-message, guaranteeing Perfect Forward Secrecy (PFS) and Break-in Recovery (Post-Compromise Security).
3. **Out-of-Band Safety Numbers**: QR code / numeric fingerprint comparison between conversation participants.
