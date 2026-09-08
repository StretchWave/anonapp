import 'package:flutter/material.dart';

/// Curated color palette and design tokens for AnonApp.
///
/// Follows a sophisticated dark-first aesthetic with layered near-black surfaces,
/// refined purple/indigo accents, and subtle teal highlights.
abstract final class AppColors {
  // ── Brand Accents ───────────────────────────────────────────────
  static const Color primary = Color(
    0xFF7C6EE6,
  ); // Modern vibrant purple/indigo
  static const Color primaryLight = Color(0xFF9E92FA);
  static const Color primaryDark = Color(0xFF5A4BC7);

  static const Color secondary = Color(0xFF00D9A6); // Privacy teal accent
  static const Color secondaryLight = Color(0xFF5EFFD4);
  static const Color secondaryDark = Color(0xFF00A87A);
  static const Color accent = secondary;

  // ── Surfaces (Dark Theme) ───────────────────────────────────────
  static const Color backgroundDark = Color(0xFF090B10); // Deep near-black
  static const Color surfaceDark = Color(
    0xFF11141E,
  ); // Layer 1 (Sheets, Appbar, Nav)
  static const Color surfaceVariantDark = Color(
    0xFF181C2A,
  ); // Layer 2 (Inputs, chips)
  static const Color cardDark = Color(0xFF131722); // Cards surface
  static const Color surfaceHoverDark = Color(0xFF1E2335);

  // ── Low-Contrast Borders ─────────────────────────────────────────
  static const Color surfaceBorder = Color(0xFF22283A);
  static const Color surfaceBorderGlow = Color(0xFF333B54);
  static const Color surfaceBorderLight = Color(0xFFE2E4ED);

  // ── Surfaces (Light Theme fallback) ──────────────────────────────
  static const Color backgroundLight = Color(0xFFF8F9FC);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceVariantLight = Color(0xFFF0F2F8);
  static const Color cardLight = Color(0xFFFFFFFF);

  // ── Text ─────────────────────────────────────────────────────────
  static const Color textPrimaryDark = Color(0xFFF2F4F8);
  static const Color textSecondaryDark = Color(0xFF949AB0);
  static const Color textMutedDark = Color(0xFF61677D);

  static const Color textPrimaryLight = Color(0xFF11141E);
  static const Color textSecondaryLight = Color(0xFF6B7280);

  // ── Status Indicators ────────────────────────────────────────────
  static const Color online = Color(0xFF00E676);
  static const Color offline = Color(0xFF6B7280);
  static const Color error = Color(0xFFFF4D4D);
  static const Color warning = Color(0xFFFFB020);
  static const Color success = Color(0xFF00E676);

  // ── Chat Bubbles ─────────────────────────────────────────────────
  static const Color sentBubble = Color(0xFF7C6EE6);
  static const Color receivedBubbleDark = Color(0xFF181C2A);
  static const Color receivedBubbleLight = Color(0xFFEAECEF);
  static const Color sentBubbleText = Colors.white;
  static const Color receivedBubbleTextDark = Color(0xFFF2F4F8);
  static const Color receivedBubbleTextLight = Color(0xFF11141E);

  // ── Shimmer & Dividers ───────────────────────────────────────────
  static const Color dividerDark = Color(0xFF1D2232);
  static const Color dividerLight = Color(0xFFE5E7EB);
  static const Color shimmerBase = Color(0xFF151926);
  static const Color shimmerHighlight = Color(0xFF242A3E);

  // ── Gradients ────────────────────────────────────────────────────
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF8B7DFF), Color(0xFF6756EA)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient accentGradient = LinearGradient(
    colors: [Color(0xFF7C6EE6), Color(0xFF00D9A6)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [Color(0xFF151926), Color(0xFF10131E)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient sentBubbleGradient = LinearGradient(
    colors: [Color(0xFF8677FF), Color(0xFF6958ED)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient glowGradient = LinearGradient(
    colors: [Color(0x407C6EE6), Colors.transparent],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // ── Shadows ──────────────────────────────────────────────────────
  static const List<BoxShadow> softShadow = [
    BoxShadow(color: Color(0x33000000), blurRadius: 16, offset: Offset(0, 4)),
  ];

  static const List<BoxShadow> primaryGlow = [
    BoxShadow(
      color: Color(0x447C6EE6),
      blurRadius: 18,
      spreadRadius: -2,
      offset: Offset(0, 4),
    ),
  ];

  static const List<BoxShadow> cardShadow = [
    BoxShadow(color: Color(0x2B000000), blurRadius: 14, offset: Offset(0, 2)),
  ];
}
