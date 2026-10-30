import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:plough/plough.dart' as gv;
import 'adaptinglayout.dart';
import 'theme/app_theme.dart';

class CustomBehavior extends gv.GraphViewDefaultBehavior {
  const CustomBehavior();

  @override
  gv.GraphNodeViewBehavior createNodeViewBehavior() {
    return gv.GraphNodeViewBehavior.defaultBehavior(
      nodeRendererBuilder: (context, graph, node, child) {
        final diameter = nodeDiameterFor(graph.nodes.length);

        final highlighted = node.properties['highlighted'] == true;

        // Every node is black, like the rest of the app; a profile picture
        // shows inside the black ring.
        const ringColor = MapColors.node;

        final avatar = NetworkAvatar(
          diameter: diameter,
          image: node.properties['image'] as String?,
          initials: node.properties['initials'] as String? ?? '?',
          ringColor: ringColor,
          highlighted: highlighted,
          gapColor: MapColors.canvas,
        );

        // The default renderer only supplies the hit area and selection
        // state; the avatar draws everything visible.
        return gv.GraphDefaultNodeRenderer(
          node: node,
          style: gv.GraphDefaultNodeRendererStyle(
            shape: gv.GraphDefaultNodeRendererShape.circle,
            height: diameter,
            width: diameter,
            color: Colors.transparent,
            borderWidth: 0,
            borderColor: Colors.transparent,
            selectedBorderColor: ringColor.withValues(alpha: 0.3),
            padding: EdgeInsets.zero,
          ),
          child: _MapNode(
            diameter: diameter,
            name: node.properties['viewer'] == true
                ? 'You'
                : node.properties['label'] as String? ?? '',
            highlighted: highlighted,
            // Tapping a node selects it, which shows the name on phones
            // where there's no hover.
            selected: node.isSelected,
            // Path nodes shimmer; otherwise your own node breathes so it's
            // easy to find.
            avatar: highlighted || node.properties['viewer'] == true
                ? PulsingGlow(
                    color: ringColor.withValues(alpha: 0.45),
                    diameter: diameter,
                    forever: highlighted,
                    child: avatar,
                  )
                : avatar,
          ),
        );
      },
    );
  }

  @override
  gv.GraphLinkViewBehavior createLinkViewBehavior() {
    return gv.GraphLinkViewBehavior(
      builder:
          (context, graph, link, sourceView, targetView, routing, geometry, _) {
            // A found path is a bold black line with a shimmer running along.
            if (link.properties['highlighted'] == true) {
              return ShimmerLink(
                length: geometry.connectionPoints.distance,
                thickness: 20,
              );
            }
            final weight = (link.properties['weight'] as num? ?? 2).toDouble();
            // Grey lines so the black nodes stand out; private stays purple
            // to match the Private toggle.
            final color = link.properties['color'] == AppColors.private
                ? MapColors.privateLink
                : MapColors.link;

            return gv.GraphDefaultLinkRenderer(
              link: link,
              sourceView: sourceView,
              targetView: targetView,
              routing: routing,
              geometry: geometry,
              thickness: 20,
              // weight is 2-10 (more transactions = thicker); scale it down so
              // busy pairs stand out without lines dwarfing the small nodes.
              lineWidth: 1.2 + weight * 0.3,
              color: color.withValues(alpha: 0.6 + weight * 0.04),
            );
          },
    );
  }
}

/// A round profile picture with a colored ring and a glossy highlight.
/// Shows [image] (an asset path or an http(s) URL) when there is one,
/// otherwise the person's [initials].
class NetworkAvatar extends StatelessWidget {
  const NetworkAvatar({
    super.key,
    required this.diameter,
    required this.initials,
    required this.ringColor,
    this.image,
    this.highlighted = false,
    this.gapColor = Colors.white,
    this.faceColor,
  });

  final double diameter;
  final String? image;
  final String initials;
  final Color ringColor;
  final bool highlighted;

  /// The thin gap between the ring and the picture; matches the background.
  final Color gapColor;

  /// Background behind the initials; defaults to [ringColor].
  final Color? faceColor;

  @override
  Widget build(BuildContext context) {
    final ring = diameter * (highlighted ? 0.09 : 0.065);

    return Container(
      width: diameter,
      height: diameter,
      padding: EdgeInsets.all(ring),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ringColor,
        // A soft drop shadow, like the app's cards, so nodes sit above the
        // white map.
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: highlighted ? 0.3 : 0.18),
            blurRadius: diameter * (highlighted ? 0.4 : 0.22),
            offset: Offset(0, diameter * 0.06),
          ),
        ],
      ),
      child: Container(
        // Thin white gap between the ring and the picture.
        padding: EdgeInsets.all(diameter * 0.025),
        decoration: BoxDecoration(shape: BoxShape.circle, color: gapColor),
        // No gloss on top, so a profile picture shows in its own colours.
        child: ClipOval(child: _face(faceColor ?? ringColor)),
      ),
    );
  }

  Widget _face(Color face) {
    Widget initialsFace() => ColoredBox(
      color: face,
      child: Center(
        child: Text(
          initials,
          style: GoogleFonts.spaceGrotesk(
            fontSize: diameter * 0.3,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            height: 1,
          ),
        ),
      ),
    );

    final source = image;
    if (source == null || source.isEmpty) return initialsFace();
    Widget onError(BuildContext context, Object error, StackTrace? stack) =>
        initialsFace();
    return source.startsWith('http')
        ? Image.network(source, fit: BoxFit.cover, errorBuilder: onError)
        : Image.asset(source, fit: BoxFit.cover, errorBuilder: onError);
  }
}

/// A node's avatar with its name, which hangs below without changing the
/// node's size (so the layout and tap area stay the same). The name only
/// shows while the node is hovered or selected.
class _MapNode extends StatefulWidget {
  const _MapNode({
    required this.diameter,
    required this.name,
    required this.highlighted,
    required this.selected,
    required this.avatar,
  });

  final double diameter;
  final String name;
  final bool highlighted;
  final bool selected;
  final Widget avatar;

  @override
  State<_MapNode> createState() => _MapNodeState();
}

class _MapNodeState extends State<_MapNode> {
  bool _hovered = false;

  void _hover(bool value) {
    if (value != _hovered) setState(() => _hovered = value);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _hover(true),
      onExit: (_) => _hover(false),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          widget.avatar,
          Positioned(
            top: widget.diameter + 3,
            left: -widget.diameter,
            right: -widget.diameter,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: widget.selected || _hovered ? 1 : 0,
                duration: const Duration(milliseconds: 150),
                child: Text(
                  widget.name,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    height: 1,
                    color: widget.highlighted
                        ? MapColors.node
                        : MapColors.node.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Colours for the network map: black on white, like the rest of the app.
abstract final class MapColors {
  static const canvas = AppColors.surface;
  static const node = AppColors.textPrimary;
  static const link = Color(0xFFB4B4B4);
  static const pathLink = AppColors.textPrimary;
  static const privateLink = AppColors.private;
}

/// A soft halo that slowly swells and fades around [child], drawn outside
/// the node so the layout is unchanged.
class PulsingGlow extends StatefulWidget {
  const PulsingGlow({
    super.key,
    required this.color,
    required this.diameter,
    required this.child,
    this.forever = false,
  });

  final Color color;
  final double diameter;
  final Widget child;

  /// Keep shimmering instead of resting after a few breaths.
  final bool forever;

  @override
  State<PulsingGlow> createState() => _PulsingGlowState();
}

class _PulsingGlowState extends State<PulsingGlow>
    with SingleTickerProviderStateMixin {
  // A few breaths when the map appears, then it rests on a steady glow.
  // Path nodes keep going, faster, as a shimmer.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.forever ? 1100 : 1800),
  )..repeat(reverse: true, count: widget.forever ? null : 6);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      child: widget.child,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_pulse.value);
        return DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(
                  alpha: widget.color.a * (0.25 + 0.35 * t),
                ),
                blurRadius: widget.diameter * (0.35 + 0.45 * t),
                spreadRadius: widget.diameter * (0.02 + 0.12 * t),
              ),
            ],
          ),
          child: child,
        );
      },
    );
  }
}

/// A link on a found path: a bold black line with a soft shadow and a light
/// shimmer that keeps sweeping along it. Drawn in the same local space as
/// plough's default renderer (a horizontal line [length] long, centred in a
/// strip [thickness] tall).
class ShimmerLink extends StatefulWidget {
  const ShimmerLink({super.key, required this.length, required this.thickness});

  final double length;
  final double thickness;

  @override
  State<ShimmerLink> createState() => _ShimmerLinkState();
}

class _ShimmerLinkState extends State<ShimmerLink>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _ShimmerLinkPainter(
          length: widget.length,
          thickness: widget.thickness,
          sweep: _sweep,
        ),
      ),
    );
  }
}

class _ShimmerLinkPainter extends CustomPainter {
  _ShimmerLinkPainter({
    required this.length,
    required this.thickness,
    required this.sweep,
  }) : super(repaint: sweep);

  final double length;
  final double thickness;
  final Animation<double> sweep;

  @override
  void paint(Canvas canvas, Size size) {
    final y = thickness / 2;
    final start = Offset(0, y);
    final end = Offset(length, y);

    canvas.drawLine(
      start,
      end,
      Paint()
        ..color = MapColors.pathLink.withValues(alpha: 0.14)
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawLine(
      start,
      end,
      Paint()
        ..color = MapColors.pathLink
        ..strokeWidth = 3.2
        ..strokeCap = StrokeCap.round,
    );

    // A light band, a third of the link long, sliding from end to end.
    final band = length / 3;
    final x = -band + (length + band) * sweep.value;
    canvas.drawLine(
      Offset(x.clamp(0, length), y),
      Offset((x + band).clamp(0, length), y),
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.9),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromLTWH(x, 0, band, thickness))
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.8),
    );
  }

  @override
  bool shouldRepaint(_ShimmerLinkPainter oldDelegate) =>
      oldDelegate.length != length || oldDelegate.thickness != thickness;
}
