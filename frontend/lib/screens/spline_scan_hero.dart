import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

class SplineScanHeroScreen extends StatelessWidget {
  const SplineScanHeroScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Force dark mode for this specific aesthetic
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 900;

    return Scaffold(
      backgroundColor: const Color(0xFF090514), // Deep dark background
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          // 1. The Deep Radial Gradient (From Image 1)
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.topCenter,
                  radius: 1.5,
                  colors: [
                    Color(0xFF2A1549), // Deep purple glow at the top
                    Color(0xFF090514), // Almost black at the bottom
                  ],
                ),
              ),
            ),
          ),

          // 2. The 3D Polygon Mesh Network (From Image 2)
          // This represents a "3D Scan" or "Point Cloud" perfectly.
          const Positioned.fill(
            child: Opacity(
              opacity: 0.6,
              child: MeshNetworkBackground(),
            ),
          ),

          // 3. Optional: A central interactive 3D model faded in the background
          Positioned(
            bottom: isMobile ? -100 : -200,
            left: 0,
            right: 0,
            height: size.height * 0.7,
            child: Opacity(
              opacity: 0.8,
              child: IgnorePointer(
                // Ignoring pointer so it doesn't block UI clicks, but it still auto-rotates
                child: ModelViewer(
                  src: 'https://modelviewer.dev/shared-assets/models/Astronaut.glb', 
                  autoRotate: true,
                  rotationPerSecond: '15deg',
                  cameraControls: false,
                  disableZoom: true,
                  backgroundColor: Colors.transparent,
                  environmentImage: 'neutral',
                  shadowIntensity: 0,
                ),
              ),
            ),
          ),

          // 4. The Spline-Style Centered Typography (From Image 1 & 2)
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Glassmorphic Preview Box (From Image 2)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white.withOpacity(0.1)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  "Prompt →",
                                  style: TextStyle(color: Color(0xFFBC70FF), fontSize: 14, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  "3D preview in under 60s.",
                                  style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14, fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Spline Bold Headline (From Image 1)
                      Text(
                        "The all-in-one platform\nfor 3D scanning",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: isMobile ? 42 : 68,
                          fontWeight: FontWeight.w900,
                          height: 1.1,
                          letterSpacing: -1.5,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Subtitle
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 600),
                        child: Text(
                          "R2V is a powerful engine to scan, create, and collaborate on interactive, production-ready 3D meshes in real-time.",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: isMobile ? 16 : 20,
                            fontWeight: FontWeight.w500,
                            height: 1.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 40),

                      // CTA Button (Matches Spline exactly)
                      ElevatedButton(
                        onPressed: () {},
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0066FF), // Spline Blue
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        child: const Text(
                          "Get started — it's free  →",
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                      ),
                      
                      const SizedBox(height: 24),
                      const Text(
                        "Press and drag to orbit",
                        style: TextStyle(color: Colors.white38, fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// THE POLYGON MESH BACKGROUND (From Image 2)
// This creates the floating connected dots that perfectly represent 3D scanning
// ============================================================================
class MeshNetworkBackground extends StatefulWidget {
  const MeshNetworkBackground({super.key});

  @override
  State<MeshNetworkBackground> createState() => _MeshNetworkBackgroundState();
}

class _MeshNetworkBackgroundState extends State<MeshNetworkBackground> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final Random _rng = Random();
  late List<_MeshNode> _nodes;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat();
    
    // Generate random nodes
    _nodes = List.generate(40, (index) {
      return _MeshNode(
        x: _rng.nextDouble(),
        y: _rng.nextDouble(),
        vx: (_rng.nextDouble() - 0.5) * 0.002,
        vy: (_rng.nextDouble() - 0.5) * 0.002,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          painter: _MeshPainter(nodes: _nodes),
          size: Size.infinite,
        );
      },
    );
  }
}

class _MeshNode {
  double x, y;
  double vx, vy;
  _MeshNode({required this.x, required this.y, required this.vx, required this.vy});
}

class _MeshPainter extends CustomPainter {
  final List<_MeshNode> nodes;

  _MeshPainter({required this.nodes});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.15)
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..strokeWidth = 1.0;

    // Update positions
    for (var node in nodes) {
      node.x += node.vx;
      node.y += node.vy;

      // Bounce off walls
      if (node.x <= 0 || node.x >= 1) node.vx *= -1;
      if (node.y <= 0 || node.y >= 1) node.vy *= -1;
    }

    // Draw lines and dots
    for (int i = 0; i < nodes.length; i++) {
      final p1 = Offset(nodes[i].x * size.width, nodes[i].y * size.height);
      
      // Draw Dot
      canvas.drawCircle(p1, 2.5, paint);

      // Connect to nearby dots (creates the mesh/constellation effect)
      for (int j = i + 1; j < nodes.length; j++) {
        final p2 = Offset(nodes[j].x * size.width, nodes[j].y * size.height);
        final distance = (p1 - p2).distance;

        // If nodes are close enough, draw a line connecting them
        if (distance < 150) {
          // Fade the line out as it gets further away
          linePaint.color = Colors.white.withOpacity(0.15 * (1 - (distance / 150)));
          canvas.drawLine(p1, p2, linePaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MeshPainter oldDelegate) => true;
}