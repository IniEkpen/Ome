import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'common.dart';

/// Shared frame for the login and create-account screens: wordmark, title,
/// subtitle, then the form inside a white card.
class AuthLayout extends StatelessWidget {
  const AuthLayout({
    super.key,
    required this.title,
    required this.subtitle,
    required this.form,
    this.footer = const [],
  });

  final String title;
  final String subtitle;
  final Widget form;
  final List<Widget> footer;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppSpacing.gap),
            Text('Yuwo', style: AppText.brand),
            const SizedBox(height: AppSpacing.section),
            Text(title, style: AppText.pageTitle),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: AppText.caption.copyWith(
                fontSize: 12,
                color: AppColors.hint,
              ),
            ),
            const SizedBox(height: AppSpacing.gap),
            AppCard(child: form),
            const SizedBox(height: AppSpacing.gap),
            ...footer,
          ],
        ),
      ),
    );
  }
}
