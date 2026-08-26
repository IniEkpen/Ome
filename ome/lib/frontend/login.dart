import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:logger/logger.dart';
import 'account.dart';


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
    //opens to homepage
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
      body: SingleChildScrollView(
        child: Padding(
          padding:EdgeInsets.only(
            top: 56,
            bottom:46,
            left:46,
            right:46 ) ,
          child:Column(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children:[
                  /*Image(
                    height: 150,
                    image: AssetImage(),

                ),*/
                Text("Welcome Back"),
                //add space between text
                const SizedBox(height: 16),
                Text("change the way you handle money"),

                Form(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical:32.0),
                  child: Column(
                  children: [
                    //email
                    TextFormField(
                      decoration:InputDecoration(
                      hintText: "Email",
                      hintStyle: TextStyle(color: Colors.grey)
                      )
                    ),

                    TextFormField(
                      decoration:InputDecoration(
                      hintText: "Password",
                      hintStyle: TextStyle(color: Colors.grey)
                      )
                    ), 
                    Row(
                       mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                      //Rememeber password
                    
                      Row(children: [
                        Checkbox(value: true, onChanged:(value){}),
                        Text("Remeber Me"),
                        TextButton(onPressed: (){},child:Text(
                          "Forgot Password"
                        ) )
                      ],
                    
                     ),

                    ],), 
                    const SizedBox(height:16),
                    //Login 
                  SizedBox(child: ElevatedButton(onPressed:(){}, child: Text("Login"))),

                    //Create Account
                  SizedBox(child: OutlinedButton(onPressed:(){}, child: Text("Create Account"))),

                    Row(children:[
                      Divider(color: Colors.grey,
                      thickness: 0.5, indent: 60, endIndent:5)
                    ])

                    

                    ],
                    ),
                  ),
                  )

                ]
               
              )
            ],))
      )

    );


  }
}
