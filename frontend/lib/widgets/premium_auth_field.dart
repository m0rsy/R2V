import 'dart:ui';

import 'package:flutter/material.dart';

/// Shared premium input used across the R2V auth screens
/// (sign in, sign up, forgot password, set new password).
///
/// Renders exactly ONE clean rounded container per field — the leading icon,
/// the text input and the optional suffix all live inside a single border.
/// The inner [TextField] draws no border/fill of its own ([InputBorder.none]),
/// so there is no "box inside a box".
///
///  * Unfocused: subtle grey/purple border over a very faint dark fill.
///  * Focused:   soft lavender border with a gentle purple glow.
class PremiumAuthField extends StatefulWidget {
  const PremiumAuthField({
    super.key,
    required this.controller,
    required this.icon,
    required this.hint,
    this.obscure = false,
    this.suffix,
    this.keyboardType,
    this.autofillHints,
  });

  final TextEditingController controller;
  final IconData icon;
  final String hint;
  final bool obscure;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;

  @override
  State<PremiumAuthField> createState() => _PremiumAuthFieldState();
}

class _PremiumAuthFieldState extends State<PremiumAuthField> {
  static const Color _accentLavender = Color(0xFFBC70FF);

  final FocusNode _focusNode = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (_focused != _focusNode.hasFocus) {
      setState(() => _focused = _focusNode.hasFocus);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        // Very subtle dark fill — not a second full box.
        color: Colors.white.withOpacity(_focused ? 0.06 : 0.035),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _focused
              ? _accentLavender.withOpacity(0.65)
              : Colors.white.withOpacity(0.12),
          width: _focused ? 1.4 : 1,
        ),
        boxShadow: _focused
            ? [
                BoxShadow(
                  color: _accentLavender.withOpacity(0.22),
                  blurRadius: 16,
                  spreadRadius: 0.5,
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          Icon(
            widget.icon,
            color: _focused
                ? _accentLavender.withOpacity(0.95)
                : Colors.white.withOpacity(0.75),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focusNode,
              obscureText: widget.obscure,
              keyboardType: widget.keyboardType,
              autofillHints: widget.autofillHints,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              cursorColor: _accentLavender,
              decoration: InputDecoration(
                isCollapsed: true,
                contentPadding: EdgeInsets.zero,
                hintText: widget.hint,
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.45)),
                // No inner border/fill at all — the wrapper is the only box.
                filled: false,
                fillColor: Colors.transparent,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
              ),
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
            ),
          ),
          if (widget.suffix != null) widget.suffix!,
        ],
      ),
    );
  }
}

/// Single square OTP/verification digit box matching [PremiumAuthField].
///
/// One border per box (glass blur + subtle fill). The border brightens to
/// lavender while focused. Digit-advance logic stays with the parent via
/// [onChanged]; this widget owns only the visual focus state.
class PremiumOtpBox extends StatefulWidget {
  const PremiumOtpBox({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;

  @override
  State<PremiumOtpBox> createState() => _PremiumOtpBoxState();
}

class _PremiumOtpBoxState extends State<PremiumOtpBox> {
  static const Color _accentLavender = Color(0xFFBC70FF);

  bool _focused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (_focused != widget.focusNode.hasFocus) {
      setState(() => _focused = widget.focusNode.hasFocus);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          width: 58,
          height: 58,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(_focused ? 0.08 : 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _focused
                  ? _accentLavender.withOpacity(0.75)
                  : Colors.white.withOpacity(0.14),
              width: _focused ? 1.6 : 1.2,
            ),
          ),
          child: TextField(
            controller: widget.controller,
            focusNode: widget.focusNode,
            maxLength: 1,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
            cursorColor: _accentLavender,
            decoration: const InputDecoration(
              counterText: "",
              isCollapsed: true,
              contentPadding: EdgeInsets.zero,
              filled: false,
              fillColor: Colors.transparent,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
            ),
            onChanged: widget.onChanged,
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
          ),
        ),
      ),
    );
  }
}
