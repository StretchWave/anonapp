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

  /// Prefix identifying encrypted image payloads.
  static const String imagePrefix = 'ENC_IMG:v1:';

  /// Prefix identifying encrypted video payloads.
  static const String videoPrefix = 'ENC_VID:v1:';

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

  /// Returns true if [data] is an encrypted image payload produced by this service.
  static bool isImageEncrypted(String? data) {
    if (data == null) return false;
    return data.startsWith(imagePrefix);
  }

  /// Returns true if [data] is an encrypted video payload produced by this service.
  static bool isVideoEncrypted(String? data) {
    if (data == null) return false;
    return data.startsWith(videoPrefix);
  }

  /// Returns true if [data] is any media encrypted by this service.
  static bool isMediaEncrypted(String? data) {
    if (data == null) return false;
    return isImageEncrypted(data) || isAudioEncrypted(data) || isVideoEncrypted(data);
  }

  final Map<String, _KeyCacheEntry> _keyCache = {};
  static const Duration _cacheTtl = Duration(minutes: 5);
  static const int _maxCacheSize = 15;

  /// Visible for testing: current count of cached keys.
  @visibleForTesting
  int get keyCacheSize => _keyCache.length;

  /// Zeroizes and purges all cached keys from memory.
  /// Called when the app is paused, minimized, screen locked, or on user logout.
  void clearKeyCache() {
    _keyCache.clear();
  }

  /// Derives a deterministic 256-bit symmetric key from the conversation ID using HKDF-SHA256,
  /// caching the derived key in-memory with a 5-minute TTL to accelerate subsequent operations.
  Future<SecretKey> _deriveConversationKey(String conversationId) async {
    final now = DateTime.now();
    final cached = _keyCache[conversationId];
    if (cached != null && now.difference(cached.createdAt) < _cacheTtl) {
      cached.createdAt = now;
      return cached.key;
    }

    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

    final salt = utf8.encode('anonapp_e2ee_salt_v1');
    final secretKey = SecretKey(utf8.encode(conversationId));

    final derived = await hkdf.deriveKey(
      secretKey: secretKey,
      nonce: salt,
      info: utf8.encode('conversation_message_encryption'),
    );

    if (_keyCache.length >= _maxCacheSize) {
      _keyCache.remove(_keyCache.keys.first);
    }
    _keyCache[conversationId] = _KeyCacheEntry(derived, now);

    return derived;
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

  /// Encrypts raw image bytes using AES-256-GCM with conversation-derived key.
  /// Returns a formatted string: `ENC_IMG:v1:<nonce_b64>:<ciphertext_b64>:<mac_b64>`.
  Future<String> encryptImageBytes(
    List<int> imageBytes,
    String conversationId,
  ) async {
    final secretKey = await _deriveConversationKey(conversationId);

    final secretBox = await _algorithm.encrypt(
      imageBytes,
      secretKey: secretKey,
    );

    final nonceB64 = base64Encode(secretBox.nonce);
    final cipherB64 = base64Encode(secretBox.cipherText);
    final macB64 = base64Encode(secretBox.mac.bytes);

    return '$imagePrefix$nonceB64:$cipherB64:$macB64';
  }

  /// Decrypts image ciphertext back to raw bytes using AES-256-GCM.
  /// Returns null if authentication or decryption fails, without throwing.
  Future<Uint8List?> decryptImageBytes(
    String ciphertext,
    String conversationId,
  ) async {
    if (!isImageEncrypted(ciphertext)) {
      return null;
    }

    try {
      final payload = ciphertext.substring(imagePrefix.length);
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
        debugPrint('[EncryptionService] Image decryption failed: $e');
      }
      return null;
    }
  }

  /// Convenience helper to encrypt a base64-encoded image payload into an encrypted string.
  Future<String> encryptImage(
    String base64Image,
    String conversationId,
  ) async {
    var clean = base64Image.trim();
    if (clean.contains(',')) {
      clean = clean.split(',').last;
    }
    final bytes = base64Decode(clean);
    return encryptImageBytes(bytes, conversationId);
  }

  /// Convenience helper to decrypt an encrypted image payload back to a base64-encoded image string.
  /// If [ciphertext] is unencrypted (legacy image messages), it is returned unmodified for backward compatibility.
  /// Returns null if decryption fails (e.g. key mismatch or tampered payload).
  Future<String?> decryptImage(
    String ciphertext,
    String conversationId,
  ) async {
    if (!isImageEncrypted(ciphertext)) {
      // Legacy unencrypted base64 passes through unchanged
      return ciphertext;
    }

    final decryptedBytes = await decryptImageBytes(ciphertext, conversationId);
    if (decryptedBytes == null) {
      return null;
    }
    return base64Encode(decryptedBytes);
  }

  /// Encrypts raw video bytes using AES-256-GCM with conversation-derived key.
  /// Returns a formatted string: `ENC_VID:v1:<nonce_b64>:<ciphertext_b64>:<mac_b64>`.
  Future<String> encryptVideoBytes(
    List<int> videoBytes,
    String conversationId,
  ) async {
    final secretKey = await _deriveConversationKey(conversationId);

    final secretBox = await _algorithm.encrypt(
      videoBytes,
      secretKey: secretKey,
    );

    final nonceB64 = base64Encode(secretBox.nonce);
    final cipherB64 = base64Encode(secretBox.cipherText);
    final macB64 = base64Encode(secretBox.mac.bytes);

    return '$videoPrefix$nonceB64:$cipherB64:$macB64';
  }

  /// Decrypts video ciphertext back to raw bytes using AES-256-GCM.
  /// Returns null if authentication or decryption fails, without throwing.
  Future<Uint8List?> decryptVideoBytes(
    String ciphertext,
    String conversationId,
  ) async {
    if (!isVideoEncrypted(ciphertext)) {
      return null;
    }

    try {
      final payload = ciphertext.substring(videoPrefix.length);
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
        debugPrint('[EncryptionService] Video decryption failed: $e');
      }
      return null;
    }
  }

  /// Convenience helper to encrypt a base64-encoded video payload into an encrypted string.
  Future<String> encryptVideo(
    String base64Video,
    String conversationId,
  ) async {
    var clean = base64Video.trim();
    if (clean.contains(',')) {
      clean = clean.split(',').last;
    }
    final bytes = base64Decode(clean);
    return encryptVideoBytes(bytes, conversationId);
  }

  /// Convenience helper to decrypt an encrypted video payload back to a base64-encoded video string.
  Future<String?> decryptVideo(
    String ciphertext,
    String conversationId,
  ) async {
    if (!isVideoEncrypted(ciphertext)) {
      return ciphertext;
    }

    final decryptedBytes = await decryptVideoBytes(ciphertext, conversationId);
    if (decryptedBytes == null) {
      return null;
    }
    return base64Encode(decryptedBytes);
  }
}

class _KeyCacheEntry {
  _KeyCacheEntry(this.key, this.createdAt);
  final SecretKey key;
  DateTime createdAt;
}

