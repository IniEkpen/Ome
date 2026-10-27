import 'package:flutter/widgets.dart';
import 'package:google_sign_in_web/web_only.dart' as web;

/// On the web, Google requires its own rendered button; the result arrives
/// on GoogleSignIn.instance.authenticationEvents.
Widget googleWebButton() => web.renderButton();
