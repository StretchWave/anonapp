# AnonApp — E2EE Media & Message Recovery Guide

This document contains the exact cryptographic specifications, derivation formulas, and standalone recovery scripts to decrypt and recover any message, voice note, image, or video directly from the database without needing the Flutter app.

---

## 1. Cryptographic Specifications

All client-side end-to-end encryption in AnonApp uses industry-standard symmetric cryptography:

| Component | Specification | Notes |
|---|---|---|
| **Cipher** | `AES-256-GCM` | 256-bit key, 96-bit random nonce, 128-bit authentication tag |
| **KDF** | `HKDF-SHA256` (RFC 5869) | Deterministic key derived per conversation |
| **Salt** | `anonapp_e2ee_salt_v1` | UTF-8 encoded string (20 bytes) |
| **Info / Label** | `conversation_message_encryption` | UTF-8 domain separator string (32 bytes) |
| **Input Key (IKM)**| `conversation_id` | Conversation UUID string (e.g. `d7e2...`) |
| **Derived Key** | `32 bytes` (256 bits) | Secret symmetric key for AES-GCM |

---

## 2. Payload Formats in `public.messages`

Encrypted database fields (`content` or `media_data`) are stored as formatted colon-delimited strings:

```
Text:   ENC:v1:<nonce_b64>:<ciphertext_b64>:<mac_b64>
Voice:  ENC_AUDIO:v1:<nonce_b64>:<ciphertext_b64>:<mac_b64>
Image:  ENC_IMG:v1:<nonce_b64>:<ciphertext_b64>:<mac_b64>
Video:  ENC_VID:v1:<nonce_b64>:<ciphertext_b64>:<mac_b64>
```

Where:
* `<nonce_b64>`: 12-byte initialization vector, Base64-encoded.
* `<ciphertext_b64>`: AES-256-GCM encrypted payload, Base64-encoded.
* `<mac_b64>`: 16-byte GCM authentication tag, Base64-encoded.

---

## 3. Standalone Python Recovery Script

Save this script as `decrypt_anonapp.py` and run with `python decrypt_anonapp.py`:

```python
import base64
import sys
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from cryptography.hazmat.primitives import hashes

def derive_conversation_key(conversation_id: str) -> bytes:
    """Derives the 256-bit AES key for the given conversation ID."""
    hkdf = HKDF(
        algorithm=hashes.SHA256(),
        length=32,
        salt=b'anonapp_e2ee_salt_v1',
        info=b'conversation_message_encryption',
    )
    return hkdf.derive(conversation_id.encode('utf-8'))

def decrypt_payload(encrypted_text: str, conversation_id: str) -> bytes:
    """Decrypts any AnonApp payload (Text, Audio, Image, Video) back to raw bytes."""
    prefixes = ['ENC:v1:', 'ENC_AUDIO:v1:', 'ENC_IMG:v1:', 'ENC_VID:v1:']
    raw_payload = encrypted_text.strip()
    for prefix in prefixes:
        if raw_payload.startswith(prefix):
            raw_payload = raw_payload[len(prefix):]
            break

    parts = raw_payload.split(':')
    if len(parts) != 3:
        raise ValueError("Invalid format: expected nonce:ciphertext:mac")

    nonce = base64.b64decode(parts[0])
    ciphertext = base64.b64decode(parts[1])
    mac = base64.b64decode(parts[2])

    key = derive_conversation_key(conversation_id)
    aesgcm = AESGCM(key)

    return aesgcm.decrypt(nonce, ciphertext + mac, None)

if __name__ == '__main__':
    conv_id = "YOUR_CONVERSATION_ID_HERE"
    enc_data = "ENC_IMG:v1:..."

    decrypted_bytes = decrypt_payload(enc_data, conv_id)
    with open("recovered_media.png", "wb") as f:
        f.write(decrypted_bytes)
    print("Decryption successful! Saved to recovered_media.png")
```

---

## 4. Standalone Node.js Recovery Script

Save this script as `decrypt_anonapp.js` and run with `node decrypt_anonapp.js`:

```javascript
const crypto = require('crypto');
const fs = require('fs');

function deriveConversationKey(conversationId) {
  const salt = Buffer.from('anonapp_e2ee_salt_v1', 'utf8');
  const info = Buffer.from('conversation_message_encryption', 'utf8');
  const ikm = Buffer.from(conversationId, 'utf8');

  return crypto.hkdfSync('sha256', ikm, salt, info, 32);
}

function decryptPayload(encryptedText, conversationId) {
  const clean = encryptedText.trim().replace(/^(ENC:v1:|ENC_AUDIO:v1:|ENC_IMG:v1:|ENC_VID:v1:)/, '');
  const [nonceB64, cipherB64, macB64] = clean.split(':');

  if (!nonceB64 || !cipherB64 || !macB64) {
    throw new Error('Invalid format: expected nonce:ciphertext:mac');
  }

  const key = deriveConversationKey(conversationId);
  const nonce = Buffer.from(nonceB64, 'base64');
  const ciphertext = Buffer.from(cipherB64, 'base64');
  const mac = Buffer.from(macB64, 'base64');

  const decipher = crypto.createDecipheriv('aes-256-gcm', key, nonce);
  decipher.setAuthTag(mac);

  return Buffer.concat([
    decipher.update(ciphertext),
    decipher.final()
  ]);
}

// Example:
// const convId = 'YOUR_CONVERSATION_ID_HERE';
// const encData = 'ENC_IMG:v1:...';
// const recoveredBuffer = decryptPayload(encData, convId);
// fs.writeFileSync('recovered_photo.png', recoveredBuffer);
```
