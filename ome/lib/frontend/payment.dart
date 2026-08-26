import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';


///will add payment soon to call in other functions needs to connect to 

Future<void> prelimIntegration() async{
  const url = 'https://ome-o9wx.onrender.com/create/stripe';
  String userId = "12345";
  final uri = Uri.parse('$url/$userId');
  try{
    final http.Response postResponse= await http.post(uri, 
     headers: {'Content-Type':'application/json; charset=UTF-8'},
      body:jsonEncode({'username':'john', 'email': 'john@gmail.com'}));
    }catch(error){
      debugPrint('');
    }
  }
  


class Pay extends StatefulWidget{
  const Pay({super.key});
  @override
  State<Pay> createState()=> _Payment();
}


class _Payment extends State<Pay> {
  @override
  Widget build(BuildContext context){
    return Scaffold(
      appBar: AppBar(
        title: Text('Payment Window')
      ),
      body :Column(
        children: <Widget>[
          TextField(
            decoration: InputDecoration(
              hintText: "Payment required"
            ),
          ),
          TextButton(
            onPressed: () {},
            child: Text("Submit")
          )
        ]
      )
    );




  }
   
 


}





