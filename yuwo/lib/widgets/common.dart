import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Grey app bar with the Courgette "Yuwo" wordmark, as on the home page.
class YuwoAppBar extends StatelessWidget implements PreferredSizeWidget {
  const YuwoAppBar({super.key, this.actions});

  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text('Yuwo', style: AppText.brand),
      actions: actions,
    );
  }
}

/// White rounded container used for every card in the app.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.width,
    this.height,
    this.radius = AppRadius.card,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double? width;
  final double? height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: padding,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: child,
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppText.sectionTitle),
        if (subtitle != null) Text(subtitle!, style: AppText.caption),
      ],
    );
  }
}

/// Page padding plus a max width so wide screens get the same centred
/// column as the home page.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.page),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSpacing.contentMaxWidth,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Primary button that shows a spinner and blocks repeat taps while busy.
class LoadingButton extends StatelessWidget {
  const LoadingButton({
    super.key,
    required this.label,
    required this.loading,
    required this.onPressed,
  });

  final String label;
  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: loading ? null : onPressed,
      child: loading
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.surface,
              ),
            )
          : Text(label),
    );
  }
}

class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    this.hintText = 'Password',
    this.validator,
    this.autofillHints = const [AutofillHints.password],
    this.textInputAction = TextInputAction.done,
    this.onFieldSubmitted,
  });

  final TextEditingController controller;
  final String hintText;
  final FormFieldValidator<String>? validator;
  final Iterable<String> autofillHints;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onFieldSubmitted;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      obscureText: !_visible,
      enableSuggestions: false,
      autocorrect: false,
      autofillHints: widget.autofillHints,
      textInputAction: widget.textInputAction,
      onFieldSubmitted: widget.onFieldSubmitted,
      validator: widget.validator,
      decoration: InputDecoration(
        hintText: widget.hintText,
        suffixIcon: IconButton(
          tooltip: _visible ? 'Hide password' : 'Show password',
          icon: Icon(_visible ? Icons.visibility : Icons.visibility_off),
          onPressed: () => setState(() => _visible = !_visible),
        ),
      ),
    );
  }
}

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
