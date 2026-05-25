import 'package:flutter/material.dart';

class MapEtaDistanceCard extends StatefulWidget {
  final String etaText;
  final String distanceText;
  final String? statusText;
  final VoidCallback? onTap;
  final bool iconOnlyCollapsed;

  const MapEtaDistanceCard({
    super.key,
    required this.etaText,
    required this.distanceText,
    this.statusText,
    this.onTap,
    this.iconOnlyCollapsed = true,
  });

  @override
  State<MapEtaDistanceCard> createState() => _MapEtaDistanceCardState();
}

class _MapEtaDistanceCardState extends State<MapEtaDistanceCard>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;

  void _toggle() {
    setState(() => _expanded = !_expanded);
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.etaText.trim();
    final dist = widget.distanceText.trim();
    final status = (widget.statusText ?? '').trim();

    if (title.isEmpty && dist.isEmpty) return const SizedBox.shrink();

    final collapsed = !_expanded && widget.iconOnlyCollapsed;

    return SafeArea(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _toggle,
          borderRadius: BorderRadius.circular(22),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            padding:
                collapsed
                    ? const EdgeInsets.all(10)
                    : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: AnimatedSize(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints:
                    collapsed
                        ? const BoxConstraints.tightFor(width: 42, height: 42)
                        : const BoxConstraints(minWidth: 210, maxWidth: 300),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (collapsed)
                      const Center(
                        child: Icon(
                          Icons.timer_outlined,
                          size: 20,
                          color: Colors.black,
                        ),
                      )
                    else
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (dist.isNotEmpty) ...[
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.06),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Text(
                                dist,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(width: 10),
                          const Icon(
                            Icons.timer_outlined,
                            size: 18,
                            color: Colors.black,
                          ),
                        ],
                      ),
                    if (_expanded) ...[
                      const SizedBox(height: 10),
                      if (status.isNotEmpty)
                        Text(
                          status,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                      if (status.isNotEmpty) const SizedBox(height: 6),
                      Text(
                        'Tap to collapse',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.black.withOpacity(0.55),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
