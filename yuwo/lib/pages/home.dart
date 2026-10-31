import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/home_service.dart';
import '../theme/app_theme.dart';
import '../utils/money.dart';
import '../widgets/common.dart';
import 'home_data.dart';
import 'pay_back.dart';
import 'payment_history.dart';

/// The Home tab: loads the signed-in user's bills and activity from the API.
/// Dev sessions the server didn't issue a token for get sample data instead.
class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  HomeData? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (AuthScope.read(context).session?.token == null) {
      _data = HomeData.mock();
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final data = await HomeService(AuthScope.read(context)).load();
      if (!mounted) return;
      setState(() {
        _data = data;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      // Keep what's on screen if a refresh fails.
      if (_data != null) {
        showMessage(context, e.message);
      } else {
        setState(() => _error = e.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (data != null) {
      return HomePage(data: data, onRefresh: data.isMock ? null : _load);
    }
    return Scaffold(
      appBar: const YuwoAppBar(),
      body: PageBody(
        child: _error == null
            ? const Center(child: CircularProgressIndicator())
            : AppCard(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_error!, style: AppText.body),
                    const SizedBox(height: AppSpacing.field),
                    OutlinedButton(
                      onPressed: () {
                        setState(() => _error = null);
                        _load();
                      },
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key, this.data, this.onRefresh});

  /// Defaults to sample entries when no data is given.
  final HomeData? data;

  /// Enables pull-to-refresh when set.
  final Future<void> Function()? onRefresh;

  Future<void> _payBack(BuildContext context) async {
    final message = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const PayBackPage()));
    if (message == null || !context.mounted) return;
    showMessage(context, message);
    await onRefresh?.call();
  }

  @override
  Widget build(BuildContext context) {
    final home = data ?? HomeData.mock();
    final open = home.bills.where((b) => b.stage != BillStage.paid).toList();
    final body = _body(context, home, open);
    return Scaffold(
      appBar: YuwoAppBar(
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton.filled(
              tooltip: 'Pay someone back',
              icon: const Icon(Icons.send_rounded, size: 20),
              style: IconButton.styleFrom(
                backgroundColor: AppColors.textPrimary,
                foregroundColor: AppColors.surface,
              ),
              onPressed: () => _payBack(context),
            ),
          ),
        ],
      ),
      body: onRefresh == null
          ? body
          : RefreshIndicator(onRefresh: onRefresh!, child: body),
    );
  }

  Widget _body(BuildContext context, HomeData home, List<HomeBill> open) {
    return PageBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (home.isMock) ...[
            const _SampleDataBadge(),
            const SizedBox(height: AppSpacing.field),
          ],
          _BalanceCard(home: home, openBills: open.length),
          const SizedBox(height: AppSpacing.section),
          const SectionHeader(
            'Open Bills',
            subtitle: 'Bills in your groups that still need something',
          ),
          const SizedBox(height: AppSpacing.field),
          if (open.isEmpty)
            AppCard(
              width: double.infinity,
              child: Text(
                "You're all settled up",
                style: AppText.body.copyWith(color: AppColors.hint),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              child: Row(
                spacing: AppSpacing.field,
                children: [
                  for (var i = 0; i < open.length; i++)
                    _BillCard(bill: open[i], colorIndex: i),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.section),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Expanded(
                child: SectionHeader(
                  'Recent Activity',
                  subtitle: 'Payments and changes across your groups',
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PaymentHistoryPage()),
                ),
                child: const Text('All payments'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.field),
          _ActivityList(activity: home.activity),
        ],
      ),
    );
  }
}

class _SampleDataBadge extends StatelessWidget {
  const _SampleDataBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.control),
        boxShadow: AppShadows.card,
      ),
      child: Text(
        'Sample data',
        style: AppText.caption.copyWith(color: AppColors.hint),
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.home, required this.openBills});

  final HomeData home;
  final int openBills;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            'You Owe',
            subtitle: 'Your share of bills that are still open',
          ),
          const SizedBox(height: AppSpacing.field),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(Money.format(home.youOweCents), style: AppText.amount),
          ),
          const Divider(height: 32, color: AppColors.divider),
          Row(
            children: [
              Expanded(
                child: _Stat(
                  label: 'Owed to you',
                  value: Money.format(home.owedToYouCents),
                ),
              ),
              Expanded(
                child: _Stat(label: 'Open bills', value: '$openBills'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppText.caption.copyWith(color: AppColors.hint)),
        Text(value, style: AppText.pageTitle.copyWith(fontSize: 20)),
      ],
    );
  }
}

/// Same gradients as the joined-group cards so a bill matches its group's look.
class _BillCard extends StatelessWidget {
  const _BillCard({required this.bill, required this.colorIndex});

  final HomeBill bill;
  final int colorIndex;

  @override
  Widget build(BuildContext context) {
    final colors =
        AppColors.groupCards[colorIndex % AppColors.groupCards.length];
    final onCard = AppColors.surface;
    return Container(
      width: 240,
      height: 150,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppShadows.tinted(colors.last),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  bill.groupName,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption.copyWith(
                    color: onCard.withValues(alpha: 0.8),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
                child: Text(
                  bill.stage.label,
                  style: AppText.caption.copyWith(color: onCard),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            bill.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.pageTitle.copyWith(color: onCard, fontSize: 20),
          ),
          const Spacer(),
          Text(
            bill.isHost ? "You're hosting · collecting" : 'Your share',
            style: AppText.caption.copyWith(
              color: onCard.withValues(alpha: 0.8),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  Money.format(bill.amountCents),
                  style: AppText.pageTitle.copyWith(
                    color: onCard,
                    fontSize: 22,
                  ),
                ),
              ),
              Icon(Icons.group, size: 14, color: onCard),
              const SizedBox(width: 4),
              Text(
                '${bill.people}',
                style: AppText.sectionTitle.copyWith(color: onCard),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActivityList extends StatelessWidget {
  const _ActivityList({required this.activity});

  final List<HomeActivity> activity;

  @override
  Widget build(BuildContext context) {
    if (activity.isEmpty) {
      return AppCard(
        width: double.infinity,
        child: Text(
          'Nothing yet. Join a group to get started.',
          style: AppText.body.copyWith(color: AppColors.hint),
        ),
      );
    }
    return AppCard(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        children: [
          for (var i = 0; i < activity.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: AppColors.divider),
            _ActivityRow(entry: activity[i]),
          ],
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.entry});

  final HomeActivity entry;

  @override
  Widget build(BuildContext context) {
    final (
      IconData icon,
      String text,
      String? amount,
      Color color,
    ) = switch (entry.kind) {
      ActivityKind.youPaid => (
        Icons.arrow_upward,
        'You paid ${entry.who}',
        '-${Money.format(entry.amountCents)}',
        AppColors.textPrimary,
      ),
      ActivityKind.paidYou => (
        Icons.arrow_downward,
        '${entry.who} paid you',
        '+${Money.format(entry.amountCents)}',
        AppColors.contact,
      ),
      ActivityKind.waived => (
        Icons.volunteer_activism_outlined,
        '${entry.who} waived part of your share',
        Money.format(entry.amountCents),
        AppColors.hint,
      ),
      ActivityKind.joined => (
        Icons.person_add_alt,
        '${entry.who} joined',
        null,
        AppColors.hint,
      ),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.background,
            foregroundColor: AppColors.textPrimary,
            child: Icon(icon, size: 18),
          ),
          const SizedBox(width: AppSpacing.field),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text, style: AppText.body),
                Text(
                  '${entry.groupName} · ${_relative(entry.when)}',
                  style: AppText.caption.copyWith(color: AppColors.hint),
                ),
              ],
            ),
          ),
          if (amount != null)
            Text(
              amount,
              style: AppText.body.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
        ],
      ),
    );
  }

  static String _relative(DateTime when) {
    final diff = DateTime.now().difference(when);
    if (diff.inHours < 1) return 'Just now';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    return '${diff.inDays} days ago';
  }
}
