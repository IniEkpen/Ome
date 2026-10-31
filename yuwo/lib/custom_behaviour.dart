
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
      nodeRendererBuilder: (
        context,
        graph,
        node,
        child,
      ) {
        final diameter =
            nodeDiameterFor(graph.nodes.length);

        final highlighted =
            node.properties['highlighted'] == true;

        final ringColor = highlighted
            ? AppColors.path
            : (node.properties['color'] as Color? ??
                Colors.blueGrey);

        // The default renderer only supplies the hit area and selection
        // state; the avatar draws everything visible.
        return gv.GraphDefaultNodeRenderer(
          node: node,
          style: gv.GraphDefaultNodeRendererStyle(
            shape:
                gv.GraphDefaultNodeRendererShape.circle,
            height: diameter,
            width: diameter,
            color: Colors.transparent,
            borderWidth: 0,
            borderColor: Colors.transparent,
            selectedBorderColor:
                ringColor.withValues(alpha: 0.5),
            padding: EdgeInsets.zero,
          ),
          child: NetworkAvatar(
            diameter: diameter,
            image: node.properties['image'] as String?,
            initials: node.properties['initials'] as String? ?? '?',
            ringColor: ringColor,
            highlighted: highlighted,
          ),
        );
      },
    );
  }

  @override
  gv.GraphLinkViewBehavior createLinkViewBehavior() {
    return gv.GraphLinkViewBehavior(
      builder: (
        context,
        graph,
        link,
        sourceView,
        targetView,
        routing,
        geometry,
        _,
      ) {
        final highlighted = link.properties['highlighted'] == true;
        final color = link.properties['color'] as Color? ?? Colors.blueGrey;
        final weight = (link.properties['weight'] as num? ?? 2).toDouble();

        return gv.GraphDefaultLinkRenderer(
          link: link,
          sourceView: sourceView,
          targetView: targetView,
          routing: routing,
          geometry: geometry,
          thickness: 20,
          // weight is 2-10 (more transactions = thicker); scale it down so
          // busy pairs stand out without lines dwarfing the small nodes.
          lineWidth: highlighted ? 3 : 1 + weight * 0.25,
          color: highlighted ? color : color.withValues(alpha: 0.45),
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
  });

  final double diameter;
  final String? image;
  final String initials;
  final Color ringColor;
  final bool highlighted;

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
            color: ringColor.withValues(alpha: highlighted ? 0.55 : 0.3),
            blurRadius: diameter * (highlighted ? 0.4 : 0.22),
            offset: Offset(0, diameter * 0.06),
          ),
        ],
      ),
      child: Container(
        // Thin white gap between the ring and the picture.
        padding: EdgeInsets.all(diameter * 0.025),
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
        ),
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
