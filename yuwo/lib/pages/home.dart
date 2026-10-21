import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/common.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  // Placeholder until balances come from the backend.
  static const _amountOwed = 200;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: YuwoAppBar(
        actions: [
          IconButton(
            tooltip: 'Notifications',
            icon: const Icon(Icons.notifications),
            onPressed: () {},
          ),
        ],
      ),
      body: PageBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppCard(
              height: 200,
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeader(
                    'You Owe',
                    subtitle: 'Collective Amount Owed From Splits',
                  ),
                  const SizedBox(height: AppSpacing.gap),
                  Text('\$$_amountOwed', style: AppText.amount),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.section),
            const SectionHeader('Splits to Complete'),
            const SplitList(),
            const SizedBox(height: AppSpacing.gap),
            const SectionHeader('Transactions'),
            const SplitList(),
          ],
        ),
      ),
    );
  }
}

class SplitList extends StatelessWidget {
  const SplitList({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        spacing: 12.0,
        children: List.generate(10, (i) => const SplitItem()),
      ),
    );
  }
}

class SplitItem extends StatelessWidget {
  const SplitItem({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8.0),
      child: AppCard(
        height: 112,
        width: 224,
        radius: AppRadius.tile,
        child: SizedBox.shrink(),
      ),
    );
  }
}
