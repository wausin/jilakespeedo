import 'package:flutter/material.dart';

/// Small breathing pill shown at the top-right of the screen when a new
/// build is deployed. Tap to reload the app.
class UpdateBadge extends StatefulWidget {
  const UpdateBadge({super.key, required this.onTap});

  /// Marker used by tests.
  static const Key badgeKey = Key('update-badge');

  final VoidCallback onTap;

  @override
  State<UpdateBadge> createState() => _UpdateBadgeState();
}

class _UpdateBadgeState extends State<UpdateBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.error;
    return FadeTransition(
      opacity: Tween(begin: 0.45, end: 1.0).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(14),
        elevation: 4,
        child: InkWell(
          key: UpdateBadge.badgeKey,
          borderRadius: BorderRadius.circular(14),
          onTap: widget.onTap,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.system_update_alt, size: 13, color: Colors.white),
                SizedBox(width: 4),
                Text(
                  'Update',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
