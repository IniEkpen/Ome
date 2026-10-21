import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:plough/plough.dart' as gv;
import 'adaptinglayout.dart';

//Physics for how node and nodelinks should interactwith one another
gv.GraphLayoutStrategy edgeAvoidingLayoutFor(gv.Graph graph, Size canvasSize) {
  final nodes = graph.nodes.toList();
  final links = graph.links.toList();
  if (nodes.isEmpty) {
    return gv.GraphManualLayoutStrategy(
      nodePositions: const [],
      origin: gv.GraphLayoutPositionOrigin.alignCenter,
    );
  }

  final diameter = nodeDiameterFor(nodes.length);

  // center-to-center minimum for nodes
  final nodeSpacing = diameter * 2.2;

   // gap a line must keep from a node 
  final edgeClearance = diameter / 2 + 24;

  final width = canvasSize.width.isFinite ? canvasSize.width : 800.0;
  final height = canvasSize.height.isFinite ? canvasSize.height : 600.0;

  // fixed seed so I made it so layout is stable across rebuilds
  final rng = math.Random(7); 

  // Seed on a circle so the simulation starts spread out rather than piled
  final positions = <gv.GraphId, Offset>{};
  final center = Offset(width / 2, height / 2);
  final seedRadius = math.max(math.min(width, height) / 2 - diameter, diameter);
  for (var i = 0; i < nodes.length; i++) {
    final angle = (2 * math.pi * i) / nodes.length;
    positions[nodes[i].id] = center +
        Offset(math.cos(angle), math.sin(angle)) * seedRadius +
        Offset(rng.nextDouble() * 4 - 2, rng.nextDouble() * 4 - 2);
  }

  const iterations = 300;
  for (var iter = 0; iter < iterations; iter++) {
    final forces = {for (final n in nodes) n.id: Offset.zero};

    // 1) Node-node repulsion.
    for (var i = 0; i < nodes.length; i++) {
      for (var j = i + 1; j < nodes.length; j++) {
        final a = nodes[i].id;
        final b = nodes[j].id;
        var delta = positions[a]! - positions[b]!;
        var dist = delta.distance;
        if (dist < 0.01) {
          delta = Offset(rng.nextDouble() - 0.5, rng.nextDouble() - 0.5);
          dist = math.max(delta.distance, 0.01);
        }
        if (dist < nodeSpacing) {
          final push = delta / dist * (nodeSpacing - dist) * 0.06;
          forces[a] = forces[a]! + push;
          forces[b] = forces[b]! - push;
        }
      }
    }

    // link springs
    for (final link in links) {
      final a = link.source.id;
      final b = link.target.id;
      final delta = positions[b]! - positions[a]!;
      final dist = math.max(delta.distance, 0.01);
      final stretch = dist - nodeSpacing;
      final pull = delta / dist * stretch * 0.02;
      forces[a] = forces[a]! + pull;
      forces[b] = forces[b]! - pull;
    }

    // keeps lines going across nodes
    for (final link in links) {
      final aId = link.source.id;
      final bId = link.target.id;
      final p1 = positions[aId]!;
      final p2 = positions[bId]!;
      final segment = p2 - p1;
      final segLenSq = segment.distanceSquared;
      if (segLenSq < 0.01) continue;

      for (final node in nodes) {
        if (node.id == aId || node.id == bId) continue;
        final p = positions[node.id]!;
        var t = ((p.dx - p1.dx) * segment.dx + (p.dy - p1.dy) * segment.dy) / segLenSq;
        t = t.clamp(0.0, 1.0);
        final closest = p1 + segment * t;
        var away = p - closest;
        var dist = away.distance;
        if (dist < edgeClearance) {
          if (dist < 0.01) {
            away = Offset(rng.nextDouble() - 0.5, rng.nextDouble() - 0.5);
            dist = math.max(away.distance, 0.01);
          }
          final push = away / dist * (edgeClearance - dist) * 0.5;
          forces[node.id] = forces[node.id]! + push;
        }
      }
    }

    for (final node in nodes) {
      final id = node.id;
      var next = positions[id]! + forces[id]!;
      next = Offset(
        next.dx.clamp(diameter, math.max(width - diameter, diameter)),
        next.dy.clamp(diameter, math.max(height - diameter, diameter)),
      );
      positions[id] = next;
    }
  }

  return gv.GraphManualLayoutStrategy(
    nodePositions: gv.GraphNodeLayoutPosition.fromMap(positions),
    origin: gv.GraphLayoutPositionOrigin.alignCenter,
  );
}