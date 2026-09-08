import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A modern, layered surface card with rounded corners, low-contrast border,
/// optional gradient background, and optional click response.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.margin,
    this.onTap,
    this.borderRadius = 18,
    this.borderColor,
    this.backgroundColor,
    this.useGradient = false,
    this.hasGlow = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final double borderRadius;
  final Color? borderColor;
  final Color? backgroundColor;
  final bool useGradient;
  final bool hasGlow;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor ?? (useGradient ? null : AppColors.cardDark),
        gradient: useGradient ? AppColors.cardGradient : null,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: borderColor ?? AppColors.surfaceBorder,
          width: 1,
        ),
        boxShadow: hasGlow ? AppColors.primaryGlow : AppColors.cardShadow,
      ),
      child: child,
    );

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(borderRadius),
          child: content,
        ),
      );
    }

    return content;
  }
}
