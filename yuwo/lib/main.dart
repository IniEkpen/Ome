import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'pages/login.dart';
import 'pages/home.dart';
import 'theme/app_theme.dart';

void main() {
  // Network needs a NetworkRepository implementation before it can run here:
  // runApp(MaterialApp(home: Network(repository: ..., viewerId: ...)));
  runApp(const MyApp());
  /*Pay();*/
  /*createAccount();*/
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Yuwo',
      theme: AppTheme.light,

      debugShowCheckedModeBanner: false,
      home: const HomeScreen(),
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        dragDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
        },
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreen();
}

class _HomeScreen extends State<HomeScreen> {
  final List<Widget> _pages = const <Widget>[
    Center(child: Profile()),
    Center(child: MyHomePage(title: 'Yuwo')),
  ];

  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_selected],
      bottomNavigationBar: (_selected != 0)
          ? BottomNavigationBar(
              currentIndex: _selected,
              onTap: (index) => setState(() {
                if (index != 0) _selected = index;
                return;
              }),
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
                BottomNavigationBarItem(
                  icon: Icon(Icons.search),
                  label: 'Search',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.person),
                  label: 'Person',
                ),
              ],
            )
          : const SizedBox.shrink(),
    );
  }
}
