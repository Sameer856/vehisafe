import 'package:flutter/material.dart';

class AppColors {
  // Brand Colors
  static const Color brandPrimary = Color(0xfff4c300); // Yellow #f4c300
  static const Color brandSecondary = Color(0xffd4a700); // Darker yellow/gold
  
  // Alert Severity Colors
  static const Color severityLow = Color(0xff4CAF50);    // Green
  static const Color severityMedium = Color(0xffFF9800); // Amber
  static const Color severityHigh = Color(0xffF44336);   // Red
  
  // Dark Theme Colors (Remapped to White/Yellow to prevent background clashing in views)
  static const Color darkBackground = Color(0xffFFFFFF);  // White background
  static const Color darkSurface = Color(0xffF8FAFC);     // Light gray surface
  static const Color darkCardBg = Color(0xffF1F5F9);      // Slightly darker light gray
  static const Color darkTextPrimary = Color(0xff0F172A);  // Slate-black
  static const Color darkTextSecondary = Color(0xff64748B); // Slate-gray
  static const Color darkDivider = Color(0xffE2E8F0);     // Light divider
  
  // Light Theme Colors
  static const Color lightBackground = Color(0xffFFFFFF);
  static const Color lightSurface = Color(0xffF8FAFC);
  static const Color lightCardBg = Color(0xffF1F5F9);
  static const Color lightTextPrimary = Color(0xff0F172A);
  static const Color lightTextSecondary = Color(0xff64748B);
  static const Color lightDivider = Color(0xffE2E8F0);
  
  // Status Colors
  static const Color statusConnected = Color(0xff4CAF50);
  static const Color statusStandby = Color(0xfff4c300);
  static const Color statusDisconnected = Color(0xff9E9E9E);
  
  // Gradients
  static const LinearGradient brandGradient = LinearGradient(
    colors: [Color(0xfff4c300), Color(0xffFFD54F)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient emergencyGradient = LinearGradient(
    colors: [Color(0xffD32F2F), Color(0xffC62828)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
