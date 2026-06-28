import 'package:flutter/material.dart';
import '../constants/colors.dart';

class CustomPinPad extends StatelessWidget {
  final Function(String) onKeyPressed;
  final VoidCallback onDeletePressed;
  final VoidCallback? onBiometricPressed;
  final bool showBiometric;

  const CustomPinPad({
    super.key,
    required this.onKeyPressed,
    required this.onDeletePressed,
    this.onBiometricPressed,
    this.showBiometric = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var row in [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: row.map((val) => _buildNumberButton(context, val)).toList(),
            ),
          ),
        // Last row: Biometric (or empty), '0', Backspace
        Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              showBiometric && onBiometricPressed != null
                  ? _buildIconButton(
                      context,
                      Icons.fingerprint,
                      onBiometricPressed!,
                      color: AppColors.brandPrimary,
                    )
                  : const SizedBox(width: 80, height: 80),
              _buildNumberButton(context, '0'),
              _buildIconButton(
                context,
                Icons.backspace_outlined,
                onDeletePressed,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNumberButton(BuildContext context, String value) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: 80,
      height: 80,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      child: OutlinedButton(
        onPressed: () => onKeyPressed(value),
        style: OutlinedButton.styleFrom(
          shape: const CircleBorder(),
          side: BorderSide(
            color: isDark ? AppColors.darkDivider : AppColors.lightDivider,
            width: 1.5,
          ),
          backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
          foregroundColor: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
        ),
        child: Text(
          value,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildIconButton(
    BuildContext context,
    IconData icon,
    VoidCallback onPressed, {
    Color? color,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: 80,
      height: 80,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          shape: const CircleBorder(),
          side: BorderSide(
            color: isDark ? AppColors.darkDivider : AppColors.lightDivider,
            width: 1.5,
          ),
          backgroundColor: isDark ? AppColors.darkSurface.withValues(alpha: 0.5) : AppColors.lightSurface.withValues(alpha: 0.5),
          foregroundColor: color ?? (isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary),
        ),
        child: Icon(
          icon,
          size: 28,
        ),
      ),
    );
  }
}
