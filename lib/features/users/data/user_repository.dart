import 'package:supabase_flutter/supabase_flutter.dart' hide AuthException;

import '../../../core/constants/supabase_constants.dart';
import '../../../core/errors/error_handler.dart';
import '../../auth/domain/models/user_profile.dart';

/// Repository for user search operations.
class UserRepository {
  UserRepository(this._client);

  final SupabaseClient _client;

  /// Search for users by username (partial match, case-insensitive).
  /// Uses the controlled `search_public_profiles` RPC to protect sensitive columns.
  Future<List<UserProfile>> searchByUsername(String query) async {
    try {
      try {
        final rpcResult = await _client.rpc(
          'search_public_profiles',
          params: {'p_query': query.trim(), 'p_limit': 20},
        );
        if (rpcResult is List) {
          return rpcResult
              .map(
                (r) =>
                    UserProfile.fromJson(Map<String, dynamic>.from(r as Map)),
              )
              .toList();
        }
      } catch (_) {
        // Fallback for pre-migration environments
      }

      final userId = _client.auth.currentUser?.id;
      var filter = _client
          .from(SupabaseConstants.profilesTable)
          .select(
            'id, username, display_name, avatar, bio, interests, online_status_visible, created_at, last_seen',
          )
          .ilike('username', '%${query.trim()}%');

      if (userId != null) {
        filter = filter.neq('id', userId);
      }

      final results = await filter.limit(20);
      return results.map((r) => UserProfile.fromJson(r)).toList();
    } catch (e, st) {
      throw ErrorHandler.handle(e, st);
    }
  }

  /// Search for a user by exact contact code using the secure RPC.
  /// Never exposes contact codes of other users globally.
  Future<UserProfile?> searchByContactCode(String code) async {
    try {
      try {
        final rpcResult = await _client.rpc(
          'find_profile_by_contact_code',
          params: {'p_code': code.trim().toUpperCase()},
        );
        if (rpcResult != null) {
          return UserProfile.fromJson(
            Map<String, dynamic>.from(rpcResult as Map),
          );
        }
        return null;
      } catch (_) {
        // Fallback for pre-migration environments
      }

      final userId = _client.auth.currentUser?.id;
      final upperCode = code.trim().toUpperCase();

      var req = _client
          .from(SupabaseConstants.profilesTable)
          .select()
          .eq('contact_code', upperCode);

      if (userId != null) {
        req = req.neq('id', userId);
      }

      final result = await req.maybeSingle();
      if (result == null) return null;
      return UserProfile.fromJson(result);
    } catch (e, st) {
      throw ErrorHandler.handle(e, st);
    }
  }

  /// Get a single user's public profile by ID using the secure RPC.
  Future<UserProfile?> getProfileById(String userId) async {
    try {
      try {
        final rpcResult = await _client.rpc(
          'get_public_profile',
          params: {'p_user_id': userId},
        );
        if (rpcResult != null) {
          return UserProfile.fromJson(
            Map<String, dynamic>.from(rpcResult as Map),
          );
        }
        return null;
      } catch (_) {
        // Fallback for pre-migration environments
      }

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
