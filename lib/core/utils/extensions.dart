import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;

/// Convenience extensions used across the app.

extension StringX on String {
  /// Convert a username to the pseudo-email used for Supabase Auth.
  String toAuthEmail(String domain) => '$this@$domain';
}

extension DateTimeX on DateTime {
  /// Relative time string like "2 minutes ago".
  String get timeAgo => timeago.format(this);

  /// Short time format: "14:30" or "2:30 PM".
  String get shortTime {
    final hour = this.hour.toString().padLeft(2, '0');
    final minute = this.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  /// Date string: "Sep 7, 2026".
  String get shortDate {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[month - 1]} $day, $year';
  }

  /// Shows time if today, date otherwise.
  String get chatTimestamp {
    final now = DateTime.now();
    if (year == now.year && month == now.month && day == now.day) {
      return shortTime;
    }
    return shortDate;
  }
}

extension ContextX on BuildContext {
  /// Shortcut for `Theme.of(context)`.
  ThemeData get theme => Theme.of(this);

  /// Shortcut for `Theme.of(context).colorScheme`.
  ColorScheme get colorScheme => Theme.of(this).colorScheme;

  /// Shortcut for `Theme.of(context).textTheme`.
  TextTheme get textTheme => Theme.of(this).textTheme;

  /// Shortcut for `MediaQuery.sizeOf(context)`.
  Size get screenSize => MediaQuery.sizeOf(this);

  /// Show a snackbar with a message.
  void showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError
            ? Theme.of(this).colorScheme.error
            : Theme.of(this).colorScheme.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
