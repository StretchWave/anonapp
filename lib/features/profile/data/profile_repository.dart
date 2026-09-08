import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/supabase_constants.dart';
import '../../auth/domain/models/user_profile.dart';

/// Predefined avatar styles that protect real identity while providing personality.
class AnonymousAvatars {
  static const List<AnonymousAvatarPreset> presets = [
    AnonymousAvatarPreset(
      id: 'ghost',
      name: 'Phantom',
      emoji: '👻',
      colorHex: 0xFF968AF0,
    ),
    AnonymousAvatarPreset(
      id: 'fox',
      name: 'Cyber Fox',
      emoji: '🦊',
      colorHex: 0xFFFF7675,
    ),
    AnonymousAvatarPreset(
      id: 'ninja',
      name: 'Shadow Shinobi',
      emoji: '🥷',
      colorHex: 0xFF00D9A6,
    ),
    AnonymousAvatarPreset(
      id: 'robot',
      name: 'Quantum Bot',
      emoji: '🤖',
      colorHex: 0xFF74B9FF,
    ),
    AnonymousAvatarPreset(
      id: 'owl',
      name: 'Nocturnal Owl',
      emoji: '🦉',
      colorHex: 0xFFA29BFE,
    ),
    AnonymousAvatarPreset(
      id: 'cat',
      name: 'Neon Stray',
      emoji: '🐱',
      colorHex: 0xFFFD79A8,
    ),
    AnonymousAvatarPreset(
      id: 'alien',
      name: 'Cosmic Anon',
      emoji: '👽',
      colorHex: 0xFF55EFC4,
    ),
    AnonymousAvatarPreset(
      id: 'wizard',
      name: 'Arcane Cipher',
      emoji: '🧙',
      colorHex: 0xFFE17055,
    ),
  ];

  static AnonymousAvatarPreset getPreset(String? id) {
    return presets.firstWhere((p) => p.id == id, orElse: () => presets.first);
  }
}

class AnonymousAvatarPreset {
  const AnonymousAvatarPreset({
    required this.id,
    required this.name,
    required this.emoji,
    required this.colorHex,
  });

  final String id;
  final String name;
  final String emoji;
  final int colorHex;
}

/// Hybrid repository managing extended profile attributes, personas, and interests.
class ProfileRepository {
  ProfileRepository(this._client);

  final SupabaseClient _client;

  String _key(String userId, String field) => 'anon_profile_${userId}_$field';

  /// Loads local profile extensions (bio, avatar, interests, persona) for [profile].
  Future<UserProfile> enrichProfile(UserProfile profile) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final localBio = prefs.getString(_key(profile.id, 'bio'));
      final localAvatar = prefs.getString(_key(profile.id, 'avatar'));
      final localInterestsStr = prefs.getString(_key(profile.id, 'interests'));
      final localPersona = prefs.getString(_key(profile.id, 'persona'));
      final localOnlineVisible = prefs.getBool(
        _key(profile.id, 'online_visible'),
      );

      List<String>? localInterests;
      if (localInterestsStr != null) {
        try {
          final decoded = jsonDecode(localInterestsStr);
          if (decoded is List) {
            localInterests = decoded.map((e) => e.toString()).toList();
          }
        } catch (_) {}
      }

      return profile.copyWith(
        bio: localBio ?? profile.bio,
        avatar: localAvatar ?? profile.avatar,
        interests: localInterests ?? profile.interests,
        persona: localPersona ?? profile.persona,
        onlineStatusVisible: localOnlineVisible ?? profile.onlineStatusVisible,
      );
    } catch (e) {
      debugPrint('Error enriching profile from local prefs: $e');
      return profile;
    }
  }

  /// Updates profile attributes both in local storage and in remote Supabase.
  Future<UserProfile> updateProfile({
    required UserProfile currentProfile,
    String? displayName,
    String? bio,
    String? avatar,
    List<String>? interests,
    String? persona,
    bool? onlineStatusVisible,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = currentProfile.id;

    // 1. Save locally immediately.
    if (bio != null) await prefs.setString(_key(userId, 'bio'), bio);
    if (avatar != null) await prefs.setString(_key(userId, 'avatar'), avatar);
    if (interests != null) {
      await prefs.setString(_key(userId, 'interests'), jsonEncode(interests));
    }
    if (persona != null) {
      await prefs.setString(_key(userId, 'persona'), persona);
    }
    if (onlineStatusVisible != null) {
      await prefs.setBool(_key(userId, 'online_visible'), onlineStatusVisible);
    }

    final updated = currentProfile.copyWith(
      displayName: displayName,
      bio: bio,
      avatar: avatar,
      interests: interests,
      persona: persona,
      onlineStatusVisible: onlineStatusVisible,
    );

    // 2. Best-effort update to Supabase.
    try {
      final remoteUpdate = <String, dynamic>{};
      if (displayName != null) remoteUpdate['display_name'] = displayName;
      if (bio != null) remoteUpdate['bio'] = bio;
      if (avatar != null) remoteUpdate['avatar'] = avatar;
      if (interests != null) remoteUpdate['interests'] = interests;
      if (persona != null) remoteUpdate['persona'] = persona;
      if (onlineStatusVisible != null) {
        remoteUpdate['online_status_visible'] = onlineStatusVisible;
      }

      if (remoteUpdate.isNotEmpty) {
        await _client
            .from(SupabaseConstants.profilesTable)
            .update(remoteUpdate)
            .eq('id', userId);
      }
    } catch (e) {
      // If remote table lacks new columns yet or network is down, local storage
      // already ensures the user's preferences are preserved.
      debugPrint('Remote profile update note: $e');
    }

    return updated;
  }

  /// Retrieves list of saved anonymous personas for the account.
  Future<List<String>> getSavedPersonas(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList('anon_personas_$userId');
      if (raw != null && raw.isNotEmpty) return raw;
      return const ['GhostRunner', 'NightCoder', 'PixelFox'];
    } catch (_) {
      return const ['GhostRunner', 'NightCoder', 'PixelFox'];
    }
  }

  /// Adds a new persona.
  Future<void> addPersona(String userId, String personaName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = await getSavedPersonas(userId);
      if (!existing.contains(personaName)) {
        final updated = [...existing, personaName];
        await prefs.setStringList('anon_personas_$userId', updated);
      }
    } catch (e) {
      debugPrint('Failed to save persona: $e');
    }
  }
}
