/// Form validators shared by the auth and group screens. Each returns an
/// error message, or null when the value is valid.
abstract final class Validators {
  static final _username = RegExp(r'^[A-Za-z0-9_.]{3,20}$');
  static final _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
  static final _phone = RegExp(r'^\+?[0-9]{7,15}$');
  static final _password = RegExp(
    r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&])[A-Za-z\d@$!%*?&]{8,64}$',
  );

  static String? required(String? value, String field) =>
      (value == null || value.trim().isEmpty) ? 'Please enter $field' : null;

  static String? name(String? value) {
    final missing = required(value, 'a name');
    if (missing != null) return missing;
    return value!.trim().length > 50 ? 'Name is too long' : null;
  }

  static String? username(String? value) {
    final missing = required(value, 'a username');
    if (missing != null) return missing;
    return _username.hasMatch(value!.trim())
        ? null
        : '3–20 letters, numbers, dots or underscores';
  }

  static String? email(String? value) {
    final missing = required(value, 'an email');
    if (missing != null) return missing;
    return _email.hasMatch(value!.trim()) ? null : 'Please enter a valid email';
  }

  static String? phone(String? value) {
    final missing = required(value, 'a phone number');
    if (missing != null) return missing;
    final digits = value!.replaceAll(RegExp(r'[\s\-()]'), '');
    return _phone.hasMatch(digits) ? null : 'Please enter a valid phone number';
  }

  static String? newPassword(String? value) {
    if (value == null || value.isEmpty) return 'Please enter a password';
    return _password.hasMatch(value)
        ? null
        : '8+ characters with upper, lower, number and symbol (@\$!%*?&)';
  }
}
