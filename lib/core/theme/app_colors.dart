import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Brand
  static const primary = Color(0xFF1565C0);     // Microsalt blue
  static const secondary = Color(0xFF00897B);    // Teal accent

  // Status
  static const success = Color(0xFF4CAF50);
  static const warning = Color(0xFFFFA726);
  static const error = Color(0xFFE53935);
  static const info = Color(0xFF42A5F5);

  // Crystal overlays
  static const crystalModel = Color(0xFF9EC4D5);       // Light blue — auto detection (matches report)
  static const crystalHuman = Color(0xFF2979FF);        // Blue — operator annotation
  static const crystalDiscarded = Color(0x80F44336);    // Semi-transparent red
  static const crystalSelected = Color(0xFFFFD600);     // Yellow — selected

  // Processing status
  static const statusPending = Color(0xFF9E9E9E);
  static const statusProcessing = Color(0xFFFFA726);
  static const statusComplete = Color(0xFF4CAF50);
  static const statusFailed = Color(0xFFE53935);
}
