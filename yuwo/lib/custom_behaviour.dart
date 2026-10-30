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

        final ringColor = highlighted
            ? AppColors.path
            : (node.properties['color'] as Color? ?? Colors.blueGrey);

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
            selectedBorderColor: ringColor.withValues(alpha: 0.5),
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
            // Your own node breathes so it's easy to find.
            avatar: node.properties['viewer'] == true
                ? PulsingGlow(
                    color: ringColor,
                    diameter: diameter,
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
            final highlighted = link.properties['highlighted'] == true;
            final weight = (link.properties['weight'] as num? ?? 2).toDouble();
            // Lines glow against the dark map: path green, private purple,
            // everything else a soft cyan.
            final color = highlighted
                ? MapColors.pathLink
                : link.properties['color'] == AppColors.private
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
              lineWidth: highlighted ? 3.5 : 1.4 + weight * 0.3,
              color: highlighted
                  ? color
                  : color.withValues(alpha: 0.55 + weight * 0.04),
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
  });

  final double diameter;
  final String? image;
  final String initials;
  final Color ringColor;
  final bool highlighted;

  /// The thin gap between the ring and the picture; matches the background.
  final Color gapColor;

  @override
  Widget build(BuildContext context) {
    final ring = diameter * (highlighted ? 0.09 : 0.065);
    final light = Color.lerp(ringColor, Colors.white, 0.35)!;
    final dark = Color.lerp(ringColor, Colors.black, 0.25)!;

    return Container(
      width: diameter,
      height: diameter,
      padding: EdgeInsets.all(ring),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [light, dark],
        ),
        boxShadow: [
          BoxShadow(
            color: ringColor.withValues(alpha: highlighted ? 0.7 : 0.45),
            blurRadius: diameter * (highlighted ? 0.55 : 0.32),
            spreadRadius: diameter * (highlighted ? 0.04 : 0),
          ),
        ],
      ),
      child: Container(
        // Thin white gap between the ring and the picture.
        padding: EdgeInsets.all(diameter * 0.025),
        decoration: BoxDecoration(shape: BoxShape.circle, color: gapColor),
        child: ClipOval(
          child: Stack(
            fit: StackFit.expand,
            children: [
              _face(light, dark),
              // Gloss: a soft specular spot up top and a little shade at
              // the bottom so the avatar reads as a rounded bead.
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(-0.35, -0.65),
                    radius: 0.85,
                    colors: [
                      Color(0x8CFFFFFF),
                      Color(0x1FFFFFFF),
                      Color(0x00FFFFFF),
                    ],
                    stops: [0, 0.4, 0.75],
                  ),
                ),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.center,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0x2E000000)],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _face(Color light, Color dark) {
    Widget initialsFace() => DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [light, dark],
        ),
      ),
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
                        ? MapColors.pathLink
                        : Colors.white.withValues(alpha: 0.8),
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

/// Colours for the dark network map.
abstract final class MapColors {
  static const canvas = Color(0xFF101114);
  static const link = Color(0xFF7DD3FC);
  static const pathLink = Color(0xFF34E3B0);
  static const privateLink = Color(0xFFB79BFF);
}

/// A soft halo that slowly swells and fades around [child], drawn outside
/// the node so the layout is unchanged.
class PulsingGlow extends StatefulWidget {
  const PulsingGlow({
    super.key,
    required this.color,
    required this.diameter,
    required this.child,
  });

  final Color color;
  final double diameter;
  final Widget child;

  @override
  State<PulsingGlow> createState() => _PulsingGlowState();
}

class _PulsingGlowState extends State<PulsingGlow>
    with SingleTickerProviderStateMixin {
  // A few breaths when the map appears, then it rests on a steady glow.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat(reverse: true, count: 6);

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
                color: widget.color.withValues(alpha: 0.25 + 0.35 * t),
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
