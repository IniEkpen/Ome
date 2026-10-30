import 'package:flutter/material.dart';

import 'package:plough/plough.dart' as gv;
import 'custom_behaviour.dart';
import 'edgechecker.dart';
import 'network_repository.dart';
import 'services/api_client.dart';
import 'transactiongraph.dart';
import 'theme/app_theme.dart';
import 'widgets/common.dart';

class Graph extends StatelessWidget {
  const Graph({super.key, required this.graph});

  final gv.Graph graph;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(
          constraints.hasBoundedWidth ? constraints.maxWidth : 800,
          constraints.hasBoundedHeight ? constraints.maxHeight : 600,
        );

        return gv.GraphView(
          graph: graph,
          layoutStrategy: edgeAvoidingLayoutFor(graph, size),
          behavior: const CustomBehavior(),
        );
      },
    );
  }
}

//backend current user implementation.. find their transactions
class Network extends StatefulWidget {
  const Network({super.key, required this.repository, required this.viewerId});

  final NetworkRepository repository;
  final String viewerId;

  @override
  State<Network> createState() => _NetworkState();
}

class _NetworkState extends State<Network> with SingleTickerProviderStateMixin {
  late TransactionGraphBuilder builder;

  late final TransformationController camera = TransformationController();

  late final AnimationController animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  );

  Animation<Matrix4>? cameraTween;

  int depth = 1;
  bool showMyPrivate = false;
  bool busy = false;

  String? message;
  List<String> path = [];
  Set<String> extraIds = {};
  List<Party> suggestions = [];

  final searchController = TextEditingController();

  int searchVersion = 0;
  int requestVersion = 0;

  @override
  void initState() {
    super.initState();

    builder = TransactionGraphBuilder(viewerId: widget.viewerId);

    animation.addListener(() {
      if (cameraTween != null) {
        camera.value = cameraTween!.value;
      }
    });

    _loadLayer();
  }

  // Add transactions returned by the backend.
  void _merge(NetworkPayload payload) {
    for (final party in payload.parties) {
      builder.addParty(party);
    }

    for (final tx in payload.transactions) {
      final from = builder.party(tx.senderId);
      final to = builder.party(tx.recipientId);

      if (from == null || to == null) continue;

      builder.recordTransaction(
        id: tx.id,
        sender: from,
        recipient: to,
        amount: tx.amount,
        isPrivate: tx.isPrivate,
        timestamp: tx.timestamp,
        note: tx.note,
      );
    }
  }

  // Load the selected number of network layers.
  Future<void> _loadLayer() async {
    final version = ++requestVersion;

    setState(() {
      busy = true;
      message = null;
    });

    try {
      final payload = await widget.repository.loadLayer(
        viewerId: widget.viewerId,
        depth: depth,
      );

      if (!mounted || version != requestVersion) return;

      setState(() {
        _merge(payload);
        busy = false;
      });
    } catch (e) {
      if (mounted && version == requestVersion) {
        setState(() {
          busy = false;
          message = _errorText(e, 'Unable to load network');
        });
      }
    }
  }

  // Private transactions are hidden by default.
  Future<void> _togglePrivate(bool value) async {
    setState(() => showMyPrivate = value);

    if (!value) return;

    try {
      final payload = await widget.repository.loadMyPrivateTransactions();

      if (!mounted) return;

      setState(() => _merge(payload));
    } catch (e) {
      if (mounted) {
        setState(() {
          showMyPrivate = false;
          message = _errorText(e, 'Unable to load private transactions');
        });
      }
    }
  }

  // Search usernames through the backend
  Future<void> _searchSuggestions(String query) async {
    final version = ++searchVersion;

    if (query.trim().isEmpty) {
      setState(() => suggestions = []);
      return;
    }

    try {
      final result = await widget.repository.searchUsers(query.trim());

      if (mounted && version == searchVersion) {
        setState(() => suggestions = result);
      }
    } catch (_) {
      if (mounted && version == searchVersion) {
        setState(() => suggestions = []);
      }
    }
  }

  // Find a public transaction path to a user.
  Future<void> _find(Party target) async {
    FocusScope.of(context).unfocus();

    final version = ++requestVersion;

    setState(() {
      busy = true;
      suggestions = [];
      message = null;
    });

    try {
      final payload = await widget.repository.findPublicPath(
        viewerId: widget.viewerId,
        targetId: target.id,
      );

      if (!mounted || version != requestVersion) return;

      if (payload == null || payload.path.isEmpty) {
        setState(() {
          busy = false;
          message = 'No available public connection';
        });
        return;
      }

      setState(() {
        _merge(payload);

        path = payload.path;

        extraIds = {...payload.parties.map((p) => p.id), ...path};

        busy = false;
      });

      // The layout always fits every node inside the map, so showing the
      // whole path just means easing back to the un-zoomed view.
      _animateCamera(Matrix4.identity());
    } catch (e) {
      if (mounted && version == requestVersion) {
        setState(() {
          busy = false;
          message = _errorText(e, 'Search failed');
        });
      }
    }
  }

  // The server's own message (e.g. "Please sign in again.") says more than
  // a generic one.
  static String _errorText(Object error, String fallback) =>
      error is ApiException ? error.message : fallback;

  void _animateCamera(Matrix4 target) {
    animation.stop();

    cameraTween = Matrix4Tween(
      begin: camera.value.clone(),
      end: target,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeInOutCubic));

    animation.forward(from: 0);
  }

  @override
  void dispose() {
    searchController.dispose();
    animation.dispose();
    camera.dispose();
    super.dispose();
  }

  void _resetView() {
    setState(() {
      path = [];
      extraIds = {};
      message = null;
    });

    _animateCamera(Matrix4.identity());
  }

  @override
  Widget build(BuildContext context) {
    final visible = builder.visibleGraph(
      maxDepth: depth,
      showMyPrivate: showMyPrivate,
      extraIds: extraIds,
      highlightedPath: path,
    );

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Network',
                          style: AppText.pageTitle.copyWith(fontSize: 22),
                        ),
                        Text(
                          'Who you are connected to through transactions',
                          style: AppText.caption,
                        ),
                      ],
                    ),
                  ),
                  _RoundButton(
                    icon: Icons.center_focus_strong,
                    tooltip: 'Reset view',
                    onTap: _resetView,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.field),

              // Layer selection and privacy toggle, on one line.
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.control),
                      boxShadow: AppShadows.card,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            'Layer',
                            style: AppText.caption.copyWith(
                              color: AppColors.hint,
                            ),
                          ),
                        ),
                        for (var i = 1; i <= 4; i++)
                          _LayerChip(
                            layer: i,
                            selected: depth == i,
                            onTap: () {
                              if (depth == i) return;
                              setState(() {
                                depth = i;
                                path = [];
                                extraIds = {};
                              });
                              _loadLayer();
                            },
                          ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  _PrivateToggle(
                    value: showMyPrivate,
                    onChanged: _togglePrivate,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.field),

              // Username search.
              TextField(
                controller: searchController,
                style: AppText.body,
                textAlignVertical: TextAlignVertical.center,
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  prefixIcon: Icon(Icons.search, size: 20),
                  prefixIconConstraints: BoxConstraints(minWidth: 40),
                  hintText: 'Search username',
                  fillColor: AppColors.surface,
                ),
                onChanged: _searchSuggestions,
              ),

              if (suggestions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: AppCard(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    radius: AppRadius.control,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 150),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: suggestions.length,
                        separatorBuilder: (context, i) => const Divider(
                          height: 1,
                          indent: 52,
                          endIndent: 12,
                          color: AppColors.divider,
                        ),
                        itemBuilder: (context, i) {
                          final party = suggestions[i];
                          return ListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                            ),
                            leading: NetworkAvatar(
                              diameter: 30,
                              image: party.image,
                              initials: party.initials,
                              ringColor: MapColors.node,
                            ),
                            title: Text(
                              party.label,
                              style: AppText.sectionTitle,
                            ),
                            trailing: const Icon(
                              Icons.north_east,
                              size: 14,
                              color: AppColors.hint,
                            ),
                            onTap: () {
                              searchController.text = party.label;

                              _find(party);
                            },
                          );
                        },
                      ),
                    ),
                  ),
                ),

              if (message != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        size: 14,
                        color: AppColors.error,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        message!,
                        style: AppText.caption.copyWith(color: AppColors.error),
                      ),
                    ],
                  ),
                ),

              if (path.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _PathTrail(
                    labels: [
                      for (final id in path) builder.party(id)?.label ?? id,
                    ],
                  ),
                ),

              const SizedBox(height: AppSpacing.field),

              // Zoomable transaction graph.
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    boxShadow: AppShadows.card,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    child: ColoredBox(
                      color: MapColors.canvas,
                      child: Column(
                        children: [
                          Expanded(
                            child: Stack(
                              children: [
                                // minScale 1 keeps the map from shrinking
                                // into a corner of the box; with no
                                // boundary margin it can't be panned
                                // past its edges either.
                                Positioned.fill(
                                  child: InteractiveViewer(
                                    transformationController: camera,
                                    minScale: 1,
                                    maxScale: 3,
                                    constrained: true,
                                    child: Graph(graph: visible),
                                  ),
                                ),
                                if (busy)
                                  const Positioned(
                                    top: 0,
                                    left: 0,
                                    right: 0,
                                    child: LinearProgressIndicator(
                                      minHeight: 2,
                                      color: MapColors.node,
                                      backgroundColor: Colors.transparent,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const _Legend(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.surface,
        shape: const CircleBorder(),
        elevation: 0,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 38,
            height: 38,
            child: Icon(icon, size: 18, color: AppColors.textPrimary),
          ),
        ),
      ),
    );
  }
}

class _LayerChip extends StatelessWidget {
  const _LayerChip({
    required this.layer,
    required this.selected,
    required this.onTap,
  });

  final int layer;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.tile),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.textPrimary : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.tile),
        ),
        child: Text(
          '$layer',
          style: AppText.sectionTitle.copyWith(
            color: selected ? AppColors.surface : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

// Pill that switches the viewer's private transactions on and off.
class _PrivateToggle extends StatelessWidget {
  const _PrivateToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final fg = value ? AppColors.surface : AppColors.textPrimary;
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: value ? AppColors.private : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.control),
          boxShadow: AppShadows.card,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              value ? Icons.lock_open_rounded : Icons.lock_rounded,
              size: 15,
              color: fg,
            ),
            const SizedBox(width: 6),
            Text('Private', style: AppText.sectionTitle.copyWith(color: fg)),
          ],
        ),
      ),
    );
  }
}

// The public path shown as a row of name pills joined by arrows.
class _PathTrail extends StatelessWidget {
  const _PathTrail({required this.labels});

  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 4,
      runSpacing: 4,
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0)
            const Icon(Icons.arrow_forward, size: 12, color: MapColors.node),
          // Black pills, matching the path on the map.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: MapColors.node,
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            child: Text(
              labels[i],
              style: AppText.caption.copyWith(color: AppColors.surface),
            ),
          ),
        ],
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    // Nodes are all black, so the legend explains what each line means.
    Widget item(
      String label,
      Color color,
      double width, [
      (double, double)? dash,
    ]) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(
          size: const Size(18, 8),
          painter: LinkPainter(
            color: color,
            width: width,
            length: 18,
            thickness: 8,
            dash: dash,
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: AppText.caption.copyWith(color: AppColors.hint)),
      ],
    );

    // Footer strip under the map, so the legend never covers a node.
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 14,
        runSpacing: 2,
        children: [
          for (final style in LinkStyle.values)
            item(style.label, style.color, style.width, style.dash),
          item('Path', MapColors.pathLink, 3.2),
        ],
      ),
    );
  }
}
