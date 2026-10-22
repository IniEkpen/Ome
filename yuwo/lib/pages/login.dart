import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'account.dart';
import 'home.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

typedef TEC = TextEditingController;

//CHANGE TO CHECK WHETHER ACOUNT EXISTS OR USERNAME EXISTS
//INCORRECT PASSWORD

Future<bool?> _fetchLogin(TEC username, TEC password) async {
  // debugPrint("CHICKEN");
  // debugPrint(username.text);
  // debugPrint(password.text);
  const url = 'https://yuwo.onrender.com/users/signin';
  String userId = "12345";
  final uri = Uri.parse('$url/$userId');

  try {
    final http.Response postResponse = await http.post(
      uri,
      headers: {'Content-Type': 'application/json; charset=UTF-8'},
      body: jsonEncode({'username': username.text}),
    );
    debugPrint("CHICKEN");
    if (postResponse.statusCode == 200 || postResponse.statusCode == 201) {
      debugPrint('Post Success');
      final data = jsonDecode(postResponse.body);
      final bool userExistsStatus = data['UserExists'];
      debugPrint(userExistsStatus.toString());
      return (userExistsStatus);
    } else {
      debugPrint('Unsuccesfull post');
      return null;
    }
  } catch (error) {
    debugPrint('Something went wrong');
    return null;
  }
}

Future<void> _goAccount(
  BuildContext context,
  TEC username,
  TEC password,
) async {
  // debugPrint('fetching data');
  final bool? data = await _fetchLogin(username, password);
  if (data == false) {
    if (context.mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const Account()),
      );
    } else {
      debugPrint('clicked off page');
    }
  }
  if (data == true) {
    debugPrint("userExists Login successful");
    //later change to where it actually opens rest of pages
    //opens to homepage
    return;
  } else {
    debugPrint("error happened didnt print result");
    return;
  }
}

class Profile extends StatefulWidget {
  const Profile({super.key});
  @override
  State<Profile> createState() => _Profiling();
}

class _Profiling extends State<Profile> {
  final TEC username = TEC();
  final TEC password = TEC();
  bool isVisible = false;
  bool rememberMe = true;

  @override
  void dispose() {
    username.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                Text('Welcome Back', style: AppText.pageTitle),
                const SizedBox(height: 4),
                Text(
                  'Change the way you handle money',
                  style: AppText.body.copyWith(color: AppColors.hint),
                ),
                const SizedBox(height: AppSpacing.gap),
                AppCard(
                  child: Form(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SectionHeader(
                          'Sign In',
                          subtitle: 'Use your Yuwo username and password',
                        ),
                        const SizedBox(height: AppSpacing.gap),
                        TextFormField(
                          controller: username,
                          decoration: const InputDecoration(
                            hintText: 'Username',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.field),
                        TextFormField(
                          controller: password,
                          obscureText: !isVisible,
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
                        const SizedBox(height: 4),
                        //Remember password
                        Row(
                          children: [
                            Checkbox(
                              value: rememberMe,
                              onChanged: (value) =>
                                  setState(() => rememberMe = value ?? false),
                            ),
                            Text('Remember Me', style: AppText.sectionTitle),
                            const Spacer(),
                            TextButton(
                              onPressed: () {},
                              child: const Text('Forgot Password'),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.field),
                        //Login
                        ElevatedButton(
                          onPressed: () async {
                            final check = await _fetchLogin(username, password);
                            if (context.mounted) {
                              if (check != null && check == true) {
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const MyHomePage(title: 'Yuwo'),
                                  ),
                                );
                              }
                            }
                          },
                          child: const Text('Login'),
                        ),
                        const SizedBox(height: AppSpacing.field),
                        const _OrDivider(),
                        const SizedBox(height: AppSpacing.field),
                        //Create Account
                        OutlinedButton(
                          onPressed: () {},
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

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider(color: AppColors.divider)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('OR', style: AppText.caption),
        ),
        const Expanded(child: Divider(color: AppColors.divider)),
      ],
    );
  }
}
