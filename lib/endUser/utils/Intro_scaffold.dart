import 'package:flutter/material.dart';
import 'package:yourpay/endUser/utils/design.dart';

class IntroScaffold extends StatelessWidget {
  const IntroScaffold({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey('intro'), // 👈 AnimatedSwitcher用
      backgroundColor: AppPalette.yellow,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.favorite, size: 48, color: AppPalette.black),
            const SizedBox(height: 16),
            Text(
              'loading',
              style: AppTypography.label(color: AppPalette.black),
            ),
            const SizedBox(height: 12),
            const CircularProgressIndicator(color: AppPalette.black),
          ],
        ),
      ),
    );
  }
}
