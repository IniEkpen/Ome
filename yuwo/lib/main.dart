import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
<<<<<<< HEAD
import 'package:yuwo/account.dart';
import 'login.dart';
import 'payment.dart';
import 'networkmap.dart';
import 'groups/grouplogic.dart';
import 'groups/groupdesign.dart';
=======
import 'pages/login.dart';
import 'pages/home.dart';
>>>>>>> dda7021bc84913b34ecea427bf4ac2877d4a41e5

import 'routes.dart';
import 'services/auth_service.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(MaterialApp(
    home:Network()
  ));
  /*Pay();*/
  /*createAccount();*/
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
