import 'package:cloud_functions/cloud_functions.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:yourpay/endUser/utils/design.dart';
import 'package:yourpay/endUser/utils/yellow_action_buttom.dart';

/// ───────────────────────────────────────────────────────────────
/// 店舗チップ用 BottomSheet（既存のまま/色はデフォルト）
/// ───────────────────────────────────────────────────────────────
class StoreTipBottomSheet extends StatefulWidget {
  final String tenantId;
  final String? tenantName;
  const StoreTipBottomSheet({required this.tenantId, this.tenantName});

  @override
  State<StoreTipBottomSheet> createState() => _StoreTipBottomSheetState();
}

class _StoreTipBottomSheetState extends State<StoreTipBottomSheet> {
  int _amount = 500;
  bool _loading = false;

  static const int _maxStoreTip = 1000000;
  final _presets = const [1000, 3000, 5000, 10000];

  void _setAmount(int v) => setState(() => _amount = v.clamp(0, _maxStoreTip));
  void _appendDigit(int d) =>
      setState(() => _amount = (_amount * 10 + d).clamp(0, _maxStoreTip));
  void _appendDoubleZero() => setState(
    () => _amount = _amount == 0 ? 0 : (_amount * 100).clamp(0, _maxStoreTip),
  );
  void _backspace() => setState(() => _amount = _amount ~/ 10);
  String _fmt(int n) => n.toString();

  Future<void> _goStripe() async {
    if (_amount <= 0 || _amount > _maxStoreTip) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(tr('stripe.attention'))));
      return;
    }
    setState(() => _loading = true);
    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'createStoreTipSessionPublic',
      );
      final res = await callable.call({
        'tenantId': widget.tenantId,
        'amount': _amount,
        'memo': 'Tip to store ${widget.tenantName ?? ''}',
      });
      final data = Map<String, dynamic>.from(res.data as Map);
      final checkoutUrl = data['checkoutUrl'] as String?;
      if (checkoutUrl == null || checkoutUrl.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(tr('stripe.miss_URL'))));
        return;
      }
      if (mounted) Navigator.pop(context);
      await launchUrlString(
        checkoutUrl,
        mode: LaunchMode.platformDefault,
        webOnlyWindowName: '_self',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr("stripe.error", args: [e.toString()]))),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.88;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.storefront, color: Colors.black87),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tr('stripe.tip_for_store'),
                    style: AppTypography.label(),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: AppPalette.black),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 金額表示
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppPalette.black,
                  width: AppDims.border,
                ),
              ),
              child: Row(
                children: [
                  const Text(
                    '¥',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _fmt(_amount),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _loading ? null : () => _setAmount(0),
                    icon: const Icon(Icons.clear, color: AppPalette.black),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // 💡 プリセット（_loading中は無効＆薄く）
            Opacity(
              opacity: _loading ? 0.5 : 1,
              child: IgnorePointer(
                ignoring: _loading,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: _presets.map((v) {
                      final active = _amount == v;
                      return Padding(
                        padding: const EdgeInsets.only(right: 2),
                        child: ChoiceChip(
                          side: BorderSide(
                            color: AppPalette.border,
                            width: AppDims.border2,
                          ),
                          label: Text('¥${_fmt(v)}'),
                          selected: active,
                          showCheckmark: false,
                          backgroundColor: active
                              ? AppPalette.black
                              : AppPalette.white,
                          selectedColor: AppPalette.black,
                          labelStyle: TextStyle(
                            color: active
                                ? AppPalette.white
                                : AppPalette.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                          onSelected: (_) => _setAmount(v),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // 💡 テンキー（_loading中は無効＆薄く）
            Opacity(
              opacity: _loading ? 0.5 : 1,
              child: IgnorePointer(
                ignoring: _loading,
                child: _Keypad(
                  onTapDigit: _appendDigit,
                  onTapDoubleZero: _appendDoubleZero,
                  onBackspace: _backspace,
                ),
              ),
            ),

            const SizedBox(height: 12),

            // アクションボタン
            Row(
              children: [
                Flexible(
                  flex: 1,
                  child: YellowActionButton(
                    label: tr('button.cancel'),
                    onPressed: _loading ? null : () => Navigator.pop(context),
                    color: AppPalette.white,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  flex: 2,
                  child: YellowActionButton(
                    label: tr('button.send_tip'),
                    onPressed: _loading ? null : _goStripe,
                    color: AppPalette.white,
                    loading: _loading, // ← スピナー表示
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// テンキー
class _Keypad extends StatelessWidget {
  final void Function(int d) onTapDigit;
  final VoidCallback onTapDoubleZero;
  final VoidCallback onBackspace;
  const _Keypad({
    required this.onTapDigit,
    required this.onTapDoubleZero,
    required this.onBackspace,
  });

  Widget _btn(BuildContext ctx, String label, VoidCallback onPressed) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppPalette.white,
        foregroundColor: AppPalette.black,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDims.radius),
        ),
        side: BorderSide(color: AppPalette.border, width: AppDims.border),
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
      onPressed: onPressed,
      child: Text(label, style: AppTypography.label()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _btn(context, '1', () => onTapDigit(1))),
            const SizedBox(width: 8),
            Expanded(child: _btn(context, '2', () => onTapDigit(2))),
            const SizedBox(width: 8),
            Expanded(child: _btn(context, '3', () => onTapDigit(3))),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _btn(context, '4', () => onTapDigit(4))),
            const SizedBox(width: 8),
            Expanded(child: _btn(context, '5', () => onTapDigit(5))),
            const SizedBox(width: 8),
            Expanded(child: _btn(context, '6', () => onTapDigit(6))),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _btn(context, '7', () => onTapDigit(7))),
            const SizedBox(width: 8),
            Expanded(child: _btn(context, '8', () => onTapDigit(8))),
            const SizedBox(width: 8),
            Expanded(child: _btn(context, '9', () => onTapDigit(9))),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _btn(context, '00', onTapDoubleZero)),
            const SizedBox(width: 8),
            Expanded(child: _btn(context, '0', () => onTapDigit(0))),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppPalette.white,
                  foregroundColor: AppPalette.black,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppDims.radius),
                  ),
                  side: BorderSide(
                    color: AppPalette.border,
                    width: AppDims.border,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: onBackspace,
                child: const Icon(Icons.backspace_outlined, size: 18),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
