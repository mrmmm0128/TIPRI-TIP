import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class BottomInstallCtaEdgeToEdge extends StatelessWidget {
  const BottomInstallCtaEdgeToEdge({
    super.key,
    this.url = 'https://www.zotman.jp/tipri',
    this.label = '導入はコチラ',
    this.topRadius = 14.0, // ← 上だけ丸める量（お好みで）
  });

  final String url;
  final String label;
  final double topRadius;

  static const _brandYellow = Color(0xFFFCC400);
  static const _borderW = 6.0;
  static const _height = 76.0;
  static const _dropOffsetY = 10.0; // 下側の“黒ベタ影”オフセット

  @override
  Widget build(BuildContext context) {
    final rTopOnly = BorderRadius.only(
      topLeft: Radius.circular(topRadius),
      topRight: Radius.circular(topRadius),
      // 下は直角（0）
    );

    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    final innerBottomPad = math.max(0.0, bottomInset - 2.0);

    return SizedBox(
      height: _height + innerBottomPad,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // ===== 黒ベタの“影”（下にだけ出す） =====
          Positioned(
            left: 0,
            right: 0,
            bottom: -_dropOffsetY,
            height: _height,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: rTopOnly, // 上だけ丸い
                ),
              ),
            ),
          ),
          // ===== 本体（黄 + 極太黒枠） =====
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: _height + innerBottomPad,
            child: Material(
              color: _brandYellow,
              shape: RoundedRectangleBorder(
                borderRadius: rTopOnly, // 上だけ丸い、下は直角
                side: const BorderSide(color: Colors.black, width: _borderW),
              ),
              child: InkWell(
                borderRadius: rTopOnly,
                onTap: () async {
                  final uri = Uri.parse(url);
                  await launchUrl(
                    uri,
                    mode: LaunchMode.externalApplication,
                    webOnlyWindowName: '_blank',
                  );
                },
                child: Padding(
                  // ホームインジケータ分を“内側”に吸収
                  padding: EdgeInsets.only(bottom: innerBottomPad),
                  child: Center(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.0,
                        color: Colors.black,
                        height: 1.0,
                        // fontFamily: 'LINEseed', // 使っていれば指定
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
