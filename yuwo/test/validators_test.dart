import 'package:flutter_test/flutter_test.dart';
import 'package:yuwo/utils/validators.dart';

void main() {
  test('accepts iOS suggested and password-manager passwords', () {
    for (final password in [
      'Fexkut-3pyxco-dobqib', // iOS "Strong Password" style
      'Yuwo-test-2026',
      'Secret1!',
      'A1b2c3d4#e',
      'Correct Horse 9 battery',
    ]) {
      expect(Validators.newPassword(password), isNull, reason: password);
    }
  });

  test('still needs length, both cases, a number and a symbol', () {
    for (final password in [
      'Sh0rt!',
      'alllower1!',
      'ALLUPPER1!',
      'NoNumbers!',
      'NoSymbols123',
    ]) {
      expect(Validators.newPassword(password), isNotNull, reason: password);
    }
  });
}
