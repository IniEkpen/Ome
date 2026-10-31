import 'package:flutter/material.dart';

import 'networkmap.dart';
import 'pages/account.dart';
import 'pages/group.dart';
import 'pages/home.dart';
import 'pages/login.dart';
import 'pages/profile.dart';
import 'preview_network.dart';
import 'services/auth_service.dart';
import 'services/network_service.dart';

abstract final class AppRoutes {
  static const root = '/';
  static const signup = '/signup';

  /// Every named route is checked here. Signed-out users can only reach
  /// [signup]; anything else (including unknown names) lands on [AuthGate],
  /// which shows the login screen until there is a session.
  static Route<void> onGenerateRoute(RouteSettings settings, AuthService auth) {
    final Widget page = switch (settings.name) {
      signup when !auth.isAuthenticated => const CreateAccountPage(),
      _ => const AuthGate(),
    };
    return MaterialPageRoute(
      settings: RouteSettings(name: page is AuthGate ? root : settings.name),
      builder: (_) => page,
    );
  }
}

/// Root of the navigator. Rebuilds whenever auth state changes, so the app
/// shell only exists while signed in and logging out tears it down.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AuthScope.of(context);
    return auth.isAuthenticated ? const AppShell() : const LoginPage();
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selected = 0;

  static const _pages = <Widget>[
    HomeTab(),
    GroupsPage(),
    NetworkTab(),
    ProfilePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _selected, children: _pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selected,
        onTap: (index) => setState(() => _selected = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.group), label: 'Groups'),
          BottomNavigationBarItem(icon: Icon(Icons.hub), label: 'Network'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}

/// The network map for the signed-in user. Dev sessions the server didn't
/// issue a token for get sample data, like the home page.
class NetworkTab extends StatelessWidget {
  const NetworkTab({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AuthScope.of(context);
    final userId = auth.session?.userId;
    if (auth.session?.token == null || userId == null) {
      return Network(viewerId: 'me', repository: FakeNetworkRepository());
    }
    return Network(viewerId: '$userId', repository: ApiNetworkRepository(auth));
  }
}
