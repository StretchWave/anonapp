import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/supabase_service.dart';
import '../../data/safety_repository.dart';

final safetyRepositoryProvider = Provider<SafetyRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return SafetyRepository(client);
});

final blockedUsersProvider =
    AsyncNotifierProvider<BlockedUsersNotifier, List<BlockedUser>>(
      BlockedUsersNotifier.new,
    );

class BlockedUsersNotifier extends AsyncNotifier<List<BlockedUser>> {
  SafetyRepository get _repo => ref.read(safetyRepositoryProvider);
  String? get _currentUserId =>
      ref.read(supabaseClientProvider).auth.currentUser?.id;

  @override
  FutureOr<List<BlockedUser>> build() async {
    final uid = _currentUserId;
    if (uid == null) return const [];
    return _repo.getBlockedUsers(uid);
  }

  Future<void> blockUser(String targetUserId, String targetUsername) async {
    final uid = _currentUserId;
    if (uid == null) return;
    await _repo.blockUser(
      currentUserId: uid,
      targetUserId: targetUserId,
      targetUsername: targetUsername,
    );
    ref.invalidateSelf();
  }

  Future<void> unblockUser(String targetUserId) async {
    final uid = _currentUserId;
    if (uid == null) return;
    await _repo.unblockUser(currentUserId: uid, targetUserId: targetUserId);
    ref.invalidateSelf();
  }
}

final privacySettingsProvider =
    AsyncNotifierProvider<PrivacySettingsNotifier, PrivacySettings>(
      PrivacySettingsNotifier.new,
    );

class PrivacySettingsNotifier extends AsyncNotifier<PrivacySettings> {
  SafetyRepository get _repo => ref.read(safetyRepositoryProvider);
  String? get _currentUserId =>
      ref.read(supabaseClientProvider).auth.currentUser?.id;

  @override
  FutureOr<PrivacySettings> build() async {
    final uid = _currentUserId;
    if (uid == null) return const PrivacySettings();
    return _repo.getPrivacySettings(uid);
  }

  Future<void> updateSettings(PrivacySettings newSettings) async {
    final uid = _currentUserId;
    if (uid == null) return;
    state = AsyncData(newSettings);
    await _repo.savePrivacySettings(currentUserId: uid, settings: newSettings);
  }
}
