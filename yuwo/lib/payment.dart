import 'package:flutter/material.dart';
import 'package:flutter_stripe_connect/flutter_stripe_connect.dart';

import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'services/payment_service.dart';

/// Payment verification: Stripe Connect onboarding. Anyone can host a bill,
/// so everyone completes it before creating or joining a group; it's how the
/// money members pay a host reaches the host's bank. Stripe's embedded
/// component runs inside the app (no browser); users come back here to update
/// details or bank accounts. The client secret comes from our server; only
/// the publishable key lives in the app.
class Pay extends StatefulWidget {
  const Pay({super.key});
  @override
  State<Pay> createState() => _Payment();
}

class _Payment extends State<Pay> {
  bool _isStripeReady = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    setupStripe();
  }

  Future<void> setupStripe() async {
    await StripeConfig.ready();
    if (!mounted) return;
    if (!StripeConfig.isConfigured) {
      setState(
        () =>
            _error = "Payment verification isn't available in this build yet.",
      );
      return;
    }
    final payments = PaymentService(AuthScope.read(context));
    try {
      await StripeConnect.instance.initialize(
        publishableKey: StripeConfig.publishableKey,
        clientSecretProvider: payments.connectOnboardingSecret,
      );
      // Checks if the screen is still active before updating UI
      if (mounted) setState(() => _isStripeReady = true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = "Couldn't start payment verification.");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Payment verification')),
      body: _error != null
          ? Center(child: Text(_error!))
          : !_isStripeReady
          ? const Center(child: CircularProgressIndicator())
          : StripeAccountOnboarding(
              onLoaded: () => debugPrint('Onboarding loaded'),
              onLoadError: (error) {
                if (mounted) {
                  setState(
                    () => _error = "Couldn't load payment verification.",
                  );
                }
              },
              // Finished or closed onboarding; whoever opened this screen
              // reloads the verification status when it closes.
              onExit: () {
                if (mounted) Navigator.of(context).maybePop();
              },
            ),
    );
  }
}
