import 'package:flutter/material.dart';

import '../routes.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../utils/validators.dart';
import '../widgets/auth_layout.dart';
import '../widgets/common.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading || !_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      // On success AuthGate swaps this page for the app, so there is no
      // login screen left behind on the back stack.
      await AuthScope.read(
        context,
      ).login(username: _username.text.trim(), password: _password.text);
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      title: 'Welcome Back',
      subtitle: 'Change the way you handle money',
      form: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _username,
                autocorrect: false,
                autofillHints: const [AutofillHints.username],
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(hintText: 'Username'),
                validator: (v) => Validators.required(v, 'your username'),
              ),
              const SizedBox(height: AppSpacing.field),
              PasswordField(
                controller: _password,
                onFieldSubmitted: (_) => _submit(),
                validator: (v) => Validators.required(v, 'your password'),
              ),
              const SizedBox(height: AppSpacing.gap),
              LoadingButton(
                label: 'Login',
                loading: _loading,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
      footer: [
        OutlinedButton(
          onPressed: _loading
              ? null
              : () => Navigator.of(context).pushNamed(AppRoutes.signup),
          child: const Text('Create Account'),
        ),
      ],
    );
  }
}
