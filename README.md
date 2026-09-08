# AnonApp 🔒

> **Anonymous, Pseudonymous, End-to-End Encrypted Realtime Chat.**  
> Designed for privacy-first, ephemeral, and tamper-resistant communication across Android, iOS, Desktop, and Web.

---

## 🌟 Key Features

- **Selective End-to-End Encryption (AES-256-GCM)**:
  - Text messages are encrypted client-side using authenticated AES-256-GCM before transmission.
  - Per-conversation 256-bit symmetric keys are derived on-the-fly with HKDF-SHA256.
  - Payloads are formatted as `ENC:v1:<nonce>:<ciphertext>:<mac>` with backwards compatibility for legacy logs.
  - Images, view-once photos, and media are safely stored directly without ciphertext corruption.

- **Native Mobile Notifications (Android & iOS)**:
  - High-priority local notification channel with Android 13+ runtime permissions.
  - **Discreet Mode**: Obscures message sender and content on lock screens to prevent shoulder-surfing.
  - **Active Chat Suppression**: Intelligently suppresses notifications if the user is already actively reading the conversation.
  - **Web Separation**: Zero background notification bloat on Flutter Web.

- **Non-Intrusive Click-Through UI**:
  - `AppToast` provides top-docked, translucent frosted-glass alerts (`BackdropFilter`).
  - Wrapped in `IgnorePointer` so alerts never interfere with typing, tapping, or keyboard focus.

- **Ephemeral Messaging & Clear Chat**:
  - Configurable disappearing message timers (30 seconds, 5 minutes, 1 hour, 24 hours, 7 days).
  - Enforced both at the client layer and via PostgreSQL Row-Level Security (`expires_at > now()`).
  - Independent "Clear Chat" functionality filtered by `created_at > conversations.cleared_at`.

- **Client Privacy & Zero Footprint**:
  - Ephemeral voice note recording files (`.m4a` / `.webm`) are immediately deleted from device storage after being encoded into memory.
  - Contact codes are restricted from public search queries to prevent unauthorized enumeration.

---

## 🛡️ Security & Architecture

### Database Access Control (Supabase / PostgreSQL)
1. **Row-Level Security (RLS)**:
   - All tables (`profiles`, `conversations`, `conversation_members`, `messages`) have strict RLS enabled.
   - Only authenticated participants can select or post messages within conversations they belong to.
2. **RPC Caller Authorization**:
   - `find_or_create_direct_conversation` asserts `auth.uid() IN (p_user_id_1, p_user_id_2)`.
3. **Recipient Tampering Defense**:
   - PostgreSQL trigger (`protect_message_fields_on_recipient_update`) prevents recipients from modifying sender content, media data, timestamps, or message types when updating delivery or read receipts.
4. **View-Once Media Handling**:
   - View-once media is opened via RPC `mark_view_once_opened` and stripped client-side from local state once viewed.

---

## 🚀 Getting Started

### 1. Prerequisites
- [Flutter SDK](https://flutter.dev) (v3.12+ or 3.24+)
- A [Supabase](https://supabase.com) project

### 2. Supabase Setup
1. Open your Supabase Project Dashboard and navigate to the **SQL Editor**.
2. Run the consolidated setup script:
   - Execute [`supabase/migrations/all_in_one_setup.sql`](supabase/migrations/all_in_one_setup.sql).
3. If you have already executed migrations 00001 through 00004, simply execute:
   - [`supabase/migrations/00005_security_hardening.sql`](supabase/migrations/00005_security_hardening.sql).

### 3. Environment Configuration
Create a `.env` file in the project root:
```env
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-publishable-anon-key
```

Or provide credentials via `--dart-define` at build/run time:
```bash
flutter run \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-publishable-anon-key
```

---

## 📦 Building for Production

### Android (APK & App Bundle)
```bash
# Build split-per-ABI or universal Release APK
flutter build apk --release --dart-define-from-file=.env

# Build Android App Bundle (AAB) for Google Play
flutter build appbundle --release --dart-define-from-file=.env
```
*Permissions included:* `INTERNET`, `RECORD_AUDIO`, `POST_NOTIFICATIONS`, `VIBRATE`.

### iOS (IPA / Archive)
```bash
# Build iOS Release Archive
flutter build ipa --release --dart-define-from-file=.env
```
*Usage descriptions included:* Microphone, Camera, and Photo Library.

### Web (PWA)
```bash
# Build optimized Web release
flutter build web --release --dart-define-from-file=.env
```
*Deploy to Firebase Hosting or Vercel with provided `firebase.json` and `vercel.json` rewrite configurations.*

---

## 🧪 Quality & Testing

Verify formatting, static analysis, and automated test suite:

```bash
# Check code formatting
dart format --output=none --set-exit-if-changed lib test

# Static analysis (0 errors, 0 warnings)
flutter analyze

# Run unit and cryptographic tests
flutter test
```

---

## 📄 License
This project is proprietary and private. All rights reserved.
