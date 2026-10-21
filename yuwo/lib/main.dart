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

void main() {
  runApp(MaterialApp(
    home:Network()
  ));
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
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: .fromSeed(seedColor: Colors.white),
      ),

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
