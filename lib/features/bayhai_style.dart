import 'package:flutter/material.dart';

abstract final class BayHaiStyle {
  static const navy = Color(0xff063d82);
  static const primary = Color(0xff0059cf);
  static const canvas = Color(0xfff4f7fb);
  static const ink = Color(0xff14243c);
  static const muted = Color(0xff4c607b);
  static const border = Color(0xffd6e0ef);
  static const blueTint = Color(0xffe6f0ff);
  static const green = Color(0xff007f62);
  static const orange = Color(0xffa35b00);
  static const purple = Color(0xff7141b7);
  static const red = Color(0xffbc2836);
  static const radius = 12.0;

  static ThemeData get theme {
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      primary: primary,
      onPrimary: Colors.white,
      surface: Colors.white,
      onSurface: ink,
      outline: border,
      error: red,
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
    );
    final field = OutlineInputBorder(
      borderRadius: BorderRadius.circular(radius),
      borderSide: const BorderSide(color: border),
    );
    return ThemeData(
      fontFamily: 'Roboto',
      visualDensity: VisualDensity.standard,
      dividerColor: BayHaiStyle.border,
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: canvas,
      appBarTheme: const AppBarTheme(
        backgroundColor: navy,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 4),
        shape: shape.copyWith(side: const BorderSide(color: border)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        border: field,
        enabledBorder: field,
        focusedBorder: field.copyWith(
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(shape: shape),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: shape,
          side: const BorderSide(color: border),
        ),
      ),
      chipTheme: const ChipThemeData(
        side: BorderSide(color: border),
        selectedColor: blueTint,
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: primary,
        unselectedLabelColor: muted,
        indicatorColor: primary,
        dividerColor: border,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        indicatorColor: blueTint,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected) ? primary : ink,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? primary : ink,
            size: 22,
          ),
        ),
      ),
    );
  }
}
