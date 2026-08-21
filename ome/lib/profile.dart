import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:logger/logger.dart';
import 'account.dart';



/*void handleLoginCallback(int statusCode) {
  Logger log = Logger();
  if (statusCode == 200) {
    log.d("Dart received: Login was successful native-side!");
  } else {
    log.d("Dart received: Login failed with code $statusCode");
  }
}







final callback = NativeCallable<Void Function(Int32)>.isolateLocal(handleLoginCallback);
*/



Future<bool?> fetchLogin() async{
  debugPrint("CHICKEN");
   const url = 'https://ome-o9wx.onrender.com/users/signin';
    String userId = "12345";
    final uri = Uri.parse('$url/$userId');
    try{
      final http.Response postResponse = await http.post(uri,
      headers: {'Content-Type':'application/json; charset=UTF-8'},
      body:jsonEncode({'username':'zeus'}));
      debugPrint("CHICKEN");
      if (postResponse.statusCode == 200 ||postResponse.statusCode == 201){
        debugPrint('Post Success');
        final data =jsonDecode(postResponse.body);
        final bool userExistsStatus = data['UserExists'];
        debugPrint(userExistsStatus.toString());
        return(userExistsStatus);
        
      }
      else{
        debugPrint('Unsuccesfull post');
        return null;
       
      }
     
    }catch(error){
      debugPrint('Something went wrong');
      return null;
    }


}


/*void main() {
  // Tells Flutter to prepare its internal engine bindings
  WidgetsFlutterBinding.ensureInitialized();
 
  // Launch a real UI window framework so the app doesn't instantly close
  runApp(const MaterialApp(
    home: Scaffold(
      body: Center(child: Text('App Running')),
    ),
  ));
 
  // Now you can safely fire your async function in the background!
  fetchLogin();
}
 */









Future<void> goAccount(BuildContext context) async {
   debugPrint('fetching data');
   final bool? data = await fetchLogin();
   if (data == false){
    if(context.mounted){
      Navigator.push(context, MaterialPageRoute(builder: (context)=> const Account()));


    }
    else{
      debugPrint('clicked off page');
    }
   }
   if (data == true) {
    debugPrint("userExists Login successful");
    //later change to where it actually opens rest of pages
    return;

   }
   else{
    debugPrint("error happened didnt print result");
    return;
   }
 
}

class Profile extends StatefulWidget{
  const Profile({super.key});
  @override
  State<Profile> createState()=> _Profiling();
}






class _Profiling extends State<Profile>{
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
