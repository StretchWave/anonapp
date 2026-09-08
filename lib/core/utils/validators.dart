import '../constants/app_constants.dart';

/// Validation utilities for user input.
///
/// Every method returns `null` on success or a user-facing error string.
abstract final class Validators {
  /// Username: 3–30 chars, alphanumeric + underscores, must start with a letter.
  static String? username(String? value) {
    if (value == null || value.isEmpty) {
      return 'Username is required.';
    }
    if (value.length < AppConstants.usernameMinLength) {
      return 'Username must be at least ${AppConstants.usernameMinLength} characters.';
    }
    if (value.length > AppConstants.usernameMaxLength) {
      return 'Username must be at most ${AppConstants.usernameMaxLength} characters.';
    }
    if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*$').hasMatch(value)) {
      return 'Username must start with a letter and contain only letters, numbers, and underscores.';
    }
    return null;
  }

  /// Password: at least 8 characters.
  static String? password(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password is required.';
    }
    if (value.length < AppConstants.passwordMinLength) {
      return 'Password must be at least ${AppConstants.passwordMinLength} characters.';
    }
    return null;
  }

  /// Confirm password must match the original.
  static String? confirmPassword(String? value, String original) {
    final base = password(value);
    if (base != null) return base;
    if (value != original) {
      return 'Passwords do not match.';
    }
    return null;
  }

  /// Display name: optional, max 50 chars, no leading/trailing whitespace.
  static String? displayName(String? value) {
    if (value == null || value.isEmpty) return null; // optional
    if (value.length > AppConstants.displayNameMaxLength) {
      return 'Display name must be at most ${AppConstants.displayNameMaxLength} characters.';
    }
    if (value.trim() != value) {
      return 'Display name must not have leading or trailing spaces.';
    }
    return null;
  }

  /// Contact code: exactly 8 alphanumeric characters.
  static String? contactCode(String? value) {
    if (value == null || value.isEmpty) return null; // optional for search
    if (!RegExp(r'^[A-Z0-9]{8}$').hasMatch(value.toUpperCase())) {
      return 'Contact code must be exactly 8 alphanumeric characters.';
    }
    return null;
  }

  /// Generic non-empty check.
  static String? required(String? value, [String fieldName = 'This field']) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required.';
    }
    return null;
  }

  /// Message content: non-empty, max 5000 chars.
  static String? messageContent(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Message cannot be empty.';
    }
    if (value.length > 5000) {
      return 'Message is too long.';
    }
    return null;
  }
}
