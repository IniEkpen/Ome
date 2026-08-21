import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:ffi';

typedef NativeCallbackSignature = Void Function(Int32 eventId);

Future<void> createAccount() async{
   const url = 'https://ome-o9wx.onrender.com/users/createaccount';
    String userId = "12345";
    final uri = Uri.parse('$url/$userId');
    try{
      final http.Response postResponse = await http.post(uri,
      headers: {'Content-Type':'application/json; charset=UTF-8'},
      //add to the profile from backend to the body
      body:jsonEncode({'username':'jake',
            'email':'jake@gmail.com',
            'phone': '124324325',
            'password':'chickennugg',
            'stripe_customer_id':'14242q5qts'}));
      if (postResponse.statusCode == 204){
          debugPrint('Post Success');
      }
      else{
          debugPrint('Unsuccesfull post');
        }
      }catch(error){
      debugPrint('One of them errored');
    }

}

class Account extends StatefulWidget{
  const Account({super.key});
  @override
  State<Account> createState()=> _Accounting();

}



class _Accounting extends State<Account>{
  @override
  Widget build(BuildContext context){
     return Scaffold(
      body: Container(
        decoration: BoxDecoration(
        gradient: LinearGradient(
          colors:[
            Colors.red[900]!,
            Colors.red[800]!,
            Colors.red[400]!
          ] 
          ) 
          ),
          child: Column (
            children: <Widget> [
            Column(
          
              children: <Widget>[
                Text("Login",
                style:TextStyle(
                  color:Colors.white,
                  fontSize: 40
                )
                ),
                Text("Welcome Back ", 
                  style: TextStyle(
                  color: Colors.white,
                  fontSize: 20
                  )
                )
              ]
            ),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(topLeft: Radius.circular(60), topRight: Radius.circular(60))
                ),
              child: Column(
                children: <Widget> [
                  Container(
                    height: 100,
                    width: double.infinity,
                    transform: Matrix4.translationValues(0, 100, 0),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color:Colors.grey[200]!)) ,
                      color: Colors.white,
                      borderRadius: BorderRadius.only(topLeft: Radius.circular(10), topRight: Radius.circular(10), bottomLeft: Radius.circular(10), bottomRight: Radius.circular(10)  ),
                      boxShadow: [BoxShadow(
                        blurRadius:20,
                        color: Color.fromRGBO(255, 0, 0,3),
                        offset:Offset(0,10) 
                        )
                        ]
                    ),
                   
                    child:TextFormField(
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                      hintText: "Username",
                      hintStyle: TextStyle(color: Colors.grey)
                      )
                      
                    ),
                    
                  ),
                  Container(
                    height: 100,
                    width: double.infinity,
                    transform: Matrix4.translationValues(0, 110, 0),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color:Colors.grey[200]!)) ,
                      color: Colors.white,
                      borderRadius: BorderRadius.only(topLeft: Radius.circular(10), topRight: Radius.circular(10), bottomLeft: Radius.circular(10), bottomRight: Radius.circular(10)  ),
                      boxShadow: [BoxShadow(
                        blurRadius:20,
                        color: Color.fromRGBO(255, 0, 0,3),
                        offset:Offset(0,10) 
                        )
                        ]
                    ),
                   
                    child:TextFormField(
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                      hintText: "password",
                      hintStyle: TextStyle(color: Colors.grey)
                      )
                      
                    )
                  )

                ]
              )
              
              ),
              )
            
          ]
          )
          
          
        )
    );
  }

}



