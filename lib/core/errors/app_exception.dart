/// Typed exception hierarchy for the application.
///
/// All user-facing errors extend [AppException] so the error handler
/// can produce consistent, safe messages without leaking internals.
sealed class AppException implements Exception {
  const AppException(this.message, [this.originalError]);

  /// A developer-readable description (never shown to users directly).
  final String message;

  /// The underlying error, if any.
  final Object? originalError;

  @override
  String toString() => '$runtimeType: $message';
}

/// Authentication-related errors (login, signup, session).
class AuthException extends AppException {
  const AuthException(super.message, [super.originalError]);
}

/// Network / connectivity errors.
class NetworkException extends AppException {
  const NetworkException(super.message, [super.originalError]);
}

/// Supabase database / PostgREST errors.
class DatabaseException extends AppException {
  const DatabaseException(super.message, [super.originalError]);
}

/// Input validation errors (username too short, etc.).
class ValidationException extends AppException {
  const ValidationException(super.message, [super.originalError]);
}

/// Permission / RLS violation errors.
class PermissionException extends AppException {
  const PermissionException(super.message, [super.originalError]);
}

/// A feature that is not yet implemented.
class NotImplementedException extends AppException {
  const NotImplementedException([String feature = 'This feature'])
      : super('$feature is not yet implemented.');
}
