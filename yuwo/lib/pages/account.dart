import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'home.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
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

  @override
  void dispose() {
    for (final c in [email, password, phonenumber, first, last, username]) {
      c.dispose();
    }
    super.dispose();
  }

  // Same rule the original fields used.
  String? _validate(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter password';
    }
    final passReg = RegExp(
      r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&])[A-Za-z\d@$!%*?&]{8,}$',
    );
    if (!passReg.hasMatch(value)) {
      return 'Please enter valid password structure';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: AppSpacing.field);
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.page,
            vertical: 56,
          ),
          child: CenteredContent(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Yuwo', style: AppText.brandLarge),
                const SizedBox(height: AppSpacing.section),
                Text('Lets create an account', style: AppText.pageTitle),
                const SizedBox(height: 4),
                Text(
                  'Split, send and settle up with friends',
                  style: AppText.body.copyWith(color: AppColors.hint),
                ),
                const SizedBox(height: AppSpacing.gap),
                AppCard(
                  child: Form(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SectionHeader(
                          'Your Details',
                          subtitle: 'This is how friends will find you',
                        ),
                        const SizedBox(height: AppSpacing.gap),
                        Row(
                          children: [
                            //FIRST NAME
                            Expanded(
                              child: TextFormField(
                                controller: first,
                                decoration: const InputDecoration(
                                  hintText: 'First Name',
                                ),
                                validator: _validate,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.field),
                            //LAST NAME
                            Expanded(
                              child: TextFormField(
                                controller: last,
                                decoration: const InputDecoration(
                                  hintText: 'Last Name',
                                ),
                                validator: _validate,
                              ),
                            ),
                          ],
                        ),
                        gap,
                        //USERNAME
                        TextFormField(
                          controller: username,
                          decoration: const InputDecoration(
                            hintText: 'Username',
                            prefixIcon: Icon(Icons.alternate_email),
                          ),
                          //COMEBACK FIX
                          validator: _validate,
                        ),
                        gap,
                        //EMAIL
                        TextFormField(
                          controller: email,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            hintText: 'Email',
                            prefixIcon: Icon(Icons.mail_outline),
                          ),
                          //COMEBACK FIX
                          validator: _validate,
                        ),
                        gap,
                        //PHONE NUMBER
                        TextFormField(
                          controller: phonenumber,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            hintText: 'Phone Number',
                            prefixIcon: Icon(Icons.phone_outlined),
                          ),
                          validator: _validate,
                        ),
                        gap,
                        //PASSWORD
                        TextFormField(
                          obscureText: !isVisible,
                          controller: password,
                          decoration: InputDecoration(
                            hintText: 'Password',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(
                                isVisible
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                              ),
                              onPressed: () =>
                                  setState(() => isVisible = !isVisible),
                            ),
                          ),
                          validator: _validate,
                        ),
                        const SizedBox(height: AppSpacing.gap),
                        //Create Account
                        ElevatedButton(
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
                          child: const Text('Create Account'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
