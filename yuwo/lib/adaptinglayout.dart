import 'package:flutter/material.dart';
import 'package:plough/plough.dart' as gv;

gv.GraphLayoutStrategy adaptiveLayoutFor(int nodeCount) {
  final diameter = nodeDiameterFor(nodeCount);

  // Minimum center-to-center distance for two circles of this diameter to avoid touching
  final minSpacing = diameter * 2.2;

  // making Coulomb repulsion strong enough to win against the springs pulling linked nodes together 
  final coulombConstant = diameter * diameter * 6;

  if (nodeCount <= 3) {
    return gv.GraphForceDirectedLayoutStrategy(
      springLength: minSpacing + 40,
      springConstant: 0.12,
      damping: 0.85,
      coulombConstant: coulombConstant,
      maxIterations: 600,
      tolerance: 0.5,
      padding: const EdgeInsets.all(60),
    );
  }
  if (nodeCount <= 8) {
    return gv.GraphForceDirectedLayoutStrategy(
      springLength: minSpacing + 60,
      springConstant: 0.1,
      damping: 0.85,
      coulombConstant: coulombConstant,
      maxIterations: 900,
      tolerance: 0.5,
      padding: const EdgeInsets.all(80),
    );
  }
  if (nodeCount <= 20) {
    return gv.GraphForceDirectedLayoutStrategy(
      springLength: minSpacing + 30,
      springConstant: 0.08,
      damping: 0.88,
      coulombConstant: coulombConstant,
      maxIterations: 1300,
      tolerance: 0.4,
      padding: const EdgeInsets.all(60),
    );
  }
  return gv.GraphForceDirectedLayoutStrategy(
    springLength: minSpacing,
    springConstant: 0.06,
    damping: 0.9,
    coulombConstant: coulombConstant,
    maxIterations: 1800,
    tolerance: 0.3,
    padding: const EdgeInsets.all(40),
  );
}

/// Node diameter shrinks a bit as the graph gets busier, so dozens of nodes
/// don't turn into an overlapping wall of avatars.
double nodeDiameterFor(int nodeCount) {
  if (nodeCount <= 6) return 100;
  if (nodeCount <= 15) return 76;
  if (nodeCount <= 30) return 56;
  return 40;
}