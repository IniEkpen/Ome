import 'package:flutter/material.dart';
import 'login.dart';
import 'account.dart';
import 'group.dart';


void main() {
  runApp(const MaterialApp(
    home: Profile(),
  ));

   
    //deleteGroup();//
    //createGroup();//
    //fetchLogin();//
    //createAccount();//
}


class Home extends StatefulWidget{
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}


class _HomeState extends State<Home> {
  @override
  Widget build(BuildContext context) {
   return Scaffold(
      appBar: AppBar(
      backgroundColor: Colors.blue,
      title: Text('OME'),
      centerTitle: true,
    ),
   );
}
}
