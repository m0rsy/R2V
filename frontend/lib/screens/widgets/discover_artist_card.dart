import 'package:flutter/material.dart';

class DiscoverArtistCard extends StatefulWidget {
  final String image;
  final String avatar;
  final String name;
  final String role;
  final String hourlyRate;
  final double rating;

  const DiscoverArtistCard({
    super.key,
    required this.image,
    required this.avatar,
    required this.name,
    required this.role,
    required this.hourlyRate,
    required this.rating,
  });

  @override
  State<DiscoverArtistCard> createState() => _DiscoverArtistCardState();
}

class _DiscoverArtistCardState extends State<DiscoverArtistCard> {
  bool isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => isHovered = true),
      onExit: (_) => setState(() => isHovered = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1825), // Dark sleek card
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isHovered
                ? const Color(0xFFA855F7).withOpacity(0.5)
                : Colors.white.withOpacity(0.05),
          ),
          boxShadow: isHovered
              ? [
                  BoxShadow(
                    color: const Color(0xFFA855F7).withOpacity(0.1),
                    blurRadius: 16,
                    spreadRadius: 1,
                  )
                ]
              : [],
        ),
        child: Column(
          children: [
            // Square Top Image
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
                child: Image.network(
                  widget.image,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            // Bottom Info
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          widget.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        widget.hourlyRate,
                        style: const TextStyle(
                          color: Color(0xFFC084FC), // Lighter Purple
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 8,
                              backgroundImage: NetworkImage(widget.avatar),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                widget.role,
                                style: const TextStyle(
                                  color: Color(0xFF9CA3AF),
                                  fontSize: 11,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          const Icon(Icons.star_rounded,
                              color: Color(0xFFF43F5E), size: 14),
                          const SizedBox(width: 4),
                          Text(
                            "${widget.rating}",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
