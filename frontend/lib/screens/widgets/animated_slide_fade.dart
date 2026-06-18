// lib/widgets/animated_slide_fade.dart
import 'package:flutter/material.dart';

/// A reusable widget that combines a SlideTransition + FadeTransition
/// driven by a single AnimationController and an Interval.
///
/// Usage:
/// AnimatedSlideFade(
///   controller: _controller,
///   beginOffset: const Offset(0, 0.5),
///   startInterval: 0.2,
///   endInterval: 0.6,
///   child: YourWidget(),
/// )
class AnimatedSlideFade extends StatelessWidget {
  final AnimationController controller;
  final Offset beginOffset;
  final double startInterval;
  final double endInterval;
  final Widget child;

  const AnimatedSlideFade({
    Key? key,
    required this.controller,
    required this.beginOffset,
    required this.startInterval,
    required this.endInterval,
    required this.child,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final Animation<double> fade = CurvedAnimation(
      parent: controller,
      curve: Interval(startInterval, endInterval, curve: Curves.easeIn),
    );

    final Animation<Offset> slide = Tween<Offset>(
      begin: beginOffset,
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: controller,
        curve: Interval(startInterval, endInterval, curve: Curves.easeOut),
      ),
    );

    return FadeTransition(
      opacity: fade,
      child: SlideTransition(
        position: slide,
        child: child,
      ),
    );
  }
}
