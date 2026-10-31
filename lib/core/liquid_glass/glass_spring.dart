import 'package:flutter/physics.dart';


/// Compose's `spring(dampingRatio, stiffness)` as a Flutter simulation,
/// with Compose's default visibility threshold.
SpringSimulation composeSpring(
  double from,
  double to,
  double velocity, {
  required double dampingRatio,
  required double stiffness,
  double threshold = 0.001,
}) {
  return SpringSimulation(
    SpringDescription.withDampingRatio(
      mass: 1,
      stiffness: stiffness,
      ratio: dampingRatio,
    ),
    from,
    to,
    velocity,
    tolerance: Tolerance(distance: threshold, velocity: threshold),
  );
}
