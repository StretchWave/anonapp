import 'package:flutter/material.dart';

/// Curated colour palette for AnonApp.
///
/// Uses a modern dark-primary scheme with vibrant accent tones.
abstract final class AppColors {
  // ── Brand ──────────────────────────────────────────────────────
  static const Color primary = Color(0xFF6C63FF); // Vibrant indigo
  static const Color primaryLight = Color(0xFF918AFF);
  static const Color primaryDark = Color(0xFF4A42DB);

  static const Color secondary = Color(0xFF00D9A6); // Teal accent
  static const Color secondaryLight = Color(0xFF5EFFD4);
  static const Color secondaryDark = Color(0xFF00A87A);
  static const Color accent = secondary;

  // ── Surfaces (dark theme) ──────────────────────────────────────
  static const Color backgroundDark = Color(0xFF0F0F1A);
  static const Color surfaceDark = Color(0xFF1A1A2E);
  static const Color surfaceVariantDark = Color(0xFF252542);
  static const Color cardDark = Color(0xFF16213E);

  // ── Surfaces (light theme) ─────────────────────────────────────
  static const Color backgroundLight = Color(0xFFF8F9FA);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceVariantLight = Color(0xFFF0F0F5);
  static const Color cardLight = Color(0xFFFFFFFF);

  // ── Text ───────────────────────────────────────────────────────
  static const Color textPrimaryDark = Color(0xFFF0F0F5);
  static const Color textSecondaryDark = Color(0xFF9E9EBF);
  static const Color textPrimaryLight = Color(0xFF1A1A2E);
  static const Color textSecondaryLight = Color(0xFF6B6B8D);

  // ── Status ─────────────────────────────────────────────────────
  static const Color online = Color(0xFF00D97E);
  static const Color offline = Color(0xFF6B6B8D);
  static const Color error = Color(0xFFFF5252);
  static const Color warning = Color(0xFFFFB74D);
  static const Color success = Color(0xFF00D97E);

  // ── Chat bubbles ───────────────────────────────────────────────
  static const Color sentBubble = Color(0xFF6C63FF);
  static const Color receivedBubbleDark = Color(0xFF252542);
  static const Color receivedBubbleLight = Color(0xFFE8E8F0);
  static const Color sentBubbleText = Color(0xFFFFFFFF);
  static const Color receivedBubbleTextDark = Color(0xFFF0F0F5);
  static const Color receivedBubbleTextLight = Color(0xFF1A1A2E);

  // ── Misc ───────────────────────────────────────────────────────
  static const Color dividerDark = Color(0xFF2A2A4A);
  static const Color dividerLight = Color(0xFFE0E0EE);
  static const Color shimmerBase = Color(0xFF252542);
  static const Color shimmerHighlight = Color(0xFF3A3A5C);
}
