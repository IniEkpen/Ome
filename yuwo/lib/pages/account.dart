import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'home.dart';
import 'dart:convert';

typedef NativeCallbackSignature = void Function(int eventId);
typedef TEC = TextEditingController;

Future<bool?> createAccount(
  TEC email,
  TEC phonenumber,
  TEC password,
  TEC username,
) async {
  const url = 'https://ome-o9wx.onrender.com/users/createaccount';
  String userId = "12345";
  final uri = Uri.parse('$url/$userId');
  try {
    final http.Response postResponse = await http.post(
      uri,
      headers: {'Content-Type': 'application/json; charset=UTF-8'},
      //add to the profile from backend to the body
      body: jsonEncode({
        'username': username.text,
        'email': email.text,
        'phone': phonenumber.text,
        'password': password.text,
        'stripe_customer_id': '14242q5qts',
      }),
    );
    if (postResponse.statusCode == 204) {
      debugPrint('Post Success');
      return true;
    } else {
      debugPrint('Unsuccesfull post');
      return false;
    }
  } catch (error) {
    debugPrint('One of them errored');
    rethrow;
  }
}

class Account extends StatefulWidget {
  const Account({super.key});
  @override
  State<Account> createState() => _Accounting();
}

class _Accounting extends State<Account> {
  final TEC email = TEC();
  final TEC password = TEC();
  final TEC phonenumber = TEC();
  final TEC first = TEC();
  final TEC last = TEC();
  final TEC username = TEC();
  bool isVisible = false;
  Icon passwordEye = Icon(Icons.visibility_off);
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.only(top: 56, bottom: 46, left: 46, right: 46),
          child: Column(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  /*Image(
                    height: 150,
                    image: AssetImage(),

                ),*/
                  Text("Lets create an account"),
                  //add space between text
                  const SizedBox(height: 16),
                  Form(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32.0),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              //FIRST NAME
                              Expanded(
                                child: TextFormField(
                                  controller: first,
                                  decoration: InputDecoration(
                                    hintText: "First Name",
                                    hintStyle: TextStyle(color: Colors.grey),
                                  ),
                                  validator: (email) {
                                    if (email == null || email.isEmpty) {
                                      return 'Please enter password';
                                    }
                                    final passReg = RegExp(
                                      r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&])[A-Za-z\d@$!%*?&]{8,}$',
                                    );
                                    if (!passReg.hasMatch(email)) {
                                      return 'Please enter valid password structure';
                                    }
                                    return null;
                                  },
                                ),
                              ),

                              //LAST NAME
                              Expanded(
                                child: TextFormField(
                                  controller: last,
                                  decoration: InputDecoration(
                                    hintText: "Last Name",
                                    hintStyle: TextStyle(color: Colors.grey),
                                  ),
                                  validator: (last) {
                                    if (last == null || last.isEmpty) {
                                      return 'Please enter password';
                                    }
                                    final passReg = RegExp(
                                      r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&])[A-Za-z\d@$!%*?&]{8,}$',
                                    );
                                    if (!passReg.hasMatch(last)) {
                                      return 'Please enter valid password structure';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                            ],
                          ),
                          //USERNAME
                          TextFormField(
                            controller: username,
                            decoration: InputDecoration(
                              hintText: "Username",
                              hintStyle: TextStyle(color: Colors.grey),
                            ),
                            //COMEBACK FIX
                            validator: (username) {
                              if (username == null || username.isEmpty) {
                                return 'Please enter password';
                              }
                              final passReg = RegExp(
                                r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&])[A-Za-z\d@$!%*?&]{8,}$',
                              );
                              if (!passReg.hasMatch(username)) {
                                return 'Please enter valid password structure';
                              }
                              return null;
                            },
                          ),
                          //EMAIL
                          TextFormField(
                            controller: email,
                            keyboardType: TextInputType.emailAddress,
                            decoration: InputDecoration(
                              hintText: "Email",
                              hintStyle: TextStyle(color: Colors.grey),
                            ),
                            //COMEBACK FIX
                            validator: (email) {
                              if (email == null || email.isEmpty) {
                                return 'Please enter password';
                              }
                              final passReg = RegExp(
                                r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&])[A-Za-z\d@$!%*?&]{8,}$',
                              );
                              if (!passReg.hasMatch(email)) {
                                return 'Please enter valid password structure';
                              }
                              return null;
                            },
                          ),

                          //PHONE NUMBER
                          TextFormField(
                            controller: phonenumber,
                            keyboardType: TextInputType.phone,
                            decoration: InputDecoration(
                              hintText: "Phone Number",
                              hintStyle: TextStyle(color: Colors.grey),
                            ),
                            validator: (phonenumber) {
                              if (phonenumber == null || phonenumber.isEmpty) {
                                return 'Please enter password';
                              }
                              final passReg = RegExp(
                                r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&])[A-Za-z\d@$!%*?&]{8,}$',
                              );
                              if (!passReg.hasMatch(phonenumber)) {
                                return 'Please enter valid password structure';
                              }
                              return null;
                            },
                          ),
                          //PASSWORD
                          TextFormField(
                            obscureText: isVisible ? false : true,
                            controller: password,
                            decoration: InputDecoration(
                              hintText: "Password",
                              hintStyle: TextStyle(color: Colors.grey),
                              suffixIcon: IconButton(
                                icon: passwordEye,
                                onPressed: () {
                                  setState(() {
                                    isVisible = !isVisible;
                                    if (isVisible) {
                                      passwordEye = Icon(Icons.visibility);
                                    } else {
                                      passwordEye = Icon(Icons.visibility);
                                    }
                                  });
                                },
                              ),
                            ),
                            validator: (password) {
                              if (password == null || password.isEmpty) {
                                return 'Please enter password';
                              }
                              final passReg = RegExp(
                                r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&])[A-Za-z\d@$!%*?&]{8,}$',
                              );
                              if (!passReg.hasMatch(password)) {
                                return 'Please enter valid password structure';
                              }
                              return null;
                            },
                          ),

                          const SizedBox(height: 16),
                          //Create Account
                          SizedBox(
                            child: ElevatedButton(
                              onPressed: () async {
                                final account = await createAccount(
                                  email,
                                  phonenumber,
                                  password,
                                  username,
                                );
                                if (account != null && account == true) {
                                  if (context.mounted) {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            const MyHomePage(title: 'Yuwo'),
                                      ),
                                    );
                                  }
                                }
                              },
                              child: Text("Create Account"),
                            ),
                          ),

                          Row(
                            children: [
                              Divider(
                                color: Colors.grey,
                                thickness: 0.5,
                                indent: 60,
                                endIndent: 5,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
