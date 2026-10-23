/// Money is always handled as integer cents, matching the backend.
abstract final class Money {
  static String format(int cents) {
    final sign = cents < 0 ? '-' : '';
    final abs = cents.abs();
    return '$sign\$${abs ~/ 100}.${(abs % 100).toString().padLeft(2, '0')}';
  }

  /// Parses user input like "12", "12.5" or "\$12.50". Returns null if invalid.
  static int? parse(String input) {
    final text = input.trim().replaceAll(r'$', '').replaceAll(',', '');
    final match = RegExp(r'^(\d{1,7})(?:\.(\d{0,2}))?$').firstMatch(text);
    if (match == null) return null;
    final cents = (match.group(2) ?? '').padRight(2, '0');
    return int.parse(match.group(1)!) * 100 + int.parse(cents);
  }
}
