import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

Future<Map<String, dynamic>?> createGroup() async {
  
   const url = 'https://ome-o9wx.onrender.com/users/group/payment';
   String userId = "12345";
   final uri = Uri.parse('$url/$userId');
  try{
      final http.Response payment = await http.post(uri,
      headers: {'Content-Type':'application/json; charset=UTF-8'},
      //add to the profile from backend to the body
       body:jsonEncode({'username':'george'}));
       //check if payment info has been added
       debugPrint("chicken");
      if (payment.statusCode==200){
        final data =jsonDecode(payment.body);
        final bool paycred = data['CardFilled'];
        debugPrint(paycred.toString());
        //also have to check if it works when info is filled out 
        if (paycred){
          debugPrint("it worked,yureka");
          /* this is where I tested up to before*/

          const url = 'https://ome-o9wx.onrender.com/users/group/create';
          String userId = "12345";
          final uri = Uri.parse('$url/$userId');
          final http.Response postResponse = await http.post(uri,
          headers: {'Content-Type':'application/json; charset=UTF-8'},
          //add to the profile from backend to the body
          body:jsonEncode({'username':'george', 
                          'groupName': 'Vacay',
                          'userList' : ['john', 'jason'],
          }));

          //check if group has been created and users has been added 
          if (postResponse.statusCode==200 || postResponse.statusCode ==201){
              debugPrint("entered the function");
              final group = jsonDecode(postResponse.body);
              debugPrint(group.toString());
              final bool created = group['Group Created'];
              debugPrint(created.toString());
              if (created){
                debugPrint("ENTERED CREATED");
                final Map<String, dynamic> addUsers = group['Users Added'];
                debugPrint(addUsers.toString());
                /*more neat we can get right a loop in button or other function logic that checks if all
                listed usernames could be added*/
                return addUsers;

              }
              else{
                debugPrint("GROUP WASNT CREATED");
                return null;
              }
              
          }
          else{
            debugPrint("unable to see if group was created and users were added");
            return null;
          }
        }
        return null;
      }
      else{
        //navigate to payment page
       /* if(context.mounted){
          Navigator.push(context, MaterialPageRoute(builder: (context)=> const Pay()));
          }
        */
        return null;
        
        }
      
      
    }catch(paymentError){
      debugPrint('unable to get payment info');
      return null;
    }
}

Future <void> deleteGroup() async {
  const url = 'https://ome-o9wx.onrender.com/users/group/deletegroup';
  String userId = "12345";
  final uri = Uri.parse('$url/$userId');
  try{
    //initial are you sure message   
    final http.Response delete = await http.get(uri);
    if (delete.statusCode == 200){
      
      final http.Response deleteChoice = await http.post(uri,
      headers: {'Content-Type':'application/json; charset=UTF-8'},
      //add to the profile from backend to the body
      body:jsonEncode({'username':'george', 'groupname': 'Vacay', 'choice': 'no'}));
        if (delete.statusCode== 200){
          final data = jsonDecode(deleteChoice.body);
          final bool choice = data['choice'];
          if (choice){
            debugPrint('info was deleted');
          }
          else{
            //if then 
            debugPrint('user choice not to delete data');
          }
        }
       else{
        debugPrint("unable to get response");
       }
    }
    

    
  }catch(delete){
    debugPrint("unable to print info");
  }
}
  
Future<void> deleteuserfromGroup() async{

}



class Group extends StatefulWidget{
  const Group({super.key});
  @override
  State<Group> createState()=> _Grouping();


}

class _Grouping extends State<Group>{
  @override
  Widget build(BuildContext context){
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(AppSpacing.page),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text("Yuwo", style: AppText.brand),
                  const SizedBox(height: AppSpacing.field),
                  Text("Login", style: AppText.pageTitle),
                  Text("Welcome Back ", style: AppText.caption),
                ],
              ),
            ),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.page, 40, AppSpacing.page, AppSpacing.page,
                ),
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(60),
                    topRight: Radius.circular(60),
                  ),
                ),
                child: CenteredContent(
                  child: Column(
                    children: const <Widget>[
                      TextField(
                        decoration: InputDecoration(
                          hintText: "Username",
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                      ),
                      SizedBox(height: AppSpacing.field),
                      TextField(
                        obscureText: true,
                        decoration: InputDecoration(
                          hintText: "password",
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
