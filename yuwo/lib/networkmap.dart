
import 'package:flutter/material.dart';
import 'package:plough/plough.dart' as gv;
import 'custom_behaviour.dart';
import 'edgechecker.dart';
import 'network_repository.dart';
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
          constraints.hasBoundedWidth
              ? constraints.maxWidth
              : 800,
          constraints.hasBoundedHeight
              ? constraints.maxHeight
              : 600,
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
  const Network({
    super.key,
    required this.repository,
    required this.viewerId,
  });

  final NetworkRepository repository;
  final String viewerId;

  @override
  State<Network> createState() => _NetworkState();
}

class _NetworkState extends State<Network>
    with SingleTickerProviderStateMixin {

  late TransactionGraphBuilder builder;

  late final TransformationController camera =
      TransformationController();

  late final AnimationController animation =
      AnimationController(
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

    builder = TransactionGraphBuilder(
      viewerId: widget.viewerId,
    );

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
    } catch (_) {
      if (mounted && version == requestVersion) {
        setState(() {
          busy = false;
          message = 'Unable to load network';
        });
      }
    }
  }

  // Private transactions are hidden by default.
  Future<void> _togglePrivate(bool value) async {
    setState(() => showMyPrivate = value);

    if (!value) return;

    try {
      final payload =
          await widget.repository.loadMyPrivateTransactions();

      if (!mounted) return;

      setState(() => _merge(payload));
    } catch (_) {
      if (mounted) {
        setState(() {
          showMyPrivate = false;
          message = 'Unable to load private transactions';
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
      final result =
          await widget.repository.searchUsers(query.trim());

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
      final payload =
          await widget.repository.findPublicPath(
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

        extraIds = {
          ...payload.parties.map((p) => p.id),
          ...path,
        };

        busy = false;
      });

      //Zoom in animation for path length
      final targetScale = path.length > 4
          ? 0.55
          : path.length > 2
              ? 0.75
              : 1.0;

      _animateCamera(
        Matrix4.diagonal3Values(targetScale, targetScale, 1),
      );
    } catch (_) {
      if (mounted && version == requestVersion) {
        setState(() {
          busy = false;
          message = 'Search failed';
        });
      }
    }
  }

  void _animateCamera(Matrix4 target) {
    animation.stop();

    cameraTween = Matrix4Tween(
      begin: camera.value.clone(),
      end: target,
    ).animate(
      CurvedAnimation(
        parent: animation,
        curve: Curves.easeInOutCubic,
      ),
    );

    animation.forward(from: 0);
  }

  @override
  void dispose() {
    searchController.dispose();
    animation.dispose();
    camera.dispose();
    super.dispose();
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
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Yuwo', style: AppText.brand),
              const SizedBox(height: AppSpacing.field),
              Text('Network', style: AppText.pageTitle),
              Text(
                'Who you are connected to through transactions',
                style: AppText.caption,
              ),
              const SizedBox(height: AppSpacing.gap),

              // Layer selection and privacy toggle.
              AppCard(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 6,
                      children: [
                        Text('Layer', style: AppText.sectionTitle),
                        const SizedBox(width: 4),
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

                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Show my private transactions',
                          style: AppText.sectionTitle,
                        ),
                        const SizedBox(width: 8),
                        Switch(
                          value: showMyPrivate,
                          onChanged: _togglePrivate,
                        ),
                      ],
                    ),

                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          path = [];
                          extraIds = {};
                          message = null;
                        });

                        _animateCamera(Matrix4.identity());
                      },
                      icon: const Icon(Icons.center_focus_strong, size: 18),
                      label: const Text('Reset view'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.field),

              // Username search.
              TextField(
                controller: searchController,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search username',
                  fillColor: AppColors.surface,
                ),
                onChanged: _searchSuggestions,
              ),

              if (suggestions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: AppCard(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    radius: AppRadius.control,
                    child: SizedBox(
                      height: 150,
                      child: ListView.separated(
                        itemCount: suggestions.length,
                        separatorBuilder: (context, i) => const Divider(
                          height: 1,
                          indent: 16,
                          endIndent: 16,
                          color: AppColors.divider,
                        ),
                        itemBuilder: (context, i) {
                          final party = suggestions[i];
                          return ListTile(
                            dense: true,
                            leading: CircleAvatar(
                              radius: 16,
                              backgroundImage: AssetImage(
                                party.imageAsset ?? 'images/profile.png',
                              ),
                            ),
                            title: Text(
                              party.label,
                              style: AppText.sectionTitle,
                            ),
                            trailing: const Icon(
                              Icons.north_east,
                              size: 16,
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
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        size: 16,
                        color: AppColors.error,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        message!,
                        style: AppText.sectionTitle.copyWith(
                          color: AppColors.error,
                        ),
                      ),
                    ],
                  ),
                ),

              if (path.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.field),
                  child: _PathTrail(
                    labels: [
                      for (final id in path) builder.party(id)?.label ?? id,
                    ],
                  ),
                ),

              const SizedBox(height: AppSpacing.field),

              // Zoomable transaction graph.
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  child: ColoredBox(
                    color: AppColors.surface,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: InteractiveViewer(
                            transformationController: camera,
                            minScale: 0.2,
                            maxScale: 4,
                            constrained: true,
                            child: Graph(graph: visible),
                          ),
                        ),
                        if (busy)
                          const Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: LinearProgressIndicator(minHeight: 3),
                          ),
                        const Positioned(
                          left: 16,
                          bottom: 16,
                          child: _Legend(),
                        ),
                      ],
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
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.textPrimary : AppColors.background,
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

// The public path shown as a row of name pills joined by arrows.
class _PathTrail extends StatelessWidget {
  const _PathTrail({required this.labels});

  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Public path', style: AppText.caption),
        const SizedBox(height: 6),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var i = 0; i < labels.length; i++) ...[
              if (i > 0)
                const Icon(
                  Icons.arrow_forward,
                  size: 14,
                  color: AppColors.path,
                ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: AppColors.path.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
                child: Text(
                  labels[i],
                  style: AppText.sectionTitle.copyWith(color: AppColors.path),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    Widget item(Color color, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: AppText.caption.copyWith(color: AppColors.hint)),
      ],
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(AppRadius.control),
        boxShadow: AppShadows.card,
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        children: [
          item(AppColors.viewer, 'You'),
          item(AppColors.contact, 'Contacts'),
          item(AppColors.path, 'Path'),
          item(AppColors.private, 'Private'),
        ],
      ),
    );
  }
}
