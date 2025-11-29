import 'package:flutter/material.dart';
import 'package:yourpay/endUser/utils/design.dart';

/// 黄色×黒の大ボタン（色は任意で上書き可）
class YellowActionButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool loading;

  /// 背景色。未指定(null)なら AppPalette.yellow を使用
  final Color? color;

  const YellowActionButton({
    required this.label,
    this.icon,
    this.onPressed,
    this.color,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = color ?? AppPalette.yellow;
    final spinnerColor = bg.computeLuminance() < 0.5
        ? Colors.white
        : Colors.black;

    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppPalette.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: AppPalette.black,
                width: AppDims.border2,
              ),
            ),
            child: Icon(icon, color: AppPalette.black, size: 38),
          ),
          const SizedBox(width: 16),
        ],
        Text(label, style: AppTypography.label2(color: AppPalette.black)),
      ],
    );

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(AppDims.radius),
      child: InkWell(
        onTap: loading ? null : onPressed,
        borderRadius: BorderRadius.circular(AppDims.radius),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppDims.radius),
            border: Border.all(color: AppPalette.border, width: AppDims.border),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            transitionBuilder: (c, a) => FadeTransition(opacity: a, child: c),
            child: loading
                ? SizedBox(
                    key: const ValueKey('spinner'),
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(spinnerColor),
                    ),
                  )
                : DefaultTextStyle.merge(
                    key: const ValueKey('content'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                    child: child,
                  ),
          ),
        ),
      ),
    );
  }
}
