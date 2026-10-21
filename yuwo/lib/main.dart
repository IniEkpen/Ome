import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'routes.dart';
import 'services/auth_service.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(YuwoApp(auth: AuthService()));
}

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
