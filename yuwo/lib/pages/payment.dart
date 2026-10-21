/* import 'package:flutter/material.dart';
import 'package:flutter_stripe_connect/flutter_stripe_connect.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'main.dart';


///will add payment soon to call in other functions needs to connect to 

class Pay extends StatefulWidget{
  const Pay({super.key});
  @override
  State<Pay> createState()=> _Payment();
}


class _Payment extends State<Pay> {
  bool _isStripeReady = false;

  @override
  //make this is loaded in before it shows
  void initState(){
    super.initState();{
      setupStripe(context);
    }

  }
Future<void> setupStripe(BuildContext context) async{
  const url = 'https://ome-o9wx.onrender.com/create/stripe';
  String userId = "12345";
  final uri = Uri.parse('$url/$userId');
  try{
    final stripeConnect = await StripeConnect.instance.initialize(
      publishableKey:'',
      clientSecretProvider: () async{
      final http.Response postResponse= await http.post(uri,
      headers: {'Content-Type':'application/json; charset = UTF-8'},
      body: jsonEncode({'username': 'john', 'email': 'john@gmail.com'}));
      final data = jsonDecode(postResponse.body);
      final clientSecret = data['client_secret'];
      return clientSecret;
      }
    );
   if (context.mounted) { // Checks if the screen is still active before updating UI
      setState(() {
        _isStripeReady = true;
      });
   }
  }
    catch(error){
      debugPrint('');
    }
  }

  @override
  Widget build(BuildContext context){
    return Scaffold(
      appBar: AppBar(
        title: Text('Payment Window')
      ),
      body:StripeAccountOnboarding(
        onLoaded: ()=> ('Onboarding loaded'),
        onLoadError:(error)=>('Error')
      )
    );




  }
   
 


}


*/
