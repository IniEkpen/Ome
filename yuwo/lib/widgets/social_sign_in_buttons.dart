import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/social_sign_in.dart';
import '../theme/app_theme.dart';
import 'common.dart';
import 'google_web_button_stub.dart'
    if (dart.library.js_interop) 'google_web_button_web.dart';

/// "or" divider plus Sign in with Apple / Continue with Google, for the login
/// and create-account screens. Shows nothing when neither is configured.
class SocialSignInButtons extends StatefulWidget {
  const SocialSignInButtons({super.key, this.onSignedIn});

  /// Called after a successful sign-in, e.g. to close the signup page.
  final VoidCallback? onSignedIn;

  @override
  State<SocialSignInButtons> createState() => _SocialSignInButtonsState();
}

class _SocialSignInButtonsState extends State<SocialSignInButtons> {
  bool _googleReady = false;
  bool _busy = false;
  StreamSubscription<GoogleSignInAuthenticationEvent>? _googleEvents;

  @override
  void initState() {
    super.initState();
    if (SocialSignIn.googleEnabled) _startGoogle();
  }

  Future<void> _startGoogle() async {
    try {
      await SocialSignIn.ensureGoogle();
    } catch (_) {
      return; // Misconfigured client id: leave the button hidden.
    }
    if (!mounted) return;
    // On the web, Google's own button signs in and reports here.
    if (!GoogleSignIn.instance.supportsAuthenticate()) {
      _googleEvents = GoogleSignIn.instance.authenticationEvents.listen((
        event,
      ) {
        if (event is GoogleSignInAuthenticationEventSignIn) {
          _finishGoogle(event.user);
        }
      }, onError: (_) => _fail('Google'));
    }
    setState(() => _googleReady = true);
  }

  @override
  void dispose() {
    _googleEvents?.cancel();
    super.dispose();
  }

  void _fail(String provider) {
    if (mounted) showMessage(context, "Signing in with $provider didn't work.");
  }

  Future<void> _run(Future<void> Function() signIn) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await signIn();
      widget.onSignedIn?.call();
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // Phones: Google's native sheet.
  Future<void> _google() async {
    try {
      _finishGoogle(await GoogleSignIn.instance.authenticate());
    } on GoogleSignInException catch (e) {
      if (e.code != GoogleSignInExceptionCode.canceled) _fail('Google');
    }
  }

  Future<void> _finishGoogle(GoogleSignInAccount account) async {
    if (!mounted) return;
    final idToken = account.authentication.idToken;
    if (idToken == null) return _fail('Google');
    final auth = AuthScope.read(context);
    await _run(() => auth.signInWithGoogle(idToken));
  }

  Future<void> _apple() async {
    final auth = AuthScope.read(context);
    final rawNonce = SocialSignIn.newNonce();
    final AuthorizationCredentialAppleID credential;
    try {
      credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: SocialSignIn.sha256Of(rawNonce),
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code != AuthorizationErrorCode.canceled) _fail('Apple');
      return;
    } catch (_) {
      return _fail('Apple');
    }
    final identityToken = credential.identityToken;
    if (identityToken == null) return _fail('Apple');
    await _run(
      () => auth.signInWithApple(
        identityToken: identityToken,
        rawNonce: rawNonce,
        authorizationCode: credential.authorizationCode,
        firstName: credential.givenName,
        lastName: credential.familyName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final apple = SocialSignIn.appleEnabled;
    final google = SocialSignIn.googleEnabled && _googleReady;
    if (!apple && !google) return const SizedBox.shrink();
    final usesWebButton =
        google && !GoogleSignIn.instance.supportsAuthenticate();
    return AbsorbPointer(
      absorbing: _busy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: Divider(color: AppColors.divider)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('or', style: AppText.caption),
              ),
              const Expanded(child: Divider(color: AppColors.divider)),
            ],
          ),
          const SizedBox(height: AppSpacing.field),
          if (apple) ...[
            SignInWithAppleButton(
              onPressed: _apple,
              height: 52,
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            const SizedBox(height: AppSpacing.field),
          ],
          if (google)
            usesWebButton
                ? Center(child: googleWebButton())
                : OutlinedButton.icon(
                    onPressed: _google,
                    icon: Text(
                      'G',
                      style: AppText.button.copyWith(fontSize: 18),
                    ),
                    label: const Text('Continue with Google'),
                  ),
          if (_busy) ...[
            const SizedBox(height: AppSpacing.field),
            const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ],
          const SizedBox(height: AppSpacing.field),
        ],
      ),
    );
  }
}
