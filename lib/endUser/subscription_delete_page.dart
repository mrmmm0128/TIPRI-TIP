import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:yourpay/endUser/utils/design.dart';

class SubscriptionDeletePage extends StatefulWidget {
  const SubscriptionDeletePage({super.key});

  @override
  State<SubscriptionDeletePage> createState() => _SubscriptionDeletePageState();
}

class _SubscriptionDeletePageState extends State<SubscriptionDeletePage> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();

  bool _loading = false;
  String? _error;
  String? _success;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _error = null;
      _success = null;
    });

    try {
      final raw = _emailCtrl.text.trim();
      final payerEmail = raw.toLowerCase(); // docId 用に正規化

      final db = FirebaseFirestore.instance;
      final ref = db.collection('subscriptionCancelRequests').doc(payerEmail);

      final now = FieldValue.serverTimestamp();

      // シンプルに上書きでOKならこれで十分
      await ref.set({
        'payerEmail': payerEmail,
        'status': 'pending',
        'requestedAt': now,
        'updatedAt': now,
      }, SetOptions(merge: true));

      setState(() {
        _success = '解約申請を受け付けました。ご入力いただいたメールアドレス宛にご案内をお送りします。';
      });
    } catch (e) {
      setState(() {
        _error = '解約申請に失敗しました。通信状況をご確認のうえ、しばらくしてからお試しください。';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
          'サブスクチップ解約',
          style: AppTypography.body(color: AppPalette.black),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: cardDecoration,
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'サブスクチップの解約申請',
                        style: AppTypography.label(color: AppPalette.black),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'サブスクチップの解約をご希望の方は、登録時に入力いただいたメールアドレスを入力して「解約申請する」を押してください。'
                        '\n運営側で内容を確認のうえ、解約手続きを行います。',
                        style: AppTypography.small(
                          color: AppPalette.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // メール入力
                      Text(
                        '登録メールアドレス',
                        style: AppTypography.small(color: AppPalette.black),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          hintText: 'example@mail.com',
                          filled: true,
                          fillColor: AppPalette.white,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: AppPalette.black,
                              width: AppDims.border,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: AppPalette.black,
                              width: AppDims.border2,
                            ),
                          ),
                        ),
                        validator: (value) {
                          final v = value?.trim() ?? '';
                          if (v.isEmpty) {
                            return 'メールアドレスを入力してください';
                          }
                          final regex = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
                          if (!regex.hasMatch(v)) {
                            return 'メールアドレスの形式が正しくありません';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 20),

                      // 解約ボタン
                      SizedBox(
                        height: 52,
                        child: FilledButton(
                          onPressed: _loading ? null : _submit,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppPalette.yellow,
                            foregroundColor: AppPalette.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                              side: const BorderSide(
                                color: AppPalette.black,
                                width: AppDims.border,
                              ),
                            ),
                          ),
                          child: _loading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  '解約申請する',
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontFamily: "LINEseed",
                                  ),
                                ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      if (_error != null) ...[
                        Text(
                          _error!,
                          style: AppTypography.small(color: Colors.redAccent),
                        ),
                      ],

                      if (_success != null) ...[
                        Text(
                          _success!,
                          style: AppTypography.small(
                            color: Colors.green.shade700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
