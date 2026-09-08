import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/supabase_service.dart';
import '../../../auth/domain/models/user_profile.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../conversations/presentation/providers/conversation_provider.dart';
import '../../data/profile_repository.dart';
import 'bookmark_provider.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return ProfileRepository(client);
});

/// Returns the current profile enriched with locally saved extensions (bio, avatar, interests, persona).
final currentEnrichedProfileProvider = FutureProvider<UserProfile?>((
  ref,
) async {
  final baseProfile = await ref.watch(currentProfileProvider.future);
  if (baseProfile == null) return null;

  final repo = ref.watch(profileRepositoryProvider);
  return repo.enrichProfile(baseProfile);
});

/// Profile statistics (real calculated metrics from active conversations, bookmarks, and account age).
final profileStatsProvider = FutureProvider<Map<String, int>>((ref) async {
  final profile = await ref.watch(currentEnrichedProfileProvider.future);
  if (profile == null) return {'chats': 0, 'bookmarks': 0, 'days': 1};

  final conversationsAsync = ref.watch(conversationsProvider);
  final bookmarksAsync = ref.watch(bookmarksProvider);

  final chatsCount = conversationsAsync.valueOrNull?.length ?? 0;
  final bookmarksCount = bookmarksAsync.valueOrNull?.length ?? 0;
  final daysActive = DateTime.now().difference(profile.createdAt).inDays + 1;

  return {
    'chats': chatsCount,
    'bookmarks': bookmarksCount,
    'days': daysActive > 0 ? daysActive : 1,
  };
});

/// Notifier handling profile mutations.
final profileNotifierProvider =
    AsyncNotifierProvider<ProfileNotifier, UserProfile?>(ProfileNotifier.new);

class ProfileNotifier extends AsyncNotifier<UserProfile?> {
  ProfileRepository get _repo => ref.read(profileRepositoryProvider);

  @override
  FutureOr<UserProfile?> build() async {
    return ref.watch(currentEnrichedProfileProvider.future);
  }

  Future<void> updateProfile({
    String? displayName,
    String? bio,
    String? avatar,
    List<String>? interests,
    String? persona,
    bool? onlineStatusVisible,
  }) async {
    final current = state.valueOrNull;
    if (current == null) return;

    state = const AsyncLoading();
    try {
      final updated = await _repo.updateProfile(
        currentProfile: current,
        displayName: displayName,
        bio: bio,
        avatar: avatar,
        interests: interests,
        persona: persona,
        onlineStatusVisible: onlineStatusVisible,
      );
      state = AsyncData(updated);
      ref.invalidate(currentEnrichedProfileProvider);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<void> switchPersona(String personaName) async {
    await updateProfile(persona: personaName);
  }
}

/// Personas list provider for the current user.
final personasListProvider = FutureProvider<List<String>>((ref) async {
  final profile = await ref.watch(currentEnrichedProfileProvider.future);
  if (profile == null) return const [];
  final repo = ref.watch(profileRepositoryProvider);
  return repo.getSavedPersonas(profile.id);
});
