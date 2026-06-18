import 'package:flutter/material.dart';

class HoverWidget extends StatefulWidget {
  final Widget child;
  final double scale;
  final bool glow;

  const HoverWidget({
    super.key,
    required this.child,
    this.scale = 1.05,
    this.glow = false,
  });

  @override
  State<HoverWidget> createState() => _HoverWidgetState();
}

class _HoverWidgetState extends State<HoverWidget> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        transform: Matrix4.identity()
          ..scale(_hovering ? widget.scale : 1.0),
        decoration: BoxDecoration(
          boxShadow: widget.glow && _hovering
              ? [
                  BoxShadow(
                    color: const Color(0xFFBC70FF).withOpacity(0.4),
                    blurRadius: 25,
                    spreadRadius: 2,
                  ),
                ]
              : [],
        ),
        child: widget.child,
      ),
    );
  }
}
