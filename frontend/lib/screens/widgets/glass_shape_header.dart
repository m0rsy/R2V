import 'dart:ui';
import 'package:flutter/material.dart';

/// Glassy circular container that shows a 3D shape inside it.
/// This is the "floating" header you chose (Option B).
class GlassShapeHeader extends StatelessWidget {
  final String asset;
  final double size;
  final double padding;

  const GlassShapeHeader({
    Key? key,
    required this.asset,
    this.size = 90,
    this.padding = 12,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: EdgeInsets.all(padding),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.4),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withOpacity(0.7),
                width: 1.4,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Image.asset(
              asset,
              width: size,
              height: size,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}
