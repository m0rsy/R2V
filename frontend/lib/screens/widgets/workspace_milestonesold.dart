import 'package:flutter/material.dart';

class WorkspaceMilestones extends StatelessWidget {
  const WorkspaceMilestones({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0B0A10),
      child: Column(
        children: [
          // Scrollable Timeline
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Launch Card
                  Container(
                    height: 200,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFF13111C),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withOpacity(0.08)),
                    ),
                    child: Stack(
                      children: [
                        // Abstract Sphere Gradient Placeholder
                        Center(
                          child: Container(
                            width: 140,
                            height: 140,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  Colors.white.withOpacity(0.15),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFA855F7).withOpacity(0.2),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: const Color(0xFFA855F7)),
                                ),
                                child: const Icon(Icons.play_arrow_rounded, color: Color(0xFFA855F7), size: 28),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                "LAUNCH REAL-TIME PREVIEW",
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.0,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                "Inspect materials & geometry live",
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  color: Color(0xFF9CA3AF),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Badge
                        Positioned(
                          bottom: 12,
                          right: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.4),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              "RENDER ENGINE: EVEE 4.1",
                              style: TextStyle(
                                fontFamily: 'Inter',
                                color: Colors.white70,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Upload Asset Action
                  Container(
                    width: double.infinity,
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF9333EA), Color(0xFFC084FC)],
                      ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF9333EA).withOpacity(0.2),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: () {},
                        child: const Center(
                          child: Text(
                            "Upload Asset",
                            style: TextStyle(
                              fontFamily: 'Inter',
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 48),

                  // Milestones Header
                  const Text(
                    "Project Milestones",
                    style: TextStyle(
                      fontFamily: 'Inter',
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Timeline Stepper Components
                  _buildStepperItem(
                    title: "Concept & Blockout",
                    description: "Basic silhouettes and functional mechanics established.",
                    status: "APPROVED",
                    icon: Icons.check,
                    isCompleted: true,
                  ),
                  _buildStepperLine(isCompleted: true),
                  _buildStepperItem(
                    title: "High-Poly Modeling",
                    description: "Detailing structural components and beveling edges for realism.",
                    status: "IN PROGRESS",
                    icon: Icons.circle,
                    isCurrent: true,
                  ),
                  _buildStepperLine(isCompleted: false),
                  _buildStepperItem(
                    title: "PBR Texturing",
                    description: "4K Substance Painter pass with procedural wear.",
                    icon: Icons.texture,
                  ),
                  _buildStepperLine(isCompleted: false),
                  _buildStepperItem(
                    title: "Final Render & Handover",
                    description: "Cinematic sequence and source file delivery.",
                    icon: Icons.camera_alt_outlined,
                  ),
                ],
              ),
            ),
          ),

          // Sticky Bottom Action Panel
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF15131D),
              border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
            ),
            child: Column(
              children: [
                const Text(
                  "MANAGEMENT CONTROLS",
                  style: TextStyle(
                    fontFamily: 'Inter',
                    color: Color(0xFF9CA3AF),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.refresh, color: Colors.white, size: 16),
                        label: const Text(
                          "Request Revision",
                          style: TextStyle(
                            fontFamily: 'Inter',
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: Colors.white.withOpacity(0.05),
                          side: BorderSide(color: Colors.white.withOpacity(0.1)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.check_circle_outline, color: Colors.white, size: 16),
                        label: const Text(
                          "Approve Milestone",
                          style: TextStyle(
                            fontFamily: 'Inter',
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: const Color(0xFFA855F7),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepperItem({
    required String title,
    required String description,
    String? status,
    required IconData icon,
    bool isCompleted = false,
    bool isCurrent = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Stepper Status Icon
        Column(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isCurrent ? const Color(0xFFA855F7) : (isCompleted ? const Color(0xFFA855F7).withOpacity(0.5) : Colors.white.withOpacity(0.1)),
                  width: isCurrent ? 2 : 1,
                ),
                color: isCompleted ? Colors.transparent : Colors.transparent,
              ),
              child: Center(
                child: Icon(
                  icon,
                  color: isCurrent || isCompleted ? const Color(0xFFA855F7) : const Color(0xFF4B5563),
                  size: isCurrent ? 12 : 16,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(width: 16),

        // Text & Content Area
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      color: (isCurrent || isCompleted) ? Colors.white : const Color(0xFF6B7280),
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (status != null)
                    Text(
                      status,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        color: isCurrent ? const Color(0xFFA855F7) : const Color(0xFFA855F7).withOpacity(0.7),
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                description,
                style: TextStyle(
                  fontFamily: 'Inter',
                  color: (isCurrent || isCompleted) ? const Color(0xFF9CA3AF) : const Color(0xFF4B5563),
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  height: 1.4,
                ),
              ),
              if (isCurrent) ...[
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    side: BorderSide(color: Colors.white.withOpacity(0.2)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  child: const Text(
                    "Submit for Review",
                    style: TextStyle(
                      fontFamily: 'Inter',
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStepperLine({required bool isCompleted}) {
    return Container(
      margin: const EdgeInsets.only(left: 17, top: 8, bottom: 8),
      width: 2,
      height: 30,
      color: isCompleted ? const Color(0xFFA855F7).withOpacity(0.5) : Colors.white.withOpacity(0.05),
    );
  }
}
