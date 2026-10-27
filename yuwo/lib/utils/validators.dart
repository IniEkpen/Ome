/// Form validators shared by the auth and group screens. Each returns an
/// error message, or null when the value is valid.
///
/// The new-account rules ([newUsername], [newPassword]) match the server's
/// (ome_backend/express/credentials.js); keep the two in step.
abstract final class Validators {
  // Any existing account, including ones made before the stricter rules.
  static final _username = RegExp(r'^[A-Za-z0-9_.]{3,30}$');
  static final _newUsername = RegExp(r'^[A-Za-z][A-Za-z0-9_.]{2,19}$');
  static const _reserved = {
    'admin', 'administrator', 'api', 'billing', 'help', 'me', 'mod', //
    'moderator', 'null', 'official', 'root', 'security', 'staff', //
    'support', 'system', 'undefined', 'yuwo', 'yuwoapp', 'yuwo_support',
  };
  static const _common = {
    'password', 'passw', 'pass', 'qwerty', 'qwertyuiop', 'asdf', 'asdfgh', //
    'zxcvbnm', 'letmein', 'welcome', 'iloveyou', 'admin', 'abc', 'abcd', //
    'abcdef', 'monkey', 'dragon', 'football', 'baseball', 'soccer', //
    'sunshine', 'princess', 'trustno', 'master', 'shadow', 'superman', //
    'batman', 'starwars', 'login', 'secret', 'changeme', 'hello', 'freedom',
    'whatever', 'yuwo', 'money',
  };
  static const _swaps = {
    '@': 'a', '4': 'a', '3': 'e', '1': 'i', '!': 'i', '0': 'o', r'$': 's', //
    '5': 's', '7': 't',
  };
  static final _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
  static final _phone = RegExp(r'^\+?[0-9]{7,15}$');
  // Any symbol counts, so iOS's suggested strong passwords (which use
  // hyphens) and password managers' generated ones are accepted.
  static final _password = RegExp(
    r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[^A-Za-z\d]).{8,128}$',
  );

  static String? required(String? value, String field) =>
      (value == null || value.trim().isEmpty) ? 'Please enter $field' : null;

  static String? name(String? value) {
    final missing = required(value, 'a name');
    if (missing != null) return missing;
    return value!.trim().length > 50 ? 'Name is too long' : null;
  }

  /// Someone else's username, e.g. when inviting people.
  static String? username(String? value) {
    final missing = required(value, 'a username');
    if (missing != null) return missing;
    return _username.hasMatch(value!.trim())
        ? null
        : 'Usernames are letters, numbers, dots or underscores';
  }

  /// A username for a new account.
  static String? newUsername(String? value) {
    final missing = required(value, 'a username');
    if (missing != null) return missing;
    final name = value!.trim();
    if (name.length < 3 || name.length > 20) {
      return 'Usernames are 3–20 characters';
    }
    if (!_newUsername.hasMatch(name)) {
      return 'Start with a letter; use letters, numbers, _ or .';
    }
    if (name.contains('..') || name.endsWith('.')) {
      return "Usernames can't have '..' or end with '.'";
    }
    final lower = name.toLowerCase();
    if (_reserved.contains(lower) || lower.startsWith('deleted_')) {
      return 'That username is reserved. Try another';
    }
    return null;
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

  /// A password for a new account. Pass the [username] and [email] being
  /// signed up with so the password can't contain them.
  static String? newPassword(String? value, {String? username, String? email}) {
    if (value == null || value.isEmpty) return 'Please enter a password';
    if (value.length > 128) return 'Use at most 128 characters';
    if (value != value.trim()) {
      return "Passwords can't start or end with a space";
    }
    if (!_password.hasMatch(value)) {
      return '8+ characters with upper and lower case, a number and a symbol';
    }
    final lower = value.toLowerCase();
    final personal = [username?.trim(), email?.trim().split('@').first]
        .whereType<String>()
        .where((part) => part.length >= 3)
        .map((part) => part.toLowerCase());
    if (personal.any(lower.contains)) {
      return "Your password can't contain your username or email";
    }
    if (_common.contains(_commonCore(lower))) {
      return 'That password is too easy to guess';
    }
    return null;
  }

  // "P@ssw0rd2026" -> "password": drop numbers and symbols at the ends,
  // undo common letter swaps, keep only the letters.
  static String _commonCore(String lowerPassword) => lowerPassword
      .replaceAll(RegExp(r'^[^a-z]+|[^a-z]+$'), '')
      .replaceAllMapped(RegExp(r'[@4310!$57]'), (m) => _swaps[m[0]]!)
      .replaceAll(RegExp('[^a-z]'), '');
}
