import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'app_exception.dart';

/// Centralised error handler that converts raw errors into user-friendly
/// messages.
abstract final class ErrorHandler {
  /// Convert any thrown error into an [AppException].
  static AppException handle(Object error, [StackTrace? stackTrace]) {
    debugPrint('[ERROR_HANDLER] Caught: $error');
    if (stackTrace != null) {
      debugPrint('[ERROR_HANDLER] Stack trace: $stackTrace');
    }

    // Already an AppException — pass through.
    if (error is AppException) return error;

    // Supabase Auth errors.
    if (error is sb.AuthException) {
      return AuthException(_mapAuthError(error.message), error);
    }

    // Supabase PostgREST errors.
    if (error is sb.PostgrestException) {
      return _mapPostgrestError(error);
    }

    // Network / generic fallback.
    final errorStr = error.toString().toLowerCase();
    if (errorStr.contains('socket') ||
        errorStr.contains('connection') ||
        errorStr.contains('timeout') ||
        errorStr.contains('network')) {
      return NetworkException(
        'Unable to connect. Please check your internet connection.',
        error,
      );
    }

    return DatabaseException(
      'Something went wrong: $error',
      error,
    );
  }

  /// Returns a user-safe string for common auth error messages.
  static String _mapAuthError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('invalid login')) {
      return 'Invalid username or password.';
    }
    if (lower.contains('email not confirmed')) {
      return 'Your account has not been confirmed.';
    }
    if (lower.contains('user already registered')) {
      return 'An account with that username already exists.';
    }
    if (lower.contains('password')) {
      return 'Password does not meet the requirements.';
    }
    if (lower.contains('rate limit')) {
      return 'Too many attempts. Please wait a moment.';
    }
    return 'Authentication failed: $raw';
  }

  /// Maps PostgREST errors to appropriate [AppException] subtypes.
  static AppException _mapPostgrestError(sb.PostgrestException error) {
    final code = error.code;

    // Relation does not exist (table not created in Supabase yet).
    if (code == '42P01') {
      return DatabaseException(
        'Database table not found (${error.message}). Please run the database setup script in Supabase SQL Editor.',
        error,
      );
    }

    // RLS violation / permission denied.
    if (code == '42501') {
      return PermissionException(
        'You do not have permission to perform this action (${error.message}).',
        error,
      );
    }

    // Unique constraint violation.
    if (code == '23505') {
      final msg = error.message.toLowerCase();
      if (msg.contains('username')) {
        return const ValidationException('That username is already taken.');
      }
      if (msg.contains('contact_code')) {
        return const ValidationException(
          'Contact code conflict. Please regenerate.',
        );
      }
      return ValidationException('A duplicate record was detected.', error);
    }

    // Check constraint violation.
    if (code == '23514') {
      return ValidationException('Input validation failed: ${error.message}', error);
    }

    // Foreign key violation.
    if (code == '23503') {
      return DatabaseException('Referenced record does not exist (${error.message}).', error);
    }

    return DatabaseException(
      error.message.isNotEmpty
          ? error.message
          : 'A database error occurred. Please try again.',
      error,
    );
  }

  /// Returns a short, safe message from an [AppException].
  static String userMessage(AppException exception) => exception.message;
}
