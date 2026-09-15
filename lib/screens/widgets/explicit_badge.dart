import 'package:flutter/material.dart';

class ExplicitBadge extends StatelessWidget {
  final Color? color;

  const ExplicitBadge({super.key, this.color});

  @override
  Widget build(BuildContext context) {
    final textColor = color ?? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7);
    return Container(
      margin: const EdgeInsets.only(right: 6.0),
      padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 1.0),
      decoration: BoxDecoration(
        border: Border.all(color: textColor, width: 1.0),
        borderRadius: BorderRadius.circular(3.0),
      ),
      child: Text(
        'E',
        style: TextStyle(
          fontSize: 10.0,
          fontWeight: FontWeight.w700,
          color: textColor,
          height: 1.1,
        ),
      ),
    );
  }
}

