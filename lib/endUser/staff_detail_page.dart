import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:yourpay/endUser/utils/Intro_scaffold.dart';
import 'package:yourpay/endUser/utils/design.dart';
import 'package:yourpay/endUser/utils/fetchPlan.dart'; // fetchPlanStringById を使う

class StaffDetailPage extends StatefulWidget {
  const StaffDetailPage({super.key});
  @override
  State<StaffDetailPage> createState() => _StaffDetailPageState();
}

enum _CommentAction { cancel, skip, ok }

enum _TipMode { oneTime, subscription }

class _StaffDetailPageState extends State<StaffDetailPage> {
  String? tenantId;
  String? employeeId;
  String? name;
  String? email;
  String? photoUrl;
  String? tenantName;
  String? uid;
  bool direct = true;
  String _fmt(int n) => n.toString();
  bool _allowMessage = false; // ← B/Cのみ true
  final _amountCtrl = TextEditingController(text: '0');
  bool _loading = false;
  final _messageCtrl = TextEditingController();
  String? _senderMessage;
  static const int _maxMessageLength = 200;
  static const int _maxAmount = 1000000;
  bool _showIntro = true;
  bool _initStarted = false;
  static const int _minSplashMs = 3000;
  _TipMode _mode = _TipMode.oneTime;
  //int _subAmount = 1000; // サブスク用の選択金額

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initWithSplash();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) {
      tenantId = args['tenantId'] as String? ?? tenantId;
      employeeId = args['employeeId'] as String? ?? employeeId;
      name = args['name'] as String? ?? name;
      email = args['email'] as String? ?? email;
      photoUrl = args['photoUrl'] as String? ?? photoUrl;
      tenantName = args['tenantName'] as String? ?? tenantName;
      uid = args['uid'] as String? ?? uid;
      direct = false;

      // ★ 追加: 最初に開くモードを決める
      final initialMode = args['initialMode'] as String?;
      if (initialMode == 'subscription') {
        _mode = _TipMode.subscription;
      } else if (initialMode == 'oneTime') {
        _mode = _TipMode.oneTime;
      }
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  int _currentAmount() {
    final v = int.tryParse(_amountCtrl.text) ?? 0;
    return v.clamp(0, _maxAmount);
  }

  // Widget _buildModeSwitcher() {
  //   final isSub = _mode == _TipMode.subscription;

  //   return Container(
  //     padding: const EdgeInsets.all(4),
  //     decoration: BoxDecoration(
  //       color: AppPalette.white,
  //       borderRadius: BorderRadius.circular(999),
  //       border: Border.all(color: AppPalette.black, width: AppDims.border),
  //     ),
  //     child: Row(
  //       children: [
  //         // 一度きりタブ
  //         Expanded(
  //           child: GestureDetector(
  //             onTap: () {
  //               if (_mode != _TipMode.oneTime) {
  //                 setState(() => _mode = _TipMode.oneTime);
  //               }
  //             },
  //             child: AnimatedContainer(
  //               duration: const Duration(milliseconds: 160),
  //               curve: Curves.easeOut,
  //               padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
  //               decoration: BoxDecoration(
  //                 color: !isSub ? AppPalette.black : Colors.transparent,
  //                 borderRadius: BorderRadius.circular(999),
  //               ),
  //               child: Row(
  //                 mainAxisAlignment: MainAxisAlignment.center,
  //                 children: [
  //                   const Icon(
  //                     Icons.flash_on,
  //                     size: 16,
  //                     color: AppPalette.yellow,
  //                   ),
  //                   const SizedBox(width: 4),
  //                   Text(
  //                     '一度きり',
  //                     style: AppTypography.small(
  //                       color: !isSub
  //                           ? AppPalette.white
  //                           : AppPalette.textPrimary,
  //                     ),
  //                   ),
  //                 ],
  //               ),
  //             ),
  //           ),
  //         ),
  //         const SizedBox(width: 4),
  //         // サブスクタブ
  //         Expanded(
  //           child: GestureDetector(
  //             onTap: () {
  //               if (_mode != _TipMode.subscription) {
  //                 setState(() => _mode = _TipMode.subscription);
  //               }
  //             },
  //             child: AnimatedContainer(
  //               duration: const Duration(milliseconds: 160),
  //               curve: Curves.easeOut,
  //               padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
  //               decoration: BoxDecoration(
  //                 color: isSub ? AppPalette.yellow : Colors.transparent,
  //                 borderRadius: BorderRadius.circular(999),
  //                 // border: isSub
  //                 //     ? Border.all(
  //                 //         color: AppPalette.black,
  //                 //         width: AppDims.border,
  //                 //       )
  //                 //     : null,
  //               ),
  //               child: Row(
  //                 mainAxisAlignment: MainAxisAlignment.center,
  //                 children: [
  //                   const SizedBox(width: 4),
  //                   Text(
  //                     'サブスク',
  //                     style: AppTypography.small(color: AppPalette.black),
  //                   ),
  //                 ],
  //               ),
  //             ),
  //           ),
  //         ),
  //       ],
  //     ),
  //   );
  // }

  Future<void> _initWithSplash() async {
    if (_initStarted) return;
    _initStarted = true;

    final startedAt = DateTime.now();

    // 元々やっていた URL 初期化（tenantId / employeeId / uid 解決など）
    await _initFromUrlIfNeeded();

    // ついでに Firestore から氏名・店舗名など取得（足りてない場合）
    await _maybeFetchFromFirestore();

    // プランに応じてメッセージ可否を判定
    await _updateAllowMessage();

    // --- ここまでの処理にかかった時間を見て 2秒に満たなければ待つ ---
    final elapsed = DateTime.now().difference(startedAt).inMilliseconds;
    final remain = _minSplashMs - elapsed;
    if (remain > 0) {
      await Future.delayed(Duration(milliseconds: remain));
    }

    if (!mounted) return;
    setState(() {
      _showIntro = false; // 本体 UI に切り替え
    });
  }

  Future<void> _updateAllowMessage() async {
    if (tenantId == null || tenantId!.isEmpty) return;

    // uid が無ければ tenantIndex から補完
    var u = uid;
    if (u == null || u.isEmpty) {
      try {
        final idx = await FirebaseFirestore.instance
            .collection('tenantIndex')
            .doc(tenantId!)
            .get();
        u = (idx.data()?['uid'] as String?) ?? u;
        if (u != null && u.isNotEmpty) {
          uid = u;
        }
      } catch (_) {}
    }
    if (u == null || u.isEmpty) return;

    try {
      final plan = await fetchPlanStringById(
        u,
        tenantId!,
      ); // 'A' / 'B' / 'C' など
      final allow = plan.toUpperCase() == 'B' || plan.toUpperCase() == 'C';
      if (mounted) setState(() => _allowMessage = allow);
    } catch (_) {
      // エラー時は false のまま
    }
  }

  Future<void> _initFromUrlIfNeeded() async {
    // すでに埋まっていれば二度目は何もしない
    if (tenantId != null && employeeId != null) return;

    final uri = Uri.base;

    // 1) 通常のクエリ（?key=value）
    final qp1 = uri.queryParameters;

    // 2) ハッシュルーター内のクエリ（/#/...?...）
    final frag = uri.fragment;
    Map<String, String> qp2 = {};
    final qIndex = frag.indexOf('?');
    if (qIndex >= 0 && qIndex < frag.length - 1) {
      qp2 = Uri.splitQueryString(frag.substring(qIndex + 1));
    }

    // 3) 予防的に、ハッシュ直前にクエリがある稀パターンもマージ
    final merged = <String, String>{};
    merged.addAll(qp1);
    merged.addAll(qp2);

    String? pickAny(List<String> keys) {
      for (final k in keys) {
        final v = merged[k];
        if (v != null && v.isNotEmpty) return v;
      }
      return null;
    }

    final u = pickAny(['u', 'uid', 'user']);
    final t = pickAny(['t', 'tenantId']);
    final e = pickAny(['e', 'employeeId']);
    final a = pickAny(['a', 'amount']);
    final hasDeepLinkParams =
        (t != null || e != null || u != null || a != null);
    if (hasDeepLinkParams) {
      direct = true;
    }

    tenantId = tenantId ?? t;
    employeeId = employeeId ?? e;
    await _resolveUidIfNeeded();

    if (a != null) {
      _amountCtrl.text = a;
    }

    if (mounted) setState(() {});
    // _maybeFetchFromFirestore();
    // _updateAllowMessage();
  }

  Future<void> _resolveUidIfNeeded() async {
    if (tenantId == null || tenantId!.isEmpty) return;

    try {
      final idx = await FirebaseFirestore.instance
          .collection('tenantIndex')
          .doc(tenantId!)
          .get();

      final data = idx.data() ?? {};
      // フィールド名の揺れに広めに対応
      final resolved =
          (data['uid'] ??
                  data['ownerUid'] ??
                  data['userId'] ??
                  data['owner'] ??
                  data['createdBy'])
              ?.toString();

      if (resolved != null && resolved.isNotEmpty) {
        setState(() => uid = resolved);
      }
    } catch (_) {
      // 取れない場合は何もしない（上位でハンドリング）
    }
  }

  Future<void> _maybeFetchFromFirestore() async {
    if (tenantId == null || employeeId == null) return;
    // name/photo が無いときだけ取得
    if (name == null ||
        name!.isEmpty ||
        photoUrl == null ||
        photoUrl!.isEmpty) {
      final empDoc = await FirebaseFirestore.instance
          .collection(uid!)
          .doc(tenantId)
          .collection('employees')
          .doc(employeeId)
          .get();
      if (empDoc.exists) {
        final d = empDoc.data()!;
        name ??= d['name'] as String?;
        email ??= d['email'] as String?;
        photoUrl ??= d['photoUrl'] as String?;
      }
    }
    if (tenantName == null || tenantName!.isEmpty) {
      final tDoc = await FirebaseFirestore.instance
          .collection(uid!)
          .doc(tenantId)
          .get();
      if (tDoc.exists) {
        tenantName = tDoc.data()?['name'] as String?;
      }
    }
    if (mounted) setState(() {});
  }

  void _setAmount(int v) {
    final clamped = v.clamp(0, _maxAmount);
    _amountCtrl.text = clamped.toString();
    setState(() {});
  }

  // 送信エントリーポイント（プランAはコメントダイアログをスキップ）
  Future<void> _promptAndSendTip() async {
    if (tenantId == null || employeeId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(tr('status.staff_unknown'))));
      return;
    }
    final amount = _currentAmount();
    if (amount < 100) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(tr('validation.tip.min'))));
      return;
    }
    if (amount > _maxAmount) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(tr('validation.tip.max'))));
      return;
    }

    if (!_allowMessage) {
      _senderMessage = null;
      await _sendTip();
      return;
    }

    _messageCtrl.text = _senderMessage ?? '';
    final result = await showDialog<_CommentAction>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Theme(
        data: Theme.of(context).copyWith(
          dialogBackgroundColor: AppPalette.white,
          colorScheme: Theme.of(context).colorScheme.copyWith(
            primary: AppPalette.black,
            surface: AppPalette.white,
            onSurface: AppPalette.black,
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
              foregroundColor: AppPalette.black,
              textStyle: AppTypography.body(),
            ),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppPalette.black,
              backgroundColor: AppPalette.white,
              side: BorderSide(color: AppPalette.black, width: AppDims.border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              textStyle: AppTypography.label(),
            ),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              backgroundColor: AppPalette.black,
              foregroundColor: AppPalette.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              textStyle: AppTypography.label(),
            ),
          ),
        ),
        // ★ ダイアログ本体の幅を固定するために SizedBox でラップ
        child: SizedBox(
          width: 380, // お好みで 360〜420 の範囲で
          child: AlertDialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 24,
            ),
            backgroundColor: AppPalette.white,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: AppPalette.black, width: AppDims.border),
            ),
            title: Text(
              tr('dialog.send_message_title'),
              style: AppTypography.label(color: AppPalette.black),
            ),
            // ★ content 側も最大/最小幅を制限し、TextField を4行固定に
            content: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 360, maxWidth: 360),
              child: SizedBox(
                width: double.infinity,
                child: TextField(
                  controller: _messageCtrl,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  minLines: 4,
                  maxLines: 4, // 高さ4行固定（超過分は内部スクロール）
                  maxLength: _maxMessageLength,
                  expands: false,
                  style: AppTypography.body(color: AppPalette.black),
                  decoration: InputDecoration(
                    hintText: tr('dialog.message_hint'),
                    hintStyle: AppTypography.small(
                      color: AppPalette.textSecondary,
                    ),
                    filled: true,
                    fillColor: AppPalette.white,
                    contentPadding: const EdgeInsets.all(12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: AppPalette.black,
                        width: AppDims.border,
                      ),
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
                ),
              ),
            ),
            // ★ Row+Expanded は幅を広げるので Wrap に変更（横幅固定を崩さない）
            actions: [
              Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  TextButton(
                    onPressed: () =>
                        Navigator.pop(context, _CommentAction.cancel),
                    // child: const Text('戻る', ...),
                    child: Text(
                      tr('button.back'),
                      style: const TextStyle(
                        fontFamily: "LINEseed",
                        fontSize: 12,
                      ),
                    ),
                  ),
                  OutlinedButton(
                    onPressed: () =>
                        Navigator.pop(context, _CommentAction.skip),
                    // child: const Text('スキップ', ...),
                    child: Text(
                      tr('button.skip'),
                      style: const TextStyle(
                        fontFamily: "LINEseed",
                        fontSize: 12,
                      ),
                    ),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, _CommentAction.ok),
                    // child: const Text('送信', ...),
                    child: Text(
                      tr('button.send'),
                      style: const TextStyle(
                        fontFamily: "LINEseed",
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (!mounted || result == null || result == _CommentAction.cancel) return;

    if (result == _CommentAction.skip) {
      _senderMessage = null;
    } else {
      final msg = _messageCtrl.text.trim();
      _senderMessage = msg.isEmpty ? null : msg;
    }

    await _sendTip();
  }

  Future<void> _ensureAnonSignIn() async {
    final auth = FirebaseAuth.instance;
    if (auth.currentUser == null) {
      await auth.signInAnonymously();
    }
  }

  // 送信処理
  Future<void> _sendTip() async {
    if (tenantId == null || employeeId == null) return;
    final amount = _currentAmount();
    if (amount < 100) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(tr('validation.tip.min'))));
      return;
    }
    if (amount > _maxAmount) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(tr('validation.tip.max'))));
      return;
    }

    setState(() => _loading = true);
    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'createTipSessionPublic',
      );
      final result = await callable.call({
        'tenantId': tenantId,
        'employeeId': employeeId,
        'amount': amount,
        'memo': 'Tip to ${name ?? ''}',
        'payerMessage': _allowMessage ? (_senderMessage ?? '') : '',
      });

      final data = Map<String, dynamic>.from(result.data as Map);
      final checkoutUrl = data['checkoutUrl'] as String;

      await launchUrlString(
        checkoutUrl,
        mode: LaunchMode.platformDefault,
        webOnlyWindowName: '_self',
      );
      await _ensureAnonSignIn();

      if (!mounted) return;
    } catch (e) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _buildIntro() {
    return const IntroScaffold();
  }

  Widget _buildMain(BuildContext context) {
    if (tenantId == null || tenantId!.isEmpty) {
      return Scaffold(body: Center(child: Text(tr('status.not_found'))));
    }

    final tenantDocStream = FirebaseFirestore.instance
        .collection(uid!)
        .doc(tenantId)
        .snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: tenantDocStream,
      builder: (context, tSnap) {
        if (tSnap.hasError) {
          return const Scaffold(body: Center(child: Text('読み込みに失敗しました')));
        }
        final tData = tSnap.data!.data();
        final status = (tData?['status'] as String?)?.toLowerCase() ?? 'active';

        if (status == 'nonactive') {
          return Scaffold(
            backgroundColor: AppPalette.yellow,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              shadowColor: Colors.transparent,
              foregroundColor: AppPalette.black,
              automaticallyImplyLeading: direct ? false : true,
              toolbarHeight: 30,
              elevation: 0,
              scrolledUnderElevation: 0,
            ),
            body: Center(
              child: Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                constraints: const BoxConstraints(maxWidth: 520),
                decoration: BoxDecoration(
                  color: AppPalette.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: AppPalette.black,
                    width: AppDims.border,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.info_outline,
                      size: 32,
                      color: AppPalette.black,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      tr('status.store_not_ready_title'),
                      style: AppTypography.label(color: AppPalette.black),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tr('status.store_not_ready_desc'),
                      style: AppTypography.body(
                        color: AppPalette.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    if (!direct)
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppPalette.black,
                          foregroundColor: AppPalette.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () => Navigator.pop(context),
                        child: Text(tr('button.back')),
                      ),
                  ],
                ),
              ),
            ),
          );
        }

        // ===== ここから通常 UI =====
        final title = name ?? 'スタッフ詳細';
        final presets = const [1000, 3000, 5000, 10000];

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
            automaticallyImplyLeading: direct ? false : true,
            toolbarHeight: 30,
            elevation: 0,
            scrolledUnderElevation: 0,
          ),
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxHeight < 720;
                final avatar = compact ? 56.0 : 72.0;
                final amountFs = compact ? 24.0 : 28.0;
                final yenFs = compact ? 26.0 : 30.0;
                final sendBtnH = compact ? 64.0 : 80.0;

                return Column(
                  children: [
                    // ===== 上段（プロフィール＋モード切替＋単発カード or 何もなし）=====
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // プロフィール
                          Column(
                            children: [
                              Container(
                                width: avatar,
                                height: avatar,
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
                                  radius: avatar / 2,
                                  backgroundImage:
                                      (photoUrl != null && photoUrl!.isNotEmpty)
                                      ? NetworkImage(photoUrl!)
                                      : null,
                                  child: (photoUrl == null || photoUrl!.isEmpty)
                                      ? const Icon(
                                          Icons.person,
                                          size: 36,
                                          color: AppPalette.black,
                                        )
                                      : null,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(title, style: AppTypography.label()),
                            ],
                          ),
                          // const SizedBox(height: 12),

                          // // モード切り替え
                          // _buildModeSwitcher(),
                          const SizedBox(height: 10),

                          // 単発のときだけ上のカード＋送信ボタンを表示
                          if (_mode == _TipMode.oneTime) ...[
                            Container(
                              decoration: cardDecoration,
                              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          tr("validation.value"),
                                          style: AppTypography.body(),
                                        ),
                                        TextButton.icon(
                                          style: TextButton.styleFrom(
                                            foregroundColor: AppPalette.black,
                                            padding: EdgeInsets.zero,
                                            minimumSize: const Size(0, 0),
                                            tapTargetSize: MaterialTapTargetSize
                                                .shrinkWrap,
                                          ),
                                          onPressed: () => _setAmount(0),
                                          icon: const Icon(
                                            Icons.clear,
                                            size: 20,
                                          ),
                                          label: Text(
                                            tr("validation.clear"),
                                            style: AppTypography.body(),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppPalette.white,
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(
                                        color: AppPalette.black,
                                        width: AppDims.border,
                                      ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                        horizontal: 12,
                                      ),
                                      child: Row(
                                        children: [
                                          Text(
                                            '¥',
                                            style: TextStyle(
                                              fontSize: yenFs,
                                              fontFamily: 'LINEseed',
                                              fontWeight: FontWeight.w700,
                                              color: AppPalette.black,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              _fmt(_currentAmount()),
                                              textAlign: TextAlign.right,
                                              style: TextStyle(
                                                fontFamily: 'LINEseed',
                                                fontSize: amountFs,
                                                color: AppPalette.textPrimary,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Wrap(
                                          spacing: 2,
                                          alignment: WrapAlignment.spaceBetween,
                                          children: presets.map((v) {
                                            final active =
                                                _currentAmount() == v;
                                            return ChoiceChip(
                                              materialTapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                              label: Text(
                                                '¥${_fmt(v)}',
                                                style: AppTypography.small(),
                                              ),
                                              selected: active,
                                              showCheckmark: false,
                                              side: const BorderSide(
                                                width: 0,
                                                color: AppPalette.yellow,
                                              ),
                                              backgroundColor:
                                                  AppPalette.yellow,
                                              selectedColor: AppPalette.yellow,
                                              labelStyle: const TextStyle(
                                                color: AppPalette.black,
                                                fontWeight: FontWeight.w700,
                                              ),
                                              onSelected: (_) => _setAmount(v),
                                              visualDensity:
                                                  const VisualDensity(
                                                    vertical: -2,
                                                    horizontal: 3,
                                                  ),
                                            );
                                          }).toList(),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              height: sendBtnH,
                              child: FilledButton.icon(
                                onPressed: _loading ? null : _promptAndSendTip,
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppPalette.white,
                                  foregroundColor: AppPalette.black,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                    side: const BorderSide(
                                      color: AppPalette.black,
                                      width: AppDims.border,
                                    ),
                                  ),
                                ),
                                label: _loading
                                    ? Text(tr('status.processing'))
                                    : Text(
                                        tr("button.send_tip"),
                                        style: AppTypography.label(),
                                      ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 8),

                    // ===== 下段：単発はテンキー、サブスクは縦並びリスト＋確定ボタン =====
                    if (_mode == _TipMode.oneTime) ...[
                      Expanded(
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(AppDims.radius),
                              topRight: Radius.circular(AppDims.radius),
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 12,
                          ),
                          child: _AmountKeypad(
                            onTapDigit: (d) {
                              final curr = _currentAmount();
                              final next = (curr * 10 + d);
                              if (next <= _maxAmount) _setAmount(next);
                            },
                            onTapDoubleZero: () {
                              final curr = _currentAmount();
                              final next = (curr == 0) ? 0 : (curr * 100);
                              if (next <= _maxAmount) _setAmount(next);
                            },
                            onBackspace: () {
                              final curr = _currentAmount();
                              _setAmount(curr ~/ 10);
                            },
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

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

/// 画面内テンキー（1–9 / 00 / 0 / ⌫）
class _AmountKeypad extends StatelessWidget {
  final void Function(int digit) onTapDigit;
  final VoidCallback onTapDoubleZero;
  final VoidCallback onBackspace;

  const _AmountKeypad({
    required this.onTapDigit,
    required this.onTapDoubleZero,
    required this.onBackspace,
  });

  @override
  Widget build(BuildContext context) {
    const cols = 3;
    const rows = 4;
    const mainSpacing = 8.0; // 縦方向間隔
    const crossSpacing = 8.0; // 横方向間隔

    final buttons = <Widget>[
      for (var i = 1; i <= 9; i++) _numBtn('$i', () => onTapDigit(i)),
      _numBtn('00', onTapDoubleZero),
      _numBtn('0', () => onTapDigit(0)),
      _iconBtn(Icons.backspace_outlined, onBackspace),
    ];

    return LayoutBuilder(
      builder: (context, c) {
        final itemW = (c.maxWidth - (cols - 1) * crossSpacing) / cols;
        final itemH = (c.maxHeight - (rows - 1) * mainSpacing) / rows;
        final ratio = itemW / itemH;

        return GridView.count(
          crossAxisCount: cols,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: mainSpacing,
          crossAxisSpacing: crossSpacing,
          childAspectRatio: ratio,
          children: buttons,
        );
      },
    );
  }

  Widget _numBtn(String label, VoidCallback onPressed) => ElevatedButton(
    onPressed: onPressed,
    style: ElevatedButton.styleFrom(
      elevation: 0,
      backgroundColor: AppPalette.yellow,
      foregroundColor: AppPalette.black,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      side: const BorderSide(color: AppPalette.black, width: AppDims.border),
      padding: const EdgeInsets.symmetric(vertical: 10),
      textStyle: AppTypography.label(),
    ),
    child: Text(label),
  );

  Widget _iconBtn(IconData icon, VoidCallback onPressed) => ElevatedButton(
    onPressed: onPressed,
    style: ElevatedButton.styleFrom(
      elevation: 0,
      backgroundColor: AppPalette.yellow,
      foregroundColor: AppPalette.black,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      side: const BorderSide(color: AppPalette.black, width: AppDims.border),
      padding: const EdgeInsets.symmetric(vertical: 14),
    ),
    child: Icon(icon, size: 22),
  );
}
