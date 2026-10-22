import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  void _logout(BuildContext context) {
    // Clear anything pushed above the shell before dropping the session so
    // no signed-in screen stays reachable with the back button.
    Navigator.of(context).popUntil((route) => route.isFirst);
    AuthScope.read(context).logout();
  }

  @override
  Widget build(BuildContext context) {
    final username = AuthScope.of(context).session?.username ?? '';
    return Scaffold(
      appBar: const YuwoAppBar(),
      body: PageBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppCard(
              width: double.infinity,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: AppColors.background,
                    foregroundColor: AppColors.textPrimary,
                    child: Text(
                      username.isEmpty ? '?' : username[0].toUpperCase(),
                      style: AppText.pageTitle.copyWith(fontSize: 22),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.gap),
                  Expanded(
                    child: SectionHeader(username, subtitle: 'Signed in'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.section),
            OutlinedButton(
              onPressed: () => _logout(context),
              child: const Text('Log Out'),
            ),
          ],
        ),
      ),
    );
  }
}
