import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'networkmap.dart';
import 'preview_network.dart';
import 'routes.dart';
import 'services/auth_service.dart';
import 'services/payment_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Uses --dart-define=STRIPE_PUBLISHABLE_KEY=pk_... if given, otherwise
  // loads the key from the server in the background.
  await StripeConfig.init();

  // The full app (sign-in, groups, bill splitting) is the default. To open
  // the network map preview on its own instead:
  //   flutter run --dart-define=PREVIEW=network
  if (const String.fromEnvironment('PREVIEW') == 'network') {
    // The signed-in app has the live map in its Network tab. This standalone
    // preview has no session, so it uses sample data.
    runApp(
      MaterialApp(
        theme: AppTheme.light,
        home: Network(viewerId: 'me', repository: FakeNetworkRepository()),
      ),
    );
    return;
  }

  // Signed-in users stay signed in across launches.
  final auth = AuthService(store: const SessionStore());
  await auth.restore();
  runApp(YuwoApp(auth: auth));
}

/// Full app with sign-in, routes and the Home / Groups / Network / Profile shell.
class YuwoApp extends StatelessWidget {
  const YuwoApp({super.key, required this.auth});

  final AuthService auth;

  @override
  Widget build(BuildContext context) {
    return AuthScope(
      service: auth,
      child: MaterialApp(
        title: 'Yuwo',
        theme: AppTheme.light,
        debugShowCheckedModeBanner: false,
        initialRoute: AppRoutes.root,
        onGenerateRoute: (settings) =>
            AppRoutes.onGenerateRoute(settings, auth),
        scrollBehavior: const MaterialScrollBehavior().copyWith(
          dragDevices: {
            PointerDeviceKind.touch,
            PointerDeviceKind.mouse,
            PointerDeviceKind.trackpad,
          },
        ),
      ),
    );
  }
}
