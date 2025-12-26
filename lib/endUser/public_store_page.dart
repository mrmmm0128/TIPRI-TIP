import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:yourpay/endUser/utils/BottomInstallCta.dart';
import 'package:yourpay/endUser/utils/design.dart';
import 'package:yourpay/endUser/utils/fetchUidByTenantId.dart';
import 'package:yourpay/endUser/utils/ranking.dart';
import 'package:yourpay/endUser/utils/store_tip_bottomsheet.dart';
import 'package:yourpay/endUser/utils/yellow_action_buttom.dart';

/// 黒フチ × 黄色の“縁取りテキスト”
class StrokeText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final double strokeWidth;
  final Color strokeColor;
  final Color fillColor;

  const StrokeText(
    this.text, {
    super.key,
    required this.style,
    this.strokeWidth = 0.5,
    this.strokeColor = AppPalette.black,
    this.fillColor = AppPalette.yellow,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 黒フチ
        Text(
          text,
          style: style.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = strokeWidth
              ..color = strokeColor,
          ),
        ),
        // 黄色の塗り
        Text(text, style: style.copyWith(color: fillColor)),
      ],
    );
  }
}

class LanguageSelector extends StatelessWidget {
  const LanguageSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final currentLocale = context.locale;

    final supportedLocales = const [
      Locale('ja'),
      Locale('en'),
      Locale('zh'),
      Locale('ko'),
    ];

    return DropdownButton<Locale>(
      value: supportedLocales.contains(currentLocale)
          ? currentLocale
          : const Locale('ja'),
      dropdownColor: AppPalette.pageBg,
      underline: Container(
        height: AppDims.border / 3,
        color: AppPalette.border,
      ),
      iconEnabledColor: AppPalette.black,
      items: supportedLocales.map((locale) {
        final label = _getLabel(locale.languageCode);
        return DropdownMenuItem(
          value: locale,
          child: Text(
            label,
            style: AppTypography.label2().copyWith(
              color: AppPalette.black,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      }).toList(),
      onChanged: (Locale? newLocale) {
        if (newLocale != null) {
          context.setLocale(newLocale);
        }
      },
    );
  }

  /// 言語コードに応じたラベル
  String _getLabel(String code) {
    switch (code) {
      case 'ja':
        return '日本語';
      case 'en':
        return 'English';
      case 'zh':
        return '中文';
      case 'ko':
        return '한국어';
      default:
        return code;
    }
  }
}

/// ===============================================================
/// ページ本体
/// ===============================================================
class PublicStorePage extends StatefulWidget {
  const PublicStorePage({super.key});

  @override
  State<PublicStorePage> createState() => PublicStorePageState();
}

class PublicStorePageState extends State<PublicStorePage> {
  String? tenantId;
  String? tenantName;
  String? employeeId;
  String? name;
  String? email;
  String? photoUrl;
  String? uid;
  String? tenantPlan;

  final _searchCtrl = TextEditingController();
  String _query = '';

  // 表示件数トグル（今後メンバー一覧側で使う用として保持）
  final ValueNotifier<bool> _showAllMembersVN = ValueNotifier<bool>(false);

  final _scrollController = ScrollController();
  bool _showIntro = true; // 最初はローディング画面

  // 進捗管理
  int _progress = 0; // 0..100
  bool _initStarted = false; // 二重実行防止
  static const int _minSplashMs = 500; // 最低表示時間（体感向上）

  /// Firestore Streams（init 後に一度だけ生成して再利用）
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _tenantDocStream;
  Stream<QuerySnapshot>? _tipsStream;

  /// 「直近90日」の開始日時（initState 時に固定）
  late final DateTime _tipsSince;

  @override
  void initState() {
    super.initState();

    _tipsSince = DateTime.now().subtract(const Duration(days: 90));

    _searchCtrl.addListener(() {
      setState(() => _query = _searchCtrl.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollController.dispose();
    _showAllMembersVN.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _initWithProgress();
  }

  void _setProgress(int v) {
    if (!mounted) return;
    setState(() {
      _progress = v.clamp(0, 100).toInt();
    });
  }

  Future<void> _initWithProgress() async {
    if (_initStarted) return;
    _initStarted = true;

    final startedAt = DateTime.now();

    // Step1: ロゴ画像を事前読み込み
    try {
      await precacheImage(
        const AssetImage('assets/posters/tipri.png'),
        context,
      );
    } catch (_) {}
    _setProgress(20);

    // Step2: ルート/クエリ解決 + tenant 等の初期読み込み
    await _loadFromRouteOrQuery();
    _setProgress(70);

    // Step3: ちょい待ち（UI安定）
    await Future.delayed(const Duration(milliseconds: 200));
    _setProgress(85);

    // Step4: 画面反映余裕
    await Future.delayed(const Duration(milliseconds: 100));
    _setProgress(100);

    // 最低表示時間を満たす
    final elapsed = DateTime.now().difference(startedAt).inMilliseconds;
    final remain = _minSplashMs - elapsed;
    if (remain > 0) {
      await Future.delayed(Duration(milliseconds: remain));
    }

    if (!mounted) return;
    setState(() => _showIntro = false);
  }

  // === 追加：未設定通知（白黒の SnackBar） ===
  void _showBWSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.black,
        content: Text(message, style: const TextStyle(color: Colors.white)),
        behavior: SnackBarBehavior.floating,
        elevation: 2,
      ),
    );
  }

  // === 追加：URL を開く or 未設定通知 ===
  Future<void> _openLinkOrNotify(String? url) async {
    if (url == null || url.trim().isEmpty) {
      _showBWSnack('まだ設定されていません');
      return;
    }
    await launchUrlString(
      url,
      mode: LaunchMode.externalApplication,
      webOnlyWindowName: '_self',
    );
  }

  // クエリ取得ヘルパー（? と # 両方対応）
  String? _getParam(String key) {
    final v1 = Uri.base.queryParameters[key];
    if (v1 != null && v1.isNotEmpty) return v1;

    final frag = Uri.base.fragment;
    if (frag.isNotEmpty) {
      final s = frag.startsWith('/') ? frag.substring(1) : frag;
      final f = Uri.tryParse(s);
      final v2 = f?.queryParameters[key];
      if (v2 != null && v2.isNotEmpty) return v2;
    }
    return null;
  }

  Future<void> _loadFromRouteOrQuery() async {
    // 1) Navigator args（あれば優先）
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) {
      tenantId = args['tenantId'] as String? ?? tenantId;
      employeeId = args['employeeId'] as String? ?? employeeId;
      name = args['name'] as String? ?? name;
      email = args['email'] as String? ?? email;
      photoUrl = args['photoUrl'] as String? ?? photoUrl;
      tenantName = args['tenantName'] as String? ?? tenantName;
    }

    // 2) URL（? と # の両方を見る）
    tenantId ??= _getParam('t');

    // 3) tenantId が判明したら tenantIndex から uid を解決
    if (tenantId != null) {
      uid = await fetchUidByTenantIndex(tenantId!);
    }

    // 4) 店舗名の解決（両方そろってから）
    if (tenantId != null && uid != null && tenantName == null) {
      final doc = await FirebaseFirestore.instance
          .collection(uid!)
          .doc(tenantId!)
          .get();
      if (doc.exists) {
        final data = doc.data();
        tenantName = (data?['name'] as String?) ?? '店舗';
        final sub = data?['subscription'] as Map<String, dynamic>?;
        tenantPlan = sub?['plan'] as String?;
      }
    }

    // 5) Firestore Streams を一度だけセットアップ
    if (tenantId != null && uid != null) {
      _tenantDocStream ??= FirebaseFirestore.instance
          .collection(uid!)
          .doc(tenantId!)
          .snapshots();

      _tipsStream ??= FirebaseFirestore.instance
          .collection(uid!)
          .doc(tenantId!)
          .collection('tips')
          .where('status', isEqualTo: 'succeeded')
          .where(
            'createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(_tipsSince),
          )
          .snapshots();
    }

    if (mounted) setState(() {});
  }

  Future<void> openStoreTipSheet() async {
    if (tenantId == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppPalette.yellow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) =>
          StoreTipBottomSheet(tenantId: tenantId!, tenantName: tenantName),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_showIntro) {
      return Scaffold(
        backgroundColor: AppPalette.yellow,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LayoutBuilder(
                    builder: (context, c) {
                      final w = c.maxWidth;
                      final double size = (w * 0.50).clamp(140.0, 320.0);
                      return Image.asset(
                        'assets/posters/tipri.png',
                        width: size,
                        fit: BoxFit.contain,
                      );
                    },
                  ),
                  const SizedBox(height: 18),
                  Text(
                    '読み込み中 $_progress%',
                    style: const TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: _progress / 100.0,
                      minHeight: 10,
                      color: Colors.black,
                      backgroundColor: Colors.black12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // tenantId / uid / Streams が不明 → 404 or 簡易エラー
    if (tenantId == null || uid == null || _tenantDocStream == null) {
      return Scaffold(body: Center(child: Text(tr("status.not_found"))));
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _tenantDocStream,
      builder: (context, tSnap) {
        final tData = tSnap.data?.data();
        final status = (tData?['status'] as String?)?.toLowerCase();
        if (status == 'nonactive') {
          return Scaffold(
            backgroundColor: AppPalette.pageBg,
            appBar: AppBar(
              backgroundColor: AppPalette.pageBg,
              foregroundColor: AppPalette.black,
              elevation: 0,
              automaticallyImplyLeading: false,
              scrolledUnderElevation: 0,
              actions: const [
                Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: LanguageSelector(),
                ),
              ],
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.info_outline,
                      size: 40,
                      color: AppPalette.black,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '店舗側の登録が完了していません',
                      style: AppTypography.label2(color: AppPalette.black),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '現在この店舗はご利用準備中です。しばらく待ってから再度アクセスしてください。',
                      style: AppTypography.small(
                        color: AppPalette.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () {}, // Stream なので即反映、明示の再読込不要
                      icon: const Icon(Icons.refresh),
                      label: const Text('再読み込み'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final subType = (tData?['subscription']?['plan'] as String?)
            ?.toUpperCase();
        final isTypeC =
            subType == 'C' || ((tenantPlan ?? '').toUpperCase() == 'C');
        final isTypeB =
            subType == 'B' || ((tenantPlan ?? '').toUpperCase() == 'B');

        final lineUrl = (tData?['c_perks.lineUrl'] as String?) ?? '';
        final googleReviewUrl = (tData?['c_perks.reviewUrl'] as String?) ?? '';

        // tipsStream がまだ null の可能性を考慮
        if (_tipsStream == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return Scaffold(
          backgroundColor: AppPalette.pageBg,
          appBar: AppBar(
            backgroundColor: AppPalette.pageBg,
            foregroundColor: AppPalette.black,
            elevation: 0,
            automaticallyImplyLeading: false,
            scrolledUnderElevation: 0,
            actions: const [
              Padding(
                padding: EdgeInsets.only(right: 12),
                child: LanguageSelector(),
              ),
            ],
          ),
          bottomNavigationBar: const BottomInstallCtaEdgeToEdge(),
          body: SingleChildScrollView(
            key: const PageStorageKey('publicStoreScroll'),
            controller: _scrollController,
            padding: const EdgeInsets.only(
              top: 80,
              bottom: 24,
              left: 12,
              right: 12,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final w = c.maxWidth;
                      final double size = (w * 0.5).clamp(140.0, 320.0);
                      return Image.asset(
                        'assets/posters/tipri.png',
                        width: size,
                        fit: BoxFit.contain,
                      );
                    },
                  ),
                ),
                const SizedBox(height: 50),

                // ── メンバー ────────────────────────────────
                _Sectionbar(title: tr('section.members')),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppDims.pad,
                    0,
                    AppDims.pad,
                    0,
                  ),
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: tr('button.search_staff'),
                      hintStyle: AppTypography.small(
                        color: AppPalette.textSecondary,
                      ),
                      prefixIcon: const Icon(
                        Icons.search,
                        color: AppPalette.textSecondary,
                      ),
                      filled: true,
                      fillColor: AppPalette.white,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppDims.radius),
                        borderSide: const BorderSide(
                          color: AppPalette.border,
                          width: AppDims.border,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppDims.radius),
                        borderSide: const BorderSide(
                          color: AppPalette.yellow,
                          width: AppDims.border,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Center(child: Text(tr('staff.ranking'))),
                const SizedBox(height: 10),
                StaffRankingSection(
                  tipsStream: _tipsStream!,
                  uid: uid!,
                  tenantId: tenantId!,
                  tenantName: tenantName,
                  query: _query,
                ),

                // ── お店にチップ ─────────────────────────────
                _Sectionbar(title: tr('section.store')),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppDims.pad),
                  child: SizedBox(
                    height: 100,
                    child: YellowActionButton(
                      label: tr('button.send_tip_for_store'),
                      icon: Icons.currency_yen,
                      onPressed: openStoreTipSheet,
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                if (isTypeB) ...[
                  _Sectionbar(title: tr('section.initiate1')),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDims.pad,
                    ),
                    child: Column(
                      children: [
                        SizedBox(
                          height: 100,
                          child: YellowActionButton(
                            label: tr('button.LINE'),
                            onPressed: () => _openLinkOrNotify(lineUrl),
                          ),
                        ),
                        const SizedBox(height: 7),
                      ],
                    ),
                  ),
                ],

                // ── ご協力お願いします（Cタイプのみ表示） ───────────
                if (isTypeC) ...[
                  _Sectionbar(title: tr('section.initiate1')),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDims.pad,
                    ),
                    child: Column(
                      children: [
                        SizedBox(
                          height: 100,
                          child: YellowActionButton(
                            label: tr('button.LINE'),
                            onPressed: () => _openLinkOrNotify(lineUrl),
                          ),
                        ),
                        const SizedBox(height: 15),
                        SizedBox(
                          height: 100,
                          child: YellowActionButton(
                            label: tr('button.Google_review'),
                            onPressed: () => _openLinkOrNotify(googleReviewUrl),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 三角形の吹き出し風セクションバー
class _Sectionbar extends StatelessWidget {
  const _Sectionbar({
    this.color = AppPalette.border,
    this.thickness = AppDims.border,
    this.notchWidth = 25,
    this.notchHeight = 10,
    this.margin = const EdgeInsets.only(
      top: 18,
      left: 12,
      right: 12,
      bottom: 8,
    ),
    this.alignment = Alignment.center,
    required this.title,
  });

  final Color color;
  final double thickness;
  final double notchWidth;
  final double notchHeight;
  final EdgeInsetsGeometry margin;
  final Alignment alignment;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: Column(
        children: [
          Center(child: Text(title, style: AppTypography.label2())),
          const SizedBox(height: 8),
          SizedBox(
            height: notchHeight + thickness,
            width: double.infinity,
            child: CustomPaint(
              painter: _SectionbarPainter(
                color: color,
                thickness: thickness,
                notchWidth: notchWidth,
                notchHeight: notchHeight,
                alignX: alignment.x,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _SectionbarPainter extends CustomPainter {
  _SectionbarPainter({
    required this.color,
    required this.thickness,
    required this.notchWidth,
    required this.notchHeight,
    required this.alignX,
  });

  final Color color;
  final double thickness;
  final double notchWidth; // 水平幅
  final double notchHeight; // 下方向の深さ
  final double alignX;

  @override
  void paint(Canvas canvas, Size size) {
    final y = thickness / 2;
    final r = thickness / 2;

    double cx = ((alignX + 1) / 2) * size.width;

    final minCx = r + notchWidth / 2;
    final maxCx = size.width - r - notchWidth / 2;
    cx = cx.clamp(minCx, maxCx);

    final left = Offset(r, y);
    final right = Offset(size.width - r, y);

    final path = Path()
      ..moveTo(left.dx, left.dy)
      ..lineTo(cx - notchWidth / 2, y)
      ..lineTo(cx, y + notchHeight)
      ..lineTo(cx + notchWidth / 2, y)
      ..lineTo(right.dx, right.dy);

    final paintStroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, paintStroke);
  }

  @override
  bool shouldRepaint(covariant _SectionbarPainter old) =>
      old.color != color ||
      old.thickness != thickness ||
      old.notchWidth != notchWidth ||
      old.notchHeight != notchHeight ||
      old.alignX != alignX;
}
