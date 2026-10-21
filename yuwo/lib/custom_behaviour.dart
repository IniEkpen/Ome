
import 'package:flutter/material.dart';
import 'package:plough/plough.dart' as gv;
import 'adaptinglayout.dart';

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
            ? const Color(0xFF16A085)
            : (node.properties['color'] as Color? ??
                Colors.blueGrey);

        return Container(
          width: diameter,
          height: diameter,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.22),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: gv.GraphDefaultNodeRenderer(
            node: node,
            style: gv.GraphDefaultNodeRendererStyle(
              shape:
                  gv.GraphDefaultNodeRendererShape.circle,
              height: diameter,
              width: diameter,
              borderWidth: highlighted ? 5 : 3,
              borderColor: ringColor,
              padding: EdgeInsets.zero,
            ),
            child: ClipOval(
              child: Image.asset(
                node['image'] as String,
                width: diameter,
                height: diameter,
                fit: BoxFit.cover,
              ),
            ),
          ),
        );
      },
    );
  }
}
