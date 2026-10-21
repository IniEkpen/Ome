import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'account.dart';
import 'main.dart';

typedef TEC = TextEditingController;

//CHANGE TO CHECK WHETHER ACOUNT EXISTS OR USERNAME EXISTS
//INCORRECT PASSWORD

Future<bool?> fetchLogin(TEC username, TEC password) async{
  debugPrint("CHICKEN");
  debugPrint(username.text);
  debugPrint(password.text);
   const url = 'https://yuwo.onrender.com/users/signin';
    String userId = "12345";
    final uri = Uri.parse('$url/$userId');
    try{
      final http.Response postResponse = await http.post(uri,
      headers: {'Content-Type':'application/json; charset=UTF-8'},
      body:jsonEncode({'username': username.text}));
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


Future<void> goAccount(BuildContext context, TEC username, TEC password) async {
   debugPrint('fetching data');
   final bool? data = await fetchLogin(username,password);
   /*if (data == false){
    
    if(context.mounted){
      Navigator.push(context, MaterialPageRoute(builder: (context)=> const Account()));


    }
    else{
      debugPrint('clicked off page');
    }
   }*/
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
  final TEC username = TEC();
  final TEC password = TEC();
  bool isVisible = false;
  Icon passwordEye = const Icon(Icons.visibility_off);
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
                      controller: username,
                      decoration:InputDecoration(
                      hintText: "Username",
                      hintStyle: TextStyle(color: Colors.grey)
                      )
                    ),

                    TextFormField(
                      controller: password,
                      obscureText:isVisible ?false:true ,
                      decoration:InputDecoration(
                      hintText: "Password",
                      hintStyle: TextStyle(color: Colors.grey),
                      suffixIcon: IconButton(icon:passwordEye,
                      onPressed: (){
                        setState(() {
                          isVisible = !isVisible;
                          if (isVisible){
                             passwordEye = Icon(Icons.visibility);
                          }
                          else{
                             passwordEye = Icon(Icons.visibility_off);
                          }
                        });
                      },)
                      ),
                      validator: (password) {
                        if(password==null || password.isEmpty){
                          return 'Please enter password';
                        }
                        final passReg = RegExp(r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&])[A-Za-z\d@$!%*?&]{8,}$');
                        if(!passReg.hasMatch(password)){
                          return 'Please enter valid password structure';
                        }
                        return null;
                      }
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
                  SizedBox(child: ElevatedButton(onPressed:() async {

                    final check = await fetchLogin(username, password);
                    if(context.mounted){
                      if(check != null && check==true){
                        Navigator.push(context,MaterialPageRoute(builder:(context)=> MyApp()),);
                      }
                    }

                  }, child: Text("Login"))),

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
