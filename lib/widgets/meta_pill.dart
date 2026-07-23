import 'package:flutter/material.dart';

/// An outlined content-rating badge (e.g. "R", "TV-MA"). Styled for the detail
/// header over a backdrop: white text in a white-bordered box.
class CertBadge extends StatelessWidget {
  final String text;
  const CertBadge({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
      ),
      child: Text(text,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            letterSpacing: 0.5,
          )),
    );
  }
}

/// "1h 42m" / "42m" from a minute count.
String fmtRuntime(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return h > 0 ? '${h}h ${m}m' : '${m}m';
}
