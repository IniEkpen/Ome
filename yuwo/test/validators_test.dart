import 'package:flutter_test/flutter_test.dart';
import 'package:yuwo/utils/validators.dart';

// Same cases as ome_backend/express/test/credentials.test.js, so the app
// and the server agree on what a valid new account looks like.
void main() {
  test('accepts ordinary new usernames', () {
    for (final name in [
      'ada',
      'Ada_Lovelace',
      'bob.smith',
      'cleo2026',
      'a' * 20,
    ]) {
      expect(Validators.newUsername(name), isNull, reason: name);
    }
  });

  test('rejects bad new usernames', () {
    for (final name in [
      '', 'ab', 'a' * 21, // length
      '1ada', '_ada', '.ada', 'ada smith', 'ada-smith', 'adá', 'ada@x', //
      'ada..smith', 'ada.', // typos
      'admin', 'Support', 'YUWO', 'deleted_5', 'Deleted_anything', // reserved
    ]) {
      expect(Validators.newUsername(name), isNotNull, reason: name);
    }
  });

  test('inviting still accepts older usernames the new rules would reject', () {
    expect(Validators.username('1ada'), isNull);
    expect(Validators.username('a' * 25), isNull);
    expect(Validators.username('ada smith'), isNotNull);
  });

  test('accepts strong passwords, including iOS suggested ones', () {
    for (final password in [
      'Fexkut-3pyxco-dobqib',
      'Correct Horse 9 battery',
      'Tr0ub4dor&3',
      'Yuwo-test-2026x',
    ]) {
      expect(
        Validators.newPassword(password, username: 'ada', email: 'ada@x.io'),
        isNull,
        reason: password,
      );
    }
  });

  test('rejects weak passwords', () {
    final cases = {
      'Sh0rt!': '8+ characters',
      'Aa1!${'x' * 130}': 'at most 128',
      ' Secret12!': 'space',
      'Secret12! ': 'space',
      'alllower1!': '8+ characters',
      'NoNumbers!': '8+ characters',
      'NoSymbols123': '8+ characters',
      'Password1!': 'too easy',
      'P@ssw0rd2026': 'too easy',
      r'Pa$$word1!': 'too easy',
      'Pass_word9!': 'too easy',
      'Qwerty123!': 'too easy',
      'Ada_lovelace1!': 'username or email',
      'xxADA_LOVELACE1!': 'username or email',
      'Cleo.Park99!': 'username or email',
    };
    cases.forEach((password, expected) {
      expect(
        Validators.newPassword(
          password,
          username: 'ada_lovelace',
          email: 'cleo.park@x.io',
        ),
        contains(expected),
        reason: password,
      );
    });
    expect(Validators.newPassword(''), 'Please enter a password');
  });
}
