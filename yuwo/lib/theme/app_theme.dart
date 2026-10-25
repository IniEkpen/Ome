import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens taken from the home page so every screen shares one look:
/// light grey canvas, white rounded cards, bold Space Grotesk text and a
/// Courgette wordmark.
abstract final class AppColors {
  static const background = Color.fromARGB(255, 240, 240, 240);
  static const surface = Colors.white;
  static const textPrimary = Colors.black;
  static const textMuted = Color.fromARGB(255, 199, 198, 198);
  static const hint = Color.fromARGB(255, 158, 158, 158);
  static const error = Color.fromARGB(255, 179, 38, 30);
  static const textSoft = Color.fromARGB(255, 28, 28, 30);
  static const divider = Color.fromARGB(255, 228, 228, 228);

  // Network map colours, matching the ones transactiongraph.dart assigns.
  static const viewer = Color(0xFF477ED5);
  static const contact = Color(0xFF52A98D);
  static const path = Color(0xFF16A085);
  static const private = Color(0xFF9D7BD8);

  // Joined group cards cycle through these, starting with the original orange.
  static const groupCards = <List<Color>>[
    [Color(0xFFFF9F43), Color(0xFFFF7A1A)],
    [Color(0xFF2D2D30), Color(0xFF000000)],
    [Color(0xFF52A98D), Color(0xFF16A085)],
    [Color(0xFF6C8FE0), Color(0xFF477ED5)],
    [Color(0xFFB59BE6), Color(0xFF9D7BD8)],
  ];
}

abstract final class AppRadius {
  static const double card = 20;
  static const double control = 12;
  static const double tile = 8;
}

/// Shadows that lift cards off the grey canvas: a tight contact shadow plus
/// a wide soft one, so boxes look raised rather than printed on the page.
abstract final class AppShadows {
  static const card = <BoxShadow>[
    BoxShadow(color: Color(0x0F000000), blurRadius: 3, offset: Offset(0, 1)),
    BoxShadow(
      color: Color(0x17000000),
      blurRadius: 24,
      spreadRadius: -2,
      offset: Offset(0, 10),
    ),
  ];

  /// For gradient and dark cards: a glow in the card's own colour reads as
  /// depth where a grey shadow would look muddy.
  static List<BoxShadow> tinted(Color color) => [
    const BoxShadow(
      color: Color(0x14000000),
      blurRadius: 4,
      offset: Offset(0, 2),
    ),
    BoxShadow(
      color: color.withValues(alpha: 0.35),
      blurRadius: 22,
      spreadRadius: -4,
      offset: const Offset(0, 12),
    ),
  ];
}

abstract final class AppSpacing {
  static const double page = 30;
  static const double section = 50;
  static const double gap = 20;
  static const double field = 12;

  /// Matches the width of the home page's balance card.
  static const double contentMaxWidth = 448;
}

abstract final class AppText {
  static TextStyle get brand => GoogleFonts.courgette(
    fontSize: 20,
    color: AppColors.textPrimary,
    fontWeight: FontWeight.bold,
  );

  static TextStyle get pageTitle => GoogleFonts.spaceGrotesk(
    fontSize: 28,
    color: AppColors.textPrimary,
    fontWeight: FontWeight.bold,
  );

  static TextStyle get sectionTitle => GoogleFonts.spaceGrotesk(
    fontSize: 12,
    color: AppColors.textPrimary,
    fontWeight: FontWeight.bold,
  );

  static TextStyle get caption => GoogleFonts.spaceGrotesk(
    fontSize: 9,
    color: AppColors.textMuted,
    fontWeight: FontWeight.bold,
  );

  static TextStyle get amount => GoogleFonts.spaceGrotesk(
    fontSize: 50,
    color: AppColors.textPrimary,
    fontWeight: FontWeight.bold,
  );

  static TextStyle get body =>
      GoogleFonts.spaceGrotesk(fontSize: 14, color: AppColors.textPrimary);

  static TextStyle get button =>
      GoogleFonts.spaceGrotesk(fontSize: 14, fontWeight: FontWeight.bold);
}

abstract final class AppTheme {
  static ThemeData get light {
    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.control),
    );
    OutlineInputBorder inputBorder([BorderSide side = BorderSide.none]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: side,
        );

    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.black,
        surface: AppColors.surface,
        error: AppColors.error,
      ),
      scaffoldBackgroundColor: AppColors.background,
      textTheme: GoogleFonts.spaceGroteskTextTheme(),
      appBarTheme: const AppBarThemeData(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: AppColors.background,
        hintStyle: GoogleFonts.spaceGrotesk(
          fontSize: 14,
          color: AppColors.hint,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: inputBorder(),
        enabledBorder: inputBorder(),
        focusedBorder: inputBorder(
          const BorderSide(color: AppColors.textPrimary, width: 1.5),
        ),
        errorBorder: inputBorder(const BorderSide(color: AppColors.error)),
        focusedErrorBorder: inputBorder(
          const BorderSide(color: AppColors.error, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.textPrimary,
          foregroundColor: AppColors.surface,
          disabledBackgroundColor: Colors.black38,
          disabledForegroundColor: Colors.white70,
          minimumSize: const Size.fromHeight(52),
          elevation: 3,
          shadowColor: Colors.black54,
          shape: controlShape,
          textStyle: AppText.button,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.textPrimary),
          minimumSize: const Size.fromHeight(52),
          shape: controlShape,
          textStyle: AppText.button,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          textStyle: AppText.sectionTitle,
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.surface,
        selectedItemColor: AppColors.textPrimary,
        unselectedItemColor: AppColors.hint,
        selectedLabelStyle: AppText.sectionTitle,
        unselectedLabelStyle: AppText.sectionTitle,
        type: BottomNavigationBarType.fixed,
        elevation: 12,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.textPrimary,
        contentTextStyle: AppText.body.copyWith(color: AppColors.surface),
        shape: controlShape,
      ),
    );
  }
}
