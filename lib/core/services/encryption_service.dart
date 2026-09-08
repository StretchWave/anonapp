import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

/// Application-layer symmetric encryption service for conversation text and voice messages using AES-256-GCM.
/// Media (images, view-once photos, videos) remains saved on the server as requested.
class EncryptionService {
  EncryptionService._();
  static final EncryptionService instance = EncryptionService._();

  final AesGcm _algorithm = AesGcm.with256bits();

  static const String _prefix = 'ENC:v1:';

  /// Prefix identifying encrypted audio payloads.
  static const String audioPrefix = 'ENC_AUDIO:v1:';

  /// Returns true if [text] is an encrypted text payload produced by this service.
  static bool isEncrypted(String? text) {
    if (text == null) return false;
    return text.startsWith(_prefix);
  }

  /// Returns true if [data] is an encrypted audio payload produced by this service.
  static bool isAudioEncrypted(String? data) {
    if (data == null) return false;
    return data.startsWith(audioPrefix);
  }

  /// Derives a deterministic 256-bit symmetric key from the conversation ID using HKDF-SHA256.
  Future<SecretKey> _deriveConversationKey(String conversationId) async {
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

    final salt = utf8.encode('anonapp_e2ee_salt_v1');
    final secretKey = SecretKey(utf8.encode(conversationId));

    return hkdf.deriveKey(
      secretKey: secretKey,
      nonce: salt,
      info: utf8.encode('conversation_message_encryption'),
    );
  }

  /// Encrypts plaintext message content using AES-256-GCM.
  /// Returns a formatted string: `ENC:v1:<nonce_b64>:<ciphertext_b64>:<mac_b64>`.
  Future<String> encryptText(String plaintext, String conversationId) async {
    final secretKey = await _deriveConversationKey(conversationId);
    final clearBytes = utf8.encode(plaintext);

    final secretBox = await _algorithm.encrypt(
      clearBytes,
      secretKey: secretKey,
    );

    final nonceB64 = base64Encode(secretBox.nonce);
    final cipherB64 = base64Encode(secretBox.cipherText);
    final macB64 = base64Encode(secretBox.mac.bytes);

    return '$_prefix$nonceB64:$cipherB64:$macB64';
  }

  /// Decrypts ciphertext back to plaintext.
  /// If [ciphertext] is unencrypted (e.g. historical messages), returns it unmodified.
  Future<String> decryptText(String ciphertext, String conversationId) async {
    if (!isEncrypted(ciphertext)) {
      return ciphertext;
    }

    try {
      final payload = ciphertext.substring(_prefix.length);
      final parts = payload.split(':');
      if (parts.length != 3) {
        return ciphertext;
      }

      final nonce = base64Decode(parts[0]);
      final cipherBytes = base64Decode(parts[1]);
      final macBytes = base64Decode(parts[2]);

      final secretKey = await _deriveConversationKey(conversationId);
      final secretBox = SecretBox(
        cipherBytes,
        nonce: nonce,
        mac: Mac(macBytes),
      );

      final decryptedBytes = await _algorithm.decrypt(
        secretBox,
        secretKey: secretKey,
      );

      return utf8.decode(decryptedBytes);
    } catch (_) {
      // In case of error or key mismatch, return original ciphertext safely
      return ciphertext;
    }
  }

  /// Encrypts raw audio bytes using AES-256-GCM with conversation-derived key.
  /// Returns a formatted string: `ENC_AUDIO:v1:<nonce_b64>:<ciphertext_b64>:<mac_b64>`.
  Future<String> encryptAudioBytes(
    List<int> audioBytes,
    String conversationId,
  ) async {
    final secretKey = await _deriveConversationKey(conversationId);

    final secretBox = await _algorithm.encrypt(
      audioBytes,
      secretKey: secretKey,
    );

    final nonceB64 = base64Encode(secretBox.nonce);
    final cipherB64 = base64Encode(secretBox.cipherText);
    final macB64 = base64Encode(secretBox.mac.bytes);

    return '$audioPrefix$nonceB64:$cipherB64:$macB64';
  }

  /// Decrypts audio ciphertext back to raw bytes using AES-256-GCM.
  /// Returns null if authentication or decryption fails, without throwing.
  Future<Uint8List?> decryptAudioBytes(
    String ciphertext,
    String conversationId,
  ) async {
    if (!isAudioEncrypted(ciphertext)) {
      return null;
    }

    try {
      final payload = ciphertext.substring(audioPrefix.length);
      final parts = payload.split(':');
      if (parts.length != 3) {
        return null;
      }

      final nonce = base64Decode(parts[0]);
      final cipherBytes = base64Decode(parts[1]);
      final macBytes = base64Decode(parts[2]);

      final secretKey = await _deriveConversationKey(conversationId);
      final secretBox = SecretBox(
        cipherBytes,
        nonce: nonce,
        mac: Mac(macBytes),
      );

      final decryptedBytes = await _algorithm.decrypt(
        secretBox,
        secretKey: secretKey,
      );

      return Uint8List.fromList(decryptedBytes);
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[EncryptionService] Audio decryption failed: ${e.runtimeType}',
        );
      }
      return null;
    }
  }

  /// Convenience helper to encrypt a base64-encoded audio payload into an encrypted string.
  Future<String> encryptAudio(
    String base64Audio,
    String conversationId,
  ) async {
    final bytes = base64Decode(base64Audio);
    return encryptAudioBytes(bytes, conversationId);
  }

  /// Convenience helper to decrypt an encrypted audio payload back to a base64-encoded audio string.
  /// If [ciphertext] is unencrypted (legacy audio messages), it is returned unmodified for backward compatibility.
  /// Returns null if decryption fails (e.g. key mismatch or tampered payload).
  Future<String?> decryptAudio(
    String ciphertext,
    String conversationId,
  ) async {
    if (!isAudioEncrypted(ciphertext)) {
      // Legacy unencrypted base64 audio passes through unchanged
      return ciphertext;
    }

    final decryptedBytes = await decryptAudioBytes(ciphertext, conversationId);
    if (decryptedBytes == null) {
      return null;
    }
    return base64Encode(decryptedBytes);
  }
}
