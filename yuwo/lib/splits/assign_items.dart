import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../utils/money.dart';
import '../widgets/common.dart';
import 'split_model.dart';
import 'split_service.dart';

/// The host's roulette: spin the people wheel to someone, then swipe an item
/// card up to put it on their share. Everyone sees it live.
class AssignItemsPage extends StatefulWidget {
  const AssignItemsPage({super.key, required this.live});

  final LiveSplit live;

  @override
  State<AssignItemsPage> createState() => _AssignItemsPageState();
}

class _AssignItemsPageState extends State<AssignItemsPage>
    with SingleTickerProviderStateMixin {
  final _people = PageController(viewportFraction: 0.28);
  final _items = PageController(viewportFraction: 0.68);
  late final AnimationController _fly = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  int _person = 0;
  int _item = 0;
  // How far the current card is dragged up (negative), and where a fly-off
  // started from.
  double _drag = 0;
  double _flyFrom = 0;
  bool _sending = false;

  static const _swipeDistance = 90.0;
  static const _flyDistance = 460.0;

  SplitService get _service => SplitService(AuthScope.read(context));

  @override
  void dispose() {
    _people.dispose();
    _items.dispose();
    _fly.dispose();
    super.dispose();
  }

  double get _offset => _fly.isAnimating || _fly.value > 0
      ? _flyFrom + (-_flyDistance - _flyFrom) * _fly.value
      : _drag;

  Future<void> _send(SplitBill split) async {
    if (_sending || split.items.isEmpty || split.participants.isEmpty) return;
    final item = split.items[_item.clamp(0, split.items.length - 1)];
    final person =
        split.participants[_person.clamp(0, split.participants.length - 1)];
    if (item.claimedBy.contains(person.userId)) {
      setState(() => _drag = 0);
      showMessage(context, '${person.username} already has ${item.name}');
      return;
    }
    setState(() {
      _sending = true;
      _flyFrom = _drag;
    });
    HapticFeedback.mediumImpact();
    final flying = _fly.forward(from: 0);
    try {
      final next = await _service.assignItem(split.id, item.id, person.userId);
      await flying;
      widget.live.apply(next);
      if (!mounted) return;
      showMessage(context, '${item.name} → ${person.username}');
      _advance(next ?? split);
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message);
    } finally {
      if (mounted) {
        _fly.value = 0;
        setState(() {
          _drag = 0;
          _sending = false;
        });
      }
    }
  }

  /// Moves to the next item nobody has yet, if there is one.
  void _advance(SplitBill split) {
    final items = split.items;
    for (var step = 1; step <= items.length; step++) {
      final index = (_item + step) % items.length;
      if (items[index].claimedBy.isEmpty) {
        _items.animateToPage(
          index,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
        );
        return;
      }
    }
  }

  Future<void> _unassign(SplitBill split, SplitItem item, int userId) async {
    try {
      widget.live.apply(
        await _service.assignItem(split.id, item.id, userId, claimed: false),
      );
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message);
    }
  }

  /// 1 at the centre of a wheel, shrinking towards the edges.
  double _scale(PageController controller, int index) {
    final page = controller.hasClients && controller.position.haveDimensions
        ? controller.page ?? controller.initialPage.toDouble()
        : controller.initialPage.toDouble();
    return (1 - (page - index).abs() * 0.28).clamp(0.6, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Assign items',
          style: AppText.sectionTitle.copyWith(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([widget.live, _fly]),
        builder: (context, _) {
          final split = widget.live.split;
          if (split == null || !split.isClaiming) {
            return Center(
              child: Text('This bill is closed.', style: AppText.body),
            );
          }
          final people = split.participants;
          final person = people[_person.clamp(0, people.length - 1)];
          final unclaimed = split.items.where((i) => i.claimedBy.isEmpty);
          return Column(
            children: [
              const SizedBox(height: AppSpacing.field),
              // Top wheel: who it goes to.
              SizedBox(
                height: 120,
                child: PageView.builder(
                  controller: _people,
                  itemCount: people.length,
                  onPageChanged: (i) => setState(() => _person = i),
                  itemBuilder: (context, i) => AnimatedBuilder(
                    animation: _people,
                    builder: (context, _) => Transform.scale(
                      scale: _scale(_people, i),
                      child: _PersonChip(
                        person: people[i],
                        selected: i == _person,
                        onTap: () => _people.animateToPage(
                          i,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Icon(
                Icons.keyboard_double_arrow_up,
                color: AppColors.hint.withValues(alpha: 0.8),
              ),
              Text(
                'Swipe an item up to give it to ${person.username}',
                style: AppText.caption.copyWith(fontSize: 12),
              ),
              const Spacer(),
              // Bottom wheel: the receipt's items.
              SizedBox(
                height: 250,
                child: PageView.builder(
                  controller: _items,
                  itemCount: split.items.length,
                  onPageChanged: (i) => setState(() {
                    _item = i;
                    _drag = 0;
                  }),
                  itemBuilder: (context, i) {
                    final item = split.items[i];
                    final current = i == _item;
                    return AnimatedBuilder(
                      animation: _items,
                      builder: (context, _) => Transform.scale(
                        scale: _scale(_items, i),
                        child: current
                            ? GestureDetector(
                                onVerticalDragUpdate: _sending
                                    ? null
                                    : (d) => setState(
                                        () => _drag = (_drag + d.delta.dy)
                                            .clamp(-_flyDistance, 0),
                                      ),
                                onVerticalDragEnd: _sending
                                    ? null
                                    : (d) {
                                        final fast =
                                            (d.primaryVelocity ?? 0) < -600;
                                        if (_drag < -_swipeDistance || fast) {
                                          _send(split);
                                        } else {
                                          setState(() => _drag = 0);
                                        }
                                      },
                                child: Transform.translate(
                                  offset: Offset(0, _offset),
                                  child: Opacity(
                                    opacity: (1 + _offset / _flyDistance).clamp(
                                      0.0,
                                      1.0,
                                    ),
                                    child: _ItemCard(
                                      split: split,
                                      item: item,
                                      onRemove: (userId) =>
                                          _unassign(split, item, userId),
                                    ),
                                  ),
                                ),
                              )
                            : _ItemCard(
                                split: split,
                                item: item,
                                onRemove: (userId) =>
                                    _unassign(split, item, userId),
                              ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.page,
                  AppSpacing.field,
                  AppSpacing.page,
                  AppSpacing.page,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Same as swiping, for a mouse or a screen reader.
                    LoadingButton(
                      label: 'Send to ${person.username}',
                      loading: _sending,
                      onPressed: () => _send(split),
                    ),
                    const SizedBox(height: AppSpacing.field),
                    Text(
                      unclaimed.isEmpty
                          ? 'Every item has someone.'
                          : '${unclaimed.length} item${unclaimed.length == 1 ? '' : 's'} '
                                'still unclaimed',
                      textAlign: TextAlign.center,
                      style: AppText.caption.copyWith(
                        color: unclaimed.isEmpty
                            ? AppColors.path
                            : AppColors.hint,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PersonChip extends StatelessWidget {
  const _PersonChip({
    required this.person,
    required this.selected,
    required this.onTap,
  });

  final SplitParticipant person;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: 'Give to ${person.username}',
      // The tap has to be on this node: excludeSemantics hides the
      // GestureDetector's own, so screen readers couldn't select anyone.
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? AppColors.textPrimary : Colors.transparent,
                  width: 2.5,
                ),
                boxShadow: selected ? AppShadows.card : null,
              ),
              child: CircleAvatar(
                radius: 30,
                backgroundColor: person.isHost
                    ? AppColors.textPrimary
                    : AppColors.surface,
                foregroundColor: person.isHost
                    ? AppColors.surface
                    : AppColors.textPrimary,
                child: Text(
                  person.username[0].toUpperCase(),
                  // copyWith(color: null) keeps the style's black, so set it.
                  style: AppText.pageTitle.copyWith(
                    fontSize: 22,
                    color: person.isHost
                        ? AppColors.surface
                        : AppColors.textPrimary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              person.username,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.sectionTitle.copyWith(
                color: selected ? AppColors.textPrimary : AppColors.hint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({
    required this.split,
    required this.item,
    required this.onRemove,
  });

  final SplitBill split;
  final SplitItem item;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.gap),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.receipt_long, color: AppColors.hint),
            const SizedBox(height: AppSpacing.field),
            Text(
              item.quantity > 1 ? '${item.name} ×${item.quantity}' : item.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppText.sectionTitle.copyWith(fontSize: 18),
            ),
            const SizedBox(height: 4),
            Text(
              Money.format(item.totalCents),
              style: AppText.pageTitle.copyWith(fontSize: 26),
            ),
            const Spacer(),
            if (item.claimedBy.isEmpty)
              Text(
                'Unclaimed',
                style: AppText.caption.copyWith(color: AppColors.error),
              )
            else
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final userId in item.claimedBy)
                    InputChip(
                      label: Text(split.usernameOf(userId)),
                      visualDensity: VisualDensity.compact,
                      onDeleted: () => onRemove(userId),
                      deleteButtonTooltipMessage:
                          'Take ${split.usernameOf(userId)} off',
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
