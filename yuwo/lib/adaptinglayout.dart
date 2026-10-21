import 'package:flutter/material.dart';
import 'package:plough/plough.dart' as gv;

/// Picks force-directed physics based on how many nodes are in the graph,
/// so small graphs stay tight and readable while larger ones get more room
/// to spread out. Spacing is derived from the actual rendered node size
/// (see [nodeDiameterFor]) rather than a flat constant, which is what keeps
/// nodes from sitting on top of each other as the node count changes.
///
/// Force-directed layout is a physics simulation, not a hard constraint —
/// it can't *guarantee* zero overlap the way a strict collision-avoidance
/// pass would, especially in a very densely interlinked graph. What this
/// does guarantee is that the repulsion is always sized correctly relative
/// to how big the nodes are actually drawn, which is the part that was
/// missing before and is what causes overlap in practice.
gv.GraphLayoutStrategy adaptiveLayoutFor(int nodeCount) {
  final diameter = nodeDiameterFor(nodeCount);

  // Minimum center-to-center distance for two circles of this diameter to
  // have a clear gap between them, not just avoid touching.
  final minSpacing = diameter * 2.2;

  // Coulomb repulsion strong enough, at that spacing, to actually win
  // against the springs pulling linked nodes together — scaled off the
  // node's rendered area so bigger nodes push harder.
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