import 'package:supabase_flutter/supabase_flutter.dart' hide AuthException;

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/supabase_constants.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/utils/extensions.dart';
import '../domain/models/user_profile.dart';
import '../domain/repositories/auth_repository.dart';

/// Concrete [AuthRepository] implementation backed by Supabase.
class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl(this._client);

  final SupabaseClient _client;

  GoTrueClient get _auth => _client.auth;

  /// Converts a username to the pseudo-email used for Supabase Auth.
  String _toEmail(String username) =>
      username.toLowerCase().toAuthEmail(AppConstants.authEmailDomain);

  @override
  Future<UserProfile> signUp({
    required String username,
    required String password,
  }) async {
    try {
      final email = _toEmail(username);

      // 1. Check username uniqueness first (friendlier error).
      if (await isUsernameTaken(username)) {
        throw const ValidationException('That username is already taken.');
      }

      // 2. Create the auth user.
      final response = await _auth.signUp(
        email: email,
        password: password,
      );

      final user = response.user;
      if (user == null) {
        throw const AuthException('Sign-up failed. Please try again.');
      }

      // 3. Insert the profile row.
      final profileData = {
        'id': user.id,
        'username': username.toLowerCase(),
      };

      await _client
          .from(SupabaseConstants.profilesTable)
          .insert(profileData);

      // 4. Fetch and return the created profile (includes DB-generated fields).
      final row = await _client
          .from(SupabaseConstants.profilesTable)
          .select()
          .eq('id', user.id)
          .single();

      return UserProfile.fromJson(row);
    } on AppException {
      rethrow;
    } catch (e, st) {
      throw ErrorHandler.handle(e, st);
    }
  }

  @override
  Future<UserProfile> signIn({
    required String username,
    required String password,
  }) async {
    try {
      final email = _toEmail(username);

      await _auth.signInWithPassword(
        email: email,
        password: password,
      );

      final userId = _auth.currentUser?.id;
      if (userId == null) {
        throw const AuthException('Sign-in failed. Please try again.');
      }

      // Fetch profile.
      final row = await _client
          .from(SupabaseConstants.profilesTable)
          .select()
          .eq('id', userId)
          .single();

      // Update last_seen.
      await _client
          .from(SupabaseConstants.profilesTable)
          .update({'last_seen': DateTime.now().toUtc().toIso8601String()})
          .eq('id', userId);

      return UserProfile.fromJson(row);
    } on AppException {
      rethrow;
    } catch (e, st) {
      throw ErrorHandler.handle(e, st);
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (e, st) {
      throw ErrorHandler.handle(e, st);
    }
  }

  @override
  Future<UserProfile?> getCurrentProfile() async {
    try {
      final userId = _auth.currentUser?.id;
      if (userId == null) return null;

      final row = await _client
          .from(SupabaseConstants.profilesTable)
          .select()
          .eq('id', userId)
          .maybeSingle();

      if (row == null) return null;
      return UserProfile.fromJson(row);
    } catch (e, st) {
      throw ErrorHandler.handle(e, st);
    }
  }

  @override
  Stream<bool> authStateChanges() async* {
    yield _auth.currentSession != null;
    yield* _auth.onAuthStateChange.map(
      (event) => event.session != null,
    );
  }

  @override
  Future<bool> isUsernameTaken(String username) async {
    try {
      final result = await _client
          .from(SupabaseConstants.profilesTable)
          .select('id')
          .eq('username', username.toLowerCase())
          .maybeSingle();

      return result != null;
    } catch (e, st) {
      throw ErrorHandler.handle(e, st);
    }
  }
}
