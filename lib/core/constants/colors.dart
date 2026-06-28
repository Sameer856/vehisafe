import 'package:flutter/material.dart';

class AppColors {
  // Brand Colors
  static const Color brandPrimary = Color(0xff1565C0); // Deep Blue
  static const Color brandSecondary = Color(0xff0D47A1);
  
  // Alert Severity Colors
  static const Color severityLow = Color(0xff4CAF50);    // Green
  static const Color severityMedium = Color(0xffFF9800); // Amber
  static const Color severityHigh = Color(0xffF44336);   // Red
  
  // Dark Theme Colors
  static const Color darkBackground = Color(0xff0A0E17);  // Sleek space black
  static const Color darkSurface = Color(0xff151C2C);     // Glassmorphism card base
  static const Color darkCardBg = Color(0xff1C263B);      // Lighter card base
  static const Color darkTextPrimary = Color(0xffF1F5F9);
  static const Color darkTextSecondary = Color(0xff94A3B8);
  static const Color darkDivider = Color(0xff2E3A52);
  
  // Light Theme Colors
  static const Color lightBackground = Color(0xffF8FAFC);
  static const Color lightSurface = Color(0xffFFFFFF);
  static const Color lightCardBg = Color(0xffF1F5F9);
  static const Color lightTextPrimary = Color(0xff0F172A);
  static const Color lightTextSecondary = Color(0xff64748B);
  static const Color lightDivider = Color(0xffE2E8F0);
  
  // Status Colors
  static const Color statusConnected = Color(0xff4CAF50);
  static const Color statusStandby = Color(0xffFFEB3B);
  static const Color statusDisconnected = Color(0xff9E9E9E);
  
  // Gradients
  static const LinearGradient brandGradient = LinearGradient(
    colors: [Color(0xff1E3A8A), Color(0xff1565C0)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient emergencyGradient = LinearGradient(
    colors: [Color(0xffD32F2F), Color(0xffC62828)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
