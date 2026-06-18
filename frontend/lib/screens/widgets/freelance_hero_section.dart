import 'package:flutter/material.dart';

class FreelanceHeroSection extends StatelessWidget {
  const FreelanceHeroSection({super.key});

  @override
  Widget build(BuildContext context) {
    final filters = [
      "Rigging",
      "Texturing",
      "Animation",
      "Environment",
      "Characters",
      "Hourly Rate"
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 50),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Headline
          RichText(
            text: const TextSpan(
              style: TextStyle(
                fontSize: 56,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                height: 1.1,
                fontFamily: 'Inter',
              ),
              children: [
                TextSpan(text: "Find the "),
                TextSpan(
                  text: "Architects",
                  style: TextStyle(color: Color(0xFFA855F7)), // Neon Purple
                ),
                TextSpan(text: " of\nthe Metaverse"),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Subtitle
          const Text(
            "Connect with world-class 3D specialists for high-fidelity assets,\nimmersive environments, and cinematic animations.",
            style: TextStyle(
              fontSize: 18,
              color: Color(0xFF9CA3AF), // Light Gray
              height: 1.5,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 48),

          // Search Bar
          Container(
            height: 64,
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 800),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05), // premium glass wash
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: Colors.white.withOpacity(0.10)),
            ),
            padding: const EdgeInsets.only(left: 20, right: 8),
            child: Row(
              children: [
                const Icon(Icons.search, color: Color(0xFF9CA3AF), size: 24),
                const SizedBox(width: 16),
                const Expanded(
                  child: TextField(
                    style: TextStyle(color: Colors.white, fontSize: 16),
                    decoration: InputDecoration(
                      hintText: "Search for artists, specialties, or styles...",
                      hintStyle: TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 16,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
                Container(
                  width: 1,
                  height: 32,
                  color: Colors.white.withOpacity(0.1),
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                ),
                // Advanced Filters
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () {},
                    child: const Row(
                      children: [
                        Icon(Icons.tune, color: Color(0xFF9CA3AF), size: 20),
                        SizedBox(width: 8),
                        Text(
                          "Advanced Filters",
                          style: TextStyle(
                            color: Color(0xFF9CA3AF),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 24),
                // Discover Talents Button
                Container(
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF9333EA), Color(0xFFC084FC)],
                    ),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: () {},
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 24),
                        child: Center(
                          child: Text(
                            "Discover Talents",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // Filters Row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: filters.map((filter) {
                return Padding(
                  padding: const EdgeInsets.only(right: 12.0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.15),
                      ),
                    ),
                    child: Text(
                      filter,
                      style: const TextStyle(
                        color: Color(0xFFD1D5DB),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
