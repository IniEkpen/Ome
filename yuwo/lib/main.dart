import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/gestures.dart';

void main() {
  runApp(const MyApp());
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
      home: const MyHomePage(title: 'Yuwo'),
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        dragDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
        }
      )
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;

  void _incrementCounter() {
    setState(() {
      // This call to setState tells the Flutter framework that something has
      // changed in this State, which causes it to rerun the build method below
      // so that the display can reflect the updated values. If we changed
      // _counter without calling setState(), then the build method would not be
      // called again, and so nothing would appear to happen.
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // TRY THIS: Try changing the color here to a specific color (to
        // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
        // change color while the other colors stay the same.
        backgroundColor: const Color.fromARGB(255, 240, 240, 240),
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(
                  'Yuwo',
                  style: GoogleFonts.courgette(fontSize: 12, color: Colors.black,  fontWeight: FontWeight.bold)),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.notifications),
            onPressed: () {})
        ]
      ),
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
        child: Padding(
          padding: EdgeInsets.all(30.0),
          child: SingleChildScrollView(
            child: Column(
              // Column is also a layout widget. It takes a list of children and
              // arranges them vertically. By default, it sizes itself to fit its
              // children horizontally, and tries to be as tall as its parent.
              //
              // Column has various properties to control how it sizes itself and
              // how it positions its children. Here we use mainAxisAlignment to
              // center the children vertically; the main axis here is the vertical
              // axis because Columns are vertical (the cross axis would be
              // horizontal).
              //
              // TRY THIS: Invoke "debug painting" (choose the "Toggle Debug Paint"
              // action in the IDE, or press "p" in the console), to see the
              // wireframe for each widget.
              mainAxisAlignment: .start,
              crossAxisAlignment: .start,

              children: [
                Align(
                  alignment: Alignment.center,
                  child: Container(
                    height: 200,
                    width: 448,
                    decoration: BoxDecoration (
                      borderRadius: .circular(20),
                      color: Colors.white
                    ),
                    padding: EdgeInsets.all(24),
                    child: Align(
                      alignment: .topLeft,
                      child: Column(
                      crossAxisAlignment: .start,
                      children: [
                        Text('You Owe', style: GoogleFonts.spaceGrotesk(fontSize: 12, color: Colors.black, fontWeight: FontWeight.bold)),
                        Text('Amount Owed', style: GoogleFonts.spaceGrotesk(fontSize: 9, color: const Color.fromARGB(255, 199, 198, 198), fontWeight: FontWeight.bold)),
                        Text('\$$_counter', style: GoogleFonts.spaceGrotesk(fontSize: 50, color: Colors.black, fontWeight: FontWeight.bold))
                      ],),
                    ),
                  ),
                ),
                SizedBox(height: 50.0),
                Text(
                  'Splits to Complete',
                  style: GoogleFonts.spaceGrotesk(fontSize: 12, color: Colors.black, fontWeight: FontWeight.bold )),
                const SplitList(),
                SizedBox(height: 20.0),
                Text(
                  'Transactions',
                  style: GoogleFonts.spaceGrotesk(fontSize: 12, color: Colors.black,  fontWeight: FontWeight.bold)),
                const SplitList(),
              ],
            ),
          )
        ),
      ),

      backgroundColor: Color.fromARGB(255, 240, 240, 240),
      bottomNavigationBar: NavigationBar(destinations: const <Widget>[
        NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
        NavigationDestination(icon: Icon(Icons.explore), label:'Network'),
        NavigationDestination(icon: Icon(Icons.group), label:'Group'),
        NavigationDestination(icon: Icon(Icons.person), label:'Profile'),
      ],),
    ); 
  }
}

class SplitList extends StatefulWidget {
  const SplitList({super.key});

  @override
  State<SplitList> createState() => _SplitList();
}


class _SplitList extends State<SplitList> {
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView( 
      scrollDirection: Axis.horizontal,
      child: Row(
        spacing: 12.0,
        children: List.generate(10, (i) => const SplitItem()),
      )
      )
    );
  }
}


class SplitItem extends StatelessWidget {
  const SplitItem({super.key});
  
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Container(
        height: 112,
        width: 224,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color.fromARGB(255, 255, 255, 255),
          borderRadius: BorderRadius.circular(8.0)
        ),
      ),
    );
  }
}
