import 'package:flutter/material.dart';

/// Reusable text field for authentication forms with consistent styling.
class AuthTextField extends StatelessWidget {
  const AuthTextField({
    required this.controller,
    required this.hintText,
    required this.prefixIcon,
    this.obscureText = false,
    this.validator,
    this.onChanged,
    this.textInputAction = TextInputAction.next,
    this.keyboardType = TextInputType.text,
    this.suffixIcon,
    this.autofillHints,
    this.enabled = true,
    super.key,
  });

  final TextEditingController controller;
  final String hintText;
  final IconData prefixIcon;
  final bool obscureText;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final TextInputAction textInputAction;
  final TextInputType keyboardType;
  final Widget? suffixIcon;
  final Iterable<String>? autofillHints;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      validator: validator,
      onChanged: onChanged,
      textInputAction: textInputAction,
      keyboardType: keyboardType,
      enabled: enabled,
      autofillHints: autofillHints,
      style: Theme.of(context).textTheme.bodyLarge,
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: Icon(prefixIcon),
        suffixIcon: suffixIcon,
      ),
    );
  }
}
