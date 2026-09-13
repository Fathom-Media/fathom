import 'dart:ui' show DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';

/// Which way the crease runs across the screen.
enum FoldAxis {
  /// A horizontal crease: the screen is split into a top and a bottom half.
  horizontal,

  /// A vertical crease: the screen is split into a left and a right half.
  vertical,
}

/// What the device is telling us about its fold, measured on a Pixel-class
/// book foldable (2026-09-12): the crease is reported as a zero-thickness line
/// (`[0,426,883,426]`), so nothing is hidden behind it, and both `flat` and
/// `halfOpened` postures arrive in either orientation.
///
/// It can also disappear entirely while the inner screen is still open, so
/// every caller has to treat "no fold" as the normal case and fall back to the
/// ordinary layout. Read it with [FoldInfo.of], which returns null on phones,
/// tablets, desktop, TV, and any foldable that reports nothing.
class FoldInfo {
  const FoldInfo({
    required this.axis,
    required this.position,
    required this.halfOpened,
    required this.thickness,
  });

  final FoldAxis axis;

  /// Where the crease sits, in logical pixels: a y for a horizontal crease, an
  /// x for a vertical one.
  final double position;

  /// True when the device is bent rather than flat, which is the signal for
  /// tabletop (horizontal) and book (vertical) layouts. A flat fold is worth
  /// avoiding for pane splits but is not a posture to design around.
  final bool halfOpened;

  /// How many logical pixels the crease occupies. Zero on a bending fold; some
  /// devices report a real gap, and content must then clear it.
  final double thickness;

  /// The device is half-folded with the crease across the middle: the top half
  /// faces you like a screen and the bottom half lies flat like a keyboard.
  bool get isTabletop => halfOpened && axis == FoldAxis.horizontal;

  /// The device is half-folded like a book, a page either side of the crease.
  bool get isBook => halfOpened && axis == FoldAxis.vertical;

  /// The fold as reported for [context], or null when there isn't one.
  ///
  /// Only a fold that actually crosses the window counts: a feature that sits
  /// off to one side (a cutout, or a fold in a window occupying half the
  /// screen) would give a split nobody asked for.
  static FoldInfo? of(BuildContext context) {
    final mq = MediaQuery.of(context);
    for (final f in mq.displayFeatures) {
      if (f.type != DisplayFeatureType.fold &&
          f.type != DisplayFeatureType.hinge) {
        continue;
      }
      final b = f.bounds;
      final halfOpened = f.state == DisplayFeatureState.postureHalfOpened;
      if (b.width >= mq.size.width - 1 && b.height < b.width) {
        if (b.center.dy <= 0 || b.center.dy >= mq.size.height) continue;
        return FoldInfo(
          axis: FoldAxis.horizontal,
          position: b.center.dy,
          halfOpened: halfOpened,
          thickness: b.height,
        );
      }
      if (b.height >= mq.size.height - 1 && b.width < b.height) {
        if (b.center.dx <= 0 || b.center.dx >= mq.size.width) continue;
        return FoldInfo(
          axis: FoldAxis.vertical,
          position: b.center.dx,
          halfOpened: halfOpened,
          thickness: b.width,
        );
      }
    }
    return null;
  }
}
