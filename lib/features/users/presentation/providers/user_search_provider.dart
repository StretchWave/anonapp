import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/supabase_service.dart';
import '../../../auth/domain/models/user_profile.dart';
import '../../data/user_repository.dart';

/// Provides the [UserRepository].
final userRepositoryProvider = Provider<UserRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return UserRepository(client);
});

/// Debounced user search provider.
/// Searches by username when query length >= 3.
final userSearchProvider = FutureProvider.family<List<UserProfile>, String>((
  ref,
  query,
) async {
  if (query.length < 3) return [];

  // Debounce: wait 300ms before searching.
  await Future<void>.delayed(const Duration(milliseconds: 300));

  // Check if the query is a contact code (8 alphanumeric chars).
  if (RegExp(r'^[A-Za-z0-9]{8}$').hasMatch(query)) {
    final repo = ref.watch(userRepositoryProvider);
    final result = await repo.searchByContactCode(query);
    return result != null ? [result] : [];
  }

  final repo = ref.watch(userRepositoryProvider);
  return repo.searchByUsername(query);
});
