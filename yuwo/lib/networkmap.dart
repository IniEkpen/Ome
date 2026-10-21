
import 'package:flutter/material.dart';
import 'package:plough/plough.dart' as gv;
import 'custom_behaviour.dart';
import 'edgechecker.dart';
import 'network_repository.dart';
import 'transactiongraph.dart';

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

/// Inject an authenticated backend implementation
/// of NetworkRepository.
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

  // Search usernames through the backend.
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

      // Basic zoom-out based on path length.
      // Precise node-centered camera movement
      // requires layout coordinates.
      final targetScale = path.length > 4
          ? 0.55
          : path.length > 2
              ? 0.75
              : 1.0;

      _animateCamera(
        Matrix4.identity()..scale(targetScale),
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
        child: Column(
          children: [
            // Layer selection and privacy toggle.
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                crossAxisAlignment:
                    WrapCrossAlignment.center,
                spacing: 16,
                runSpacing: 8,
                children: [
                  DropdownButton<int>(
                    value: depth,
                    items: List.generate(
                      4,
                      (i) => DropdownMenuItem(
                        value: i + 1,
                        child: Text('Layer ${i + 1}'),
                      ),
                    ),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          depth = value;
                          path = [];
                          extraIds = {};
                        });
                        _loadLayer();
                      }
                    },
                  ),

                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Show my private transactions',
                      ),
                      Switch(
                        value: showMyPrivate,
                        onChanged: _togglePrivate,
                      ),
                    ],
                  ),

                  TextButton(
                    onPressed: () {
                      setState(() {
                        path = [];
                        extraIds = {};
                        message = null;
                      });

                      _animateCamera(
                        Matrix4.identity(),
                      );
                    },
                    child: const Text('Reset view'),
                  ),
                ],
              ),
            ),

            // Username search.
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
              ),
              child: Column(
                children: [
                  TextField(
                    controller: searchController,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search username',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: _searchSuggestions,
                  ),

                  if (suggestions.isNotEmpty)
                    SizedBox(
                      height: 150,
                      child: ListView.builder(
                        itemCount: suggestions.length,
                        itemBuilder: (context, i) {
                          return ListTile(
                            title: Text(
                              suggestions[i].label,
                            ),
                            onTap: () {
                              searchController.text =
                                  suggestions[i].label;

                              _find(suggestions[i]);
                            },
                          );
                        },
                      ),
                    ),

                  if (message != null)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(message!),
                    ),

                  if (path.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        'Public path: ${path.map(
                          (id) =>
                              builder.party(id)?.label ?? id,
                        ).join(' → ')}',
                      ),
                    ),
                ],
              ),
            ),

            if (busy)
              const LinearProgressIndicator(),

            // Zoomable transaction graph.
            Expanded(
              child: ClipRect(
                child: InteractiveViewer(
                  transformationController: camera,
                  minScale: 0.2,
                  maxScale: 4,
                  constrained: true,
                  child: Graph(graph: visible),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
