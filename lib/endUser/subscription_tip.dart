import 'dart:ui';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yourpay/endUser/utils/Intro_scaffold.dart';
import 'package:yourpay/endUser/utils/design.dart';
// IntroScaffold を使うファイルを import 済みである前提

class SubscriptionTipPage extends StatefulWidget {
  const SubscriptionTipPage({
    super.key,
    required this.tenantId,
    required this.employeeId,
    this.staffName,
    this.photoUrl,
  });

  final String tenantId;
  final String employeeId;
  final String? staffName;
  final String? photoUrl;

  @override
  State<SubscriptionTipPage> createState() => _SubscriptionTipPageState();
}

class _SubscriptionTipPageState extends State<SubscriptionTipPage> {
  static const List<int> _presets = [1000, 2500, 5000, 10000];
  int _selected = 1000;
  static const Map<int, String> _amountToSubscriptionTipId = {
    1000: 'チップ①', // チップ①
    2500: 'チップ②', // チップ②
    5000: 'チップ③', // チップ③
    10000: 'チップ④', // チップ④
  };

  bool _loading = false;
  String? _error;

  // ★ 最初はイントロ画面を表示するフラグ
  bool _showIntro = true;

  String _fmt(int n) => n.toString();

  @override
  void initState() {
    super.initState();

    // ★ 数秒だけイントロを表示してから本画面に切り替える
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        _showIntro = false;
      });
    });
  }

  Future<void> _showEmailDialogAndStart() async {
    final emailCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppPalette.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(
              color: AppPalette.black,
              width: AppDims.border, // ★ 黒枠
            ),
          ),
          title: Text(
            'メールアドレスを入力',
            style: AppTypography.label(color: AppPalette.black),
          ),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(hintText: 'example@mail.com'),
              validator: (value) {
                final v = value?.trim() ?? '';
                if (v.isEmpty) return 'メールアドレスを入力してください';
                final regex = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
                if (!regex.hasMatch(v)) return 'メールアドレスの形式が正しくありません';
                return null;
              },
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: Text(
                'キャンセル',
                style: AppTypography.small(color: AppPalette.black),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppPalette.yellow,
                foregroundColor: AppPalette.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(
                    color: AppPalette.black,
                    width: AppDims.border,
                  ),
                ),
              ),
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  Navigator.of(ctx).pop(emailCtrl.text.trim());
                }
              },
              child: Text(
                '決定',
                style: TextStyle(
                  color: AppPalette.black,
                  fontFamily: "LINEseed",
                ),
              ),
            ),
          ],
        );
      },
    );

    if (result == null) return;
    await _startCheckout(payerEmail: result);
  }

  Future<void> _startCheckout({required String payerEmail}) async {
    final subTipId = _amountToSubscriptionTipId[_selected];
    if (subTipId == null) {
      setState(() {
        _error = 'この金額に対応するサブスク設定が見つかりませんでした。';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'createSubscriptionTipSessionPublic',
      );

      final result = await callable.call<Map<String, dynamic>>({
        'tenantId': widget.tenantId,
        'employeeId': widget.employeeId,
        'subscriptionTipId': subTipId,
        'payerEmail': payerEmail, // ★ ここでメールアドレスを渡す
        // 'memo': 'Subscription tip from end-user page',
      });

      final data = result.data;
      final checkoutUrl = data['checkoutUrl'] as String?;

      if (checkoutUrl == null || checkoutUrl.isEmpty) {
        throw Exception('checkoutUrl が取得できませんでした');
      }

      final uri = Uri.parse(checkoutUrl);

      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) {
        throw Exception('決済画面を開けませんでした');
      }
    } on FirebaseFunctionsException catch (e) {
      debugPrint('createSubscriptionTipSessionPublic error: $e');
      setState(() {
        _error = e.message ?? '決済の開始に失敗しました。しばらくしてからお試しください。';
      });
    } catch (e) {
      debugPrint('createSubscriptionTipSessionPublic error: $e');
      setState(() {
        _error = '決済の開始に失敗しました。しばらくしてからお試しください。';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  // ★ イントロ画面
  Widget _buildIntro() {
    // 他画面と同じように使える前提
    return const IntroScaffold();
  }

  // ★ メイン画面（今までの build の中身をこちらに移動）
  Widget _buildMain(BuildContext context) {
    final staffTitle = widget.staffName ?? 'サブスクチップ';
    const avatarSize = 64.0;
    const sendBtnH = 64.0;

    final cardDecoration = BoxDecoration(
      color: AppPalette.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppPalette.black, width: AppDims.border),
      boxShadow: [
        BoxShadow(
          color: AppPalette.black.withOpacity(0.06),
          blurRadius: 8,
          offset: const Offset(0, 3),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: AppPalette.yellow,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        foregroundColor: AppPalette.black,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'サブスクチップ',
          style: AppTypography.body(color: AppPalette.black),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // スタッフ情報
                  Column(
                    children: [
                      Container(
                        width: avatarSize,
                        height: avatarSize,
                        decoration: BoxDecoration(
                          color: AppPalette.white,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppPalette.black,
                            width: AppDims.border2,
                          ),
                        ),
                        child: CircleAvatar(
                          backgroundColor: AppPalette.white,
                          radius: avatarSize / 2,
                          backgroundImage:
                              (widget.photoUrl != null &&
                                  widget.photoUrl!.isNotEmpty)
                              ? NetworkImage(widget.photoUrl!)
                              : null,
                          child:
                              (widget.photoUrl == null ||
                                  widget.photoUrl!.isEmpty)
                              ? const Icon(
                                  Icons.person,
                                  size: 36,
                                  color: AppPalette.black,
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(staffTitle, style: AppTypography.label()),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // 説明カード（白いカード）
                  Container(
                    decoration: cardDecoration,
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '毎月のチップ金額を選択',
                          style: AppTypography.body(color: AppPalette.black),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '一度設定すると、毎月同じ金額のチップが自動で贈られます。',
                          style: AppTypography.small(
                            color: AppPalette.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // 金額選択（例に出してくれたデザインに寄せた縦並びリスト）
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _presets.map((v) {
                      final selected = _selected == v;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: GestureDetector(
                          onTap: () {
                            setState(() => _selected = v);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 140),
                            curve: Curves.easeOut,
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 14,
                            ),
                            decoration: BoxDecoration(
                              color: selected
                                  ? AppPalette.black
                                  : AppPalette.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: AppPalette.black,
                                width: AppDims.border,
                              ),
                            ),
                            child: Row(
                              children: [
                                // 左側：金額 + / 月（縦並び）
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '¥${_fmt(v)}',
                                      style: AppTypography.label(
                                        color: selected
                                            ? AppPalette.white
                                            : AppPalette.black,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '/ 月',
                                      style: AppTypography.small(
                                        color: selected
                                            ? AppPalette.white
                                            : AppPalette.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                                const Spacer(),
                                // 右側：黄色丸＋チェックマーク（選択時）
                                Container(
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: selected
                                        ? AppPalette.yellow
                                        : Colors.transparent,
                                    border: Border.all(
                                      color: AppPalette.black,
                                      width: AppDims.border,
                                    ),
                                  ),
                                  child: selected
                                      ? const Icon(
                                          Icons.check,
                                          size: 14,
                                          color: AppPalette.black,
                                        )
                                      : null,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 12),

                  // 補足文
                  Text(
                    '選択した金額が毎月自動でスタッフに届きます。',
                    style: AppTypography.small(color: AppPalette.textSecondary),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 8),

                  // ★ 目立つサブスク開始ボタン（黄色＋黒枠）
                  SizedBox(
                    height: sendBtnH,
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _loading ? null : _showEmailDialogAndStart,
                      icon: const Icon(Icons.repeat, size: 18),
                      label: Text(
                        '¥${_fmt(_selected)} / 月 でサブスク開始',
                        style: AppTypography.label(
                          color: AppPalette.black,
                        ).copyWith(fontSize: 16),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppPalette.yellow,
                        foregroundColor: AppPalette.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                          side: const BorderSide(
                            color: AppPalette.black,
                            width: AppDims.border2,
                          ),
                        ),
                        elevation: 2,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    'このあと表示される決済画面で、詳細をご確認いただけます。',
                    style: AppTypography.small(color: AppPalette.textSecondary),
                    textAlign: TextAlign.center,
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: AppTypography.small(color: Colors.redAccent),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ★ AnimatedSwitcher でイントロ → メインを切り替える
  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) {
        return FadeTransition(opacity: animation, child: child);
      },
      child: _showIntro ? _buildIntro() : _buildMain(context),
    );
  }
}
