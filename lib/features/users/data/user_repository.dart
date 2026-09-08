import 'package:supabase_flutter/supabase_flutter.dart' hide AuthException;

import '../../../core/constants/supabase_constants.dart';
import '../../../core/errors/error_handler.dart';
import '../../auth/domain/models/user_profile.dart';

/// Repository for user search operations.
class UserRepository {
  UserRepository(this._client);

  final SupabaseClient _client;

  /// Search for users by username (partial match, case-insensitive).
  /// Excludes the current user from results.
  Future<List<UserProfile>> searchByUsername(String query) async {
    try {
      final userId = _client.auth.currentUser!.id;

      final results = await _client
          .from(SupabaseConstants.profilesTable)
          .select('id, username, display_name, created_at, last_seen')
          .neq('id', userId)
          .ilike('username', '%$query%')
          .limit(20);

      return results.map((r) => UserProfile.fromJson(r)).toList();
    } catch (e, st) {
      throw ErrorHandler.handle(e, st);
    }
  }

  /// Search for a user by exact contact code.
  /// Excludes the current user.
  Future<UserProfile?> searchByContactCode(String code) async {
    try {
      final userId = _client.auth.currentUser!.id;
      final upperCode = code.toUpperCase();

      final result = await _client
          .from(SupabaseConstants.profilesTable)
          .select()
          .neq('id', userId)
          .eq('contact_code', upperCode)
          .maybeSingle();

      if (result == null) return null;
      return UserProfile.fromJson(result);
    } catch (e, st) {
      throw ErrorHandler.handle(e, st);
    }
  }

  /// Get a single user profile by ID.
  Future<UserProfile?> getProfileById(String userId) async {
    try {
      final result = await _client
          .from(SupabaseConstants.profilesTable)
          .select()
          .eq('id', userId)
          .maybeSingle();

      if (result == null) return null;
      return UserProfile.fromJson(result);
    } catch (e, st) {
      throw ErrorHandler.handle(e, st);
    }
  }
}
