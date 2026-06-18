// premium_input.dart
//
// Shared "premium glass" input/search building blocks for R2V.
//
// Goal: one consistent, transparent/glass field style across the whole app so
// no screen needs to hand-roll a dark filled rectangle behind its inputs.
//
//  - premiumInputDecoration() : the canonical glass [InputDecoration]. Use it
//    on any TextField / TextFormField that needs the premium look but keeps its
//    own widget (custom rows, send buttons, etc).
//  - PremiumTextField         : drop-in TextFormField wrapper (validators,
//    controllers, focus nodes, onChanged/onSubmitted all forwarded).
//  - PremiumSearchField       : a ready-made search field (search icon +
//    optional clear button) built on the same decoration.
//  - GlassContainer           : a blurred, subtly-bordered glass panel for
//    wrapping inputs or other content when a true backdrop-blur is wanted.
//
// Style tokens (kept in sync with AppTheme.inputDecorationTheme):
//   fill   : white @ 0.05 (dark)  /  black @ 0.03 (light)   -> transparent glass
//   border : white @ 0.10 (dark)  /  black @ 0.08 (light)
//   focus  : ColorScheme.primary (brand accent)
//   radius : 16

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ── Style tokens ──────────────────────────────────────────────────────

class PremiumInputStyle {
  PremiumInputStyle._();

  static const double radius = 16;

  static Color fill(bool isDark) =>
      isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03);

  static Color border(bool isDark) =>
      isDark ? Colors.white.withOpacity(0.10) : Colors.black.withOpacity(0.08);

  static Color hint(bool isDark) =>
      isDark ? Colors.white.withOpacity(0.45) : Colors.black.withOpacity(0.40);

  static Color text(bool isDark) =>
      isDark ? Colors.white : const Color(0xFF1E293B);

  static Color icon(bool isDark) =>
      isDark ? Colors.white.withOpacity(0.70) : Colors.black54;
}

/// The canonical glass [InputDecoration].
///
/// Pass [context] so the focus color follows the active theme's accent. All
/// other arguments mirror the common [InputDecoration] fields so this can be
/// dropped onto existing widgets without changing their behaviour.
InputDecoration premiumInputDecoration(
  BuildContext context, {
  String? hintText,
  String? labelText,
  Widget? prefixIcon,
  Widget? suffixIcon,
  bool isDense = false,
  bool filled = true,
  EdgeInsetsGeometry? contentPadding,
  double radius = PremiumInputStyle.radius,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final scheme = Theme.of(context).colorScheme;

  OutlineInputBorder side(Color color, [double width = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: BorderSide(color: color, width: width),
      );

  final borderColor = PremiumInputStyle.border(isDark);

  return InputDecoration(
    hintText: hintText,
    labelText: labelText,
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    isDense: isDense,
    filled: filled,
    fillColor: PremiumInputStyle.fill(isDark),
    hintStyle: TextStyle(color: PremiumInputStyle.hint(isDark)),
    labelStyle: TextStyle(color: PremiumInputStyle.hint(isDark)),
    contentPadding: contentPadding ??
        const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: side(borderColor),
    enabledBorder: side(borderColor),
    focusedBorder: side(scheme.primary, 1.6),
    errorBorder: side(scheme.error),
    focusedErrorBorder: side(scheme.error, 1.6),
    disabledBorder: side(borderColor.withOpacity(0.5)),
  );
}

/// A drop-in text field with the premium glass look.
///
/// Forwards the common knobs (controller, focusNode, validator, onChanged,
/// onSubmitted, obscureText, etc.) so it can replace bespoke TextField/
/// TextFormField wrappers without losing functionality.
class PremiumTextField extends StatelessWidget {
  const PremiumTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.hintText,
    this.labelText,
    this.prefixIcon,
    this.suffixIcon,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.enabled = true,
    this.autofocus = false,
    this.autofillHints,
    this.validator,
    this.onChanged,
    this.onFieldSubmitted,
    this.inputFormatters,
    this.textAlign = TextAlign.start,
    this.contentPadding,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? hintText;
  final String? labelText;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final int? maxLines;
  final int? minLines;
  final int? maxLength;
  final bool enabled;
  final bool autofocus;
  final Iterable<String>? autofillHints;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onFieldSubmitted;
  final List<TextInputFormatter>? inputFormatters;
  final TextAlign textAlign;
  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      maxLines: obscureText ? 1 : maxLines,
      minLines: minLines,
      maxLength: maxLength,
      enabled: enabled,
      autofocus: autofocus,
      autofillHints: autofillHints,
      validator: validator,
      onChanged: onChanged,
      onFieldSubmitted: onFieldSubmitted,
      inputFormatters: inputFormatters,
      textAlign: textAlign,
      cursorColor: Theme.of(context).colorScheme.primary,
      style: TextStyle(color: PremiumInputStyle.text(isDark)),
      decoration: premiumInputDecoration(
        context,
        hintText: hintText,
        labelText: labelText,
        prefixIcon: prefixIcon == null
            ? null
            : Icon(prefixIcon, color: PremiumInputStyle.icon(isDark)),
        suffixIcon: suffixIcon,
        contentPadding: contentPadding,
      ),
    );
  }
}

/// A ready-made glass search field with a search icon and optional clear button.
///
/// Manages its own controller when none is supplied. The clear button appears
/// automatically once there is text and resets the field (and notifies
/// [onChanged]) when tapped.
class PremiumSearchField extends StatefulWidget {
  const PremiumSearchField({
    super.key,
    this.controller,
    this.focusNode,
    this.hintText = 'Search',
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.radius = 22,
    this.contentPadding,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final double radius;
  final EdgeInsetsGeometry? contentPadding;

  @override
  State<PremiumSearchField> createState() => _PremiumSearchFieldState();
}

class _PremiumSearchFieldState extends State<PremiumSearchField> {
  TextEditingController? _internal;
  TextEditingController get _controller =>
      widget.controller ?? (_internal ??= TextEditingController());

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChangedInternal);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChangedInternal);
    _internal?.dispose();
    super.dispose();
  }

  void _onChangedInternal() {
    // Rebuild so the clear button shows/hides as the text changes.
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasText = _controller.text.isNotEmpty;

    return TextField(
      controller: _controller,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      textInputAction: TextInputAction.search,
      cursorColor: Theme.of(context).colorScheme.primary,
      style: TextStyle(color: PremiumInputStyle.text(isDark)),
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      decoration: premiumInputDecoration(
        context,
        hintText: widget.hintText,
        radius: widget.radius,
        contentPadding: widget.contentPadding,
        prefixIcon:
            Icon(Icons.search_rounded, color: PremiumInputStyle.icon(isDark)),
        suffixIcon: hasText
            ? IconButton(
                icon: Icon(Icons.close_rounded,
                    color: PremiumInputStyle.icon(isDark), size: 18),
                onPressed: () {
                  _controller.clear();
                  widget.onChanged?.call('');
                  FocusScope.of(context).unfocus();
                },
              )
            : null,
      ),
    );
  }
}

/// A blurred glass panel for wrapping inputs or other content.
///
/// Use when you want a real backdrop blur behind the content. For plain fields
/// prefer [PremiumTextField] / [premiumInputDecoration] which are cheaper.
class GlassContainer extends StatelessWidget {
  const GlassContainer({
    super.key,
    required this.child,
    this.radius = 18,
    this.padding,
    this.blur = 12,
    this.color,
    this.borderColor,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final double blur;
  final Color? color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: color ??
                (isDark
                    ? Colors.white.withOpacity(0.05)
                    : Colors.white.withOpacity(0.70)),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: borderColor ?? PremiumInputStyle.border(isDark),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
