import '../models/user_profile.dart';

/// Abstract auth repository contract.
///
/// UI code depends on this interface, never on the concrete implementation.
/// This enables testing with mocks and swapping backends.
abstract class AuthRepository {
  /// Sign up a new user with [username] and [password].
  ///
  /// Creates the Supabase Auth account using a pseudo-email
  /// (`username@anonapp.internal`) and inserts the profile row.
  /// Returns the newly created profile.
  Future<UserProfile> signUp({
    required String username,
    required String password,
  });

  /// Sign in an existing user.
  ///
  /// Returns the user's profile on success.
  Future<UserProfile> signIn({
    required String username,
    required String password,
  });

  /// Sign out the current user.
  Future<void> signOut();

  /// Get the currently authenticated user's profile, or `null`.
  Future<UserProfile?> getCurrentProfile();

  /// Stream of auth state changes — `true` when authenticated.
  Stream<bool> authStateChanges();

  /// Check whether a username is already taken.
  Future<bool> isUsernameTaken(String username);
}
