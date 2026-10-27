import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../utils/validators.dart';
import '../widgets/auth_layout.dart';
import '../widgets/common.dart';
import '../widgets/social_sign_in_buttons.dart';

class CreateAccountPage extends StatefulWidget {
  const CreateAccountPage({super.key});

  @override
  State<CreateAccountPage> createState() => _CreateAccountPageState();
}

class _CreateAccountPageState extends State<CreateAccountPage> {
  final _formKey = GlobalKey<FormState>();
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    for (final c in [
      _first,
      _last,
      _username,
      _email,
      _phone,
      _password,
      _confirm,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading || !_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await AuthScope.read(context).signup(
        username: _username.text.trim(),
        firstName: _first.text.trim(),
        lastName: _last.text.trim(),
        email: _email.text.trim(),
        phone: _phone.text.replaceAll(RegExp(r'[\s\-()]'), ''),
        password: _password.text,
      );
      // Signed in: drop back to the root so AuthGate shows the app and
      // the sign-up form can't be returned to with the back button.
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _field(
    TextEditingController controller,
    String hint,
    FormFieldValidator<String> validator, {
    TextInputType? keyboardType,
    Iterable<String>? autofillHints,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      autocorrect: false,
      autofillHints: autofillHints,
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(hintText: hint),
      validator: validator,
    );
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: AppSpacing.field);
    return AuthLayout(
      title: "Let's create an account",
      subtitle: 'Split costs with friends in seconds',
      form: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _field(
                      _first,
                      'First Name',
                      Validators.name,
                      autofillHints: const [AutofillHints.givenName],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.field),
                  Expanded(
                    child: _field(
                      _last,
                      'Last Name',
                      Validators.name,
                      autofillHints: const [AutofillHints.familyName],
                    ),
                  ),
                ],
              ),
              gap,
              _field(
                _username,
                'Username',
                Validators.newUsername,
                autofillHints: const [AutofillHints.newUsername],
              ),
              gap,
              _field(
                _email,
                'Email',
                Validators.email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
              ),
              gap,
              _field(
                _phone,
                'Phone Number',
                Validators.phone,
                keyboardType: TextInputType.phone,
                autofillHints: const [AutofillHints.telephoneNumber],
              ),
              gap,
              PasswordField(
                controller: _password,
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.next,
                validator: (v) => Validators.newPassword(
                  v,
                  username: _username.text,
                  email: _email.text,
                ),
              ),
              gap,
              PasswordField(
                controller: _confirm,
                hintText: 'Confirm Password',
                autofillHints: const [AutofillHints.newPassword],
                onFieldSubmitted: (_) => _submit(),
                validator: (v) =>
                    v == _password.text ? null : 'Passwords do not match',
              ),
              const SizedBox(height: AppSpacing.gap),
              LoadingButton(
                label: 'Create Account',
                loading: _loading,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
      footer: [
        // This page sits above the login screen; close it once signed in.
        SocialSignInButtons(
          onSignedIn: () =>
              Navigator.of(context).popUntil((route) => route.isFirst),
        ),
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).maybePop(),
          child: const Text('Already have an account? Login'),
        ),
      ],
    );
  }
}
