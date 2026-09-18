import 'package:flutter/material.dart';

/// The app's one busy indicator.
///
/// A bare [CircularProgressIndicator] takes its size from whatever box it
/// lands in and its stroke from the Material default, so loose ones drift:
/// the app had them at four stroke widths and a dozen diameters. This fixes
/// the pair together, with a stroke that stays in proportion to the size.
///
/// Use [AppSpinner.inline] inside buttons, rows and list tiles, and the
/// default (or [AppSpinner.page], which centers it) for a whole view that is
/// still loading.
class AppSpinner extends StatelessWidget {
  const AppSpinner({super.key, this.size = 32, this.color, this.value});

  /// Button- and row-sized, for busy states next to text.
  const AppSpinner.inline({super.key, this.color, this.value}) : size = 18;

  /// The diameter of the spinner, in logical pixels.
  final double size;

  /// Defaults to the theme's progress indicator color.
  final Color? color;

  /// 0..1 for determinate progress; null spins indefinitely.
  final double? value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: size <= 20 ? 2 : (size <= 28 ? 2.5 : 3),
        color: color,
        value: value,
      ),
    );
  }
}

/// A centered [AppSpinner], for a view that has nothing to show yet.
class PageSpinner extends StatelessWidget {
  const PageSpinner({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) =>
      Center(child: AppSpinner(color: color));
}
