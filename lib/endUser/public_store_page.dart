import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:yourpay/endUser/utils/BottomInstallCta.dart';
import 'package:yourpay/endUser/utils/design.dart';
import 'package:yourpay/endUser/utils/fetchUidByTenantId.dart';
import 'package:yourpay/endUser/utils/image_scrol.dart';

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

  // ▼ 変更：表示件数トグルは ValueNotifier で管理（外側を再構築しない）
  final ValueNotifier<bool> _showAllMembersVN = ValueNotifier<bool>(false);

  final _scrollController = ScrollController();
  bool _showIntro = true; // 最初はローディング画面

  // ▼ 追加：進捗管理
  int _progress = 0; // 0..100
  bool _initStarted = false; // 二重実行防止
  static const int _minSplashMs = 1200; // 最低表示時間（体感向上）

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      // 検索変更は最小限の再構築でOK（ここは setState で検索欄とリストを更新）
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
    // 事前に一度だけ初期化
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

  // 追加：クエリ取得ヘルパー（? と # 両方対応）
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

    // 3) tenantId が判明したら tenantIndex から uid を“必ず”解決
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
        tenantName = (doc.data()?['name'] as String?) ?? '店舗';
        final sub = doc.data()?['subscription'] as Map<String, dynamic>?;
        tenantPlan = sub?['plan'] as String?;
      }
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
          _StoreTipBottomSheet(tenantId: tenantId!, tenantName: tenantName),
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

    final size = MediaQuery.of(context).size;
    final isNarrow = size.width < 480;

    // tenantId 不明 → 404 表示（現状どおり）
    if (tenantId == null) {
      return Scaffold(body: Center(child: Text(tr("status.not_found"))));
    }
    // uid がまだ解決できていない → ローディング表示にして Firestore を触らない
    if (uid == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final tenantDocStream = FirebaseFirestore.instance
        .collection(uid!)
        .doc(tenantId)
        .snapshots();

    // 1) 直近90日の tips を購読して合計額マップを作る
    final since = DateTime.now().subtract(const Duration(days: 90));
    final tipsStream = FirebaseFirestore.instance
        .collection(uid!)
        .doc(tenantId)
        .collection('tips')
        .where('status', isEqualTo: 'succeeded')
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
        .snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: tenantDocStream,
      builder: (context, tSnap) {
        if (tSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
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

                // tips を購読して totals を作成 → employees を購読して並べる
                StreamBuilder<QuerySnapshot>(
                  stream: tipsStream,
                  builder: (context, tipSnap) {
                    final Map<String, int> totals = {};
                    if (tipSnap.hasData) {
                      for (final d in tipSnap.data!.docs) {
                        final data = d.data() as Map<String, dynamic>;
                        final rec = (data['recipient'] as Map?)
                            ?.cast<String, dynamic>();
                        final employeeId =
                            (data['employeeId'] as String?) ??
                            rec?['employeeId'] as String?;
                        final cur =
                            (data['currency'] as String?)?.toUpperCase() ??
                            'JPY';
                        if (employeeId == null || employeeId.isEmpty) continue;
                        if (cur != 'JPY') continue;
                        final amount = (data['amount'] as num?)?.toInt() ?? 0;
                        totals[employeeId] = (totals[employeeId] ?? 0) + amount;
                      }
                    }

                    return StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection(uid!)
                          .doc(tenantId)
                          .collection('employees')
                          .orderBy('createdAt', descending: true)
                          .snapshots(),
                      builder: (context, snap) {
                        if (snap.hasError) {
                          return Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              tr("stripe.error", args: [snap.toString()]),
                            ),
                          );
                        }
                        if (!snap.hasData) {
                          return const Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }

                        final all = snap.data!.docs.toList();
                        final filtered = all.where((doc) {
                          final d = doc.data() as Map<String, dynamic>;
                          final nm = (d['name'] ?? '').toString().toLowerCase();
                          return _query.isEmpty || nm.contains(_query);
                        }).toList();

                        if (filtered.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(child: Text('スタッフが見つかりません')),
                          );
                        }

                        filtered.sort((a, b) {
                          final ta = totals[a.id] ?? 0;
                          final tb = totals[b.id] ?? 0;
                          if (tb != ta) return tb.compareTo(ta);
                          final ca =
                              (a.data() as Map<String, dynamic>)['createdAt'];
                          final cb =
                              (b.data() as Map<String, dynamic>)['createdAt'];
                          final da = (ca is Timestamp)
                              ? ca.toDate()
                              : DateTime.fromMillisecondsSinceEpoch(0);
                          final db = (cb is Timestamp)
                              ? cb.toDate()
                              : DateTime.fromMillisecondsSinceEpoch(0);
                          return db.compareTo(da);
                        });

                        // ① ランク母集団は「チップ>0 の人だけ」
                        final rankedIdsByTip = filtered
                            .map((d) => d.id)
                            .where((id) => (totals[id] ?? 0) > 0)
                            .toList();

                        // ② ランク取得。0円なら null（=非表示）
                        int? rankOf(String id) {
                          if ((totals[id] ?? 0) <= 0) return null;
                          final idx = rankedIdsByTip.indexOf(id);
                          if (idx < 0) return null;
                          return idx + 1;
                        }

                        return Column(
                          children: [
                            ValueListenableBuilder<bool>(
                              valueListenable: _showAllMembersVN,
                              builder: (context, showAll, _) {
                                final displayList = showAll
                                    ? filtered
                                    : filtered.take(6).toList();

                                return Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    AppDims.pad,
                                    8,
                                    AppDims.pad,
                                    0,
                                  ),
                                  child: LayoutBuilder(
                                    builder: (context, constraints) {
                                      final w = constraints.maxWidth;
                                      int cross = 2;
                                      if (w >= 1100) {
                                        cross = 5;
                                      } else if (w >= 900) {
                                        cross = 4;
                                      } else if (w >= 680) {
                                        cross = 3;
                                      }

                                      return GridView.builder(
                                        key: ValueKey(
                                          'grid-${showAll ? "all" : "top6"}',
                                        ),
                                        shrinkWrap: true,
                                        physics:
                                            const NeverScrollableScrollPhysics(),
                                        gridDelegate:
                                            SliverGridDelegateWithFixedCrossAxisCount(
                                              crossAxisCount: cross,
                                              mainAxisSpacing: 14,
                                              crossAxisSpacing: 14,
                                              mainAxisExtent: 200,
                                            ),
                                        itemCount: displayList.length,
                                        itemBuilder: (_, i) {
                                          final doc = displayList[i];
                                          final data =
                                              doc.data()
                                                  as Map<String, dynamic>;
                                          final id = doc.id;
                                          final name =
                                              (data['name'] ?? '') as String;
                                          final email =
                                              (data['email'] ?? '') as String;
                                          final photoUrl =
                                              (data['photoUrl'] ?? '')
                                                  as String;

                                          // ③ rankLabel は 1〜4 位のみ。0円は null（＝非表示）
                                          final r = rankOf(id);
                                          final String? rankLabel =
                                              (r != null && r >= 1 && r <= 4)
                                              ? tr(
                                                  'staff.number',
                                                  namedArgs: {'rank': '$r'},
                                                )
                                              : null;

                                          return _RankedMemberCard(
                                            rankLabel:
                                                rankLabel, // ← String? にして null OK
                                            name: name,
                                            photoUrl: photoUrl,
                                            onTap: () {
                                              Navigator.pushNamed(
                                                context,
                                                '/staff',
                                                arguments: {
                                                  'tenantId': tenantId,
                                                  'tenantName': tenantName,
                                                  'employeeId': id,
                                                  'name': name,
                                                  'email': email,
                                                  'photoUrl': photoUrl,
                                                  'uid': uid,
                                                },
                                              );
                                            },
                                          );
                                        },
                                      );
                                    },
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 8),
                            // 「もっとみる」ボタン（これも部分更新）
                            Center(
                              child: ValueListenableBuilder<bool>(
                                valueListenable: _showAllMembersVN,
                                builder: (context, showAll, _) {
                                  return TextButton(
                                    onPressed: () =>
                                        _showAllMembersVN.value = !showAll,
                                    child: Text(
                                      showAll
                                          ? tr('button.close')
                                          : tr('button.see_more'),
                                      style: AppTypography.label2(
                                        color: AppPalette.textSecondary,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),

                // ── お店にチップ ─────────────────────────────
                _Sectionbar(title: tr('section.store')),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppDims.pad),
                  child: SizedBox(
                    height: 100,
                    child: _YellowActionButton(
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
                          child: _YellowActionButton(
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
                          child: _YellowActionButton(
                            label: tr('button.LINE'),
                            onPressed: () => _openLinkOrNotify(lineUrl),
                          ),
                        ),
                        const SizedBox(height: 15),
                        SizedBox(
                          height: 100,
                          child: _YellowActionButton(
                            label: tr('button.Google_review'),
                            onPressed: () => _openLinkOrNotify(googleReviewUrl),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // ── チップリを導入しよう（PR） ─────────────────
                _Sectionbar(title: tr('section.initiate2')),
                if (isNarrow) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDims.pad,
                    ),
                    child: SizedBox(
                      height: 640,
                      child: ImagesScroller(
                        assets: const [
                          'assets/pdf/1.jpg',
                          'assets/pdf/2.jpg',
                          'assets/pdf/3.jpg',
                          'assets/pdf/4.jpg',
                          'assets/pdf/5.jpg',
                          'assets/pdf/6.jpg',
                          'assets/pdf/7.jpg',
                        ],
                        borderRadius: 12,
                      ),
                    ),
                  ),
                ],
                if (!isNarrow) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDims.pad,
                    ),
                    child: SizedBox(
                      height: 640,
                      child: ImagesScroller(
                        assets: const [
                          'assets/pdf/PC_1.jpg',
                          'assets/pdf/PC_2.jpg',
                          'assets/pdf/PC_3.jpg',
                          'assets/pdf/PC_4.jpg',
                          'assets/pdf/PC_5.jpg',
                          'assets/pdf/PC_6.jpg',
                        ],
                        borderRadius: 12,
                      ),
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

/// 黄色×黒の大ボタン（色は任意で上書き可）
class _YellowActionButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool loading;

  /// 背景色。未指定(null)なら AppPalette.yellow を使用
  final Color? color;

  const _YellowActionButton({
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

/// ランキング風メンバーカード（黄色地＋黒枠）
class _RankedMemberCard extends StatelessWidget {
  /// 1〜4位などの文言。null なら順位UIは一切出さない
  final String? rankLabel;
  final String name;
  final String photoUrl;
  final VoidCallback? onTap;

  const _RankedMemberCard({
    super.key,
    this.rankLabel, // ← nullable に変更
    required this.name,
    required this.photoUrl,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoUrl.isNotEmpty;
    final showRank = (rankLabel != null && rankLabel!.isNotEmpty);

    return Material(
      color: AppPalette.yellow,
      borderRadius: BorderRadius.circular(AppDims.radius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppDims.radius),
            border: Border.all(color: AppPalette.black, width: AppDims.border),
          ),
          child: Column(
            children: [
              showRank
                  ? Text(
                      rankLabel!, // ← 表示は順位がある時だけ
                      style: AppTypography.body(color: AppPalette.black),
                    )
                  : Text(
                      "", // ← 表示は順位がある時だけ
                      style: AppTypography.body(color: AppPalette.black),
                    ),
              const SizedBox(height: 4),
              Container(
                height: AppDims.border2,
                decoration: BoxDecoration(
                  color: AppPalette.black,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(height: 12),

              const SizedBox(height: 8), // レイアウトの目安（好みで調整）
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppPalette.white,
                  border: Border.all(
                    color: AppPalette.black,
                    width: AppDims.border2,
                  ),
                  image: hasPhoto
                      ? DecorationImage(
                          image: NetworkImage(photoUrl),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                alignment: Alignment.center,
                child: !hasPhoto
                    ? Icon(
                        Icons.person,
                        color: AppPalette.black.withOpacity(.65),
                        size: 36,
                      )
                    : null,
              ),
              const SizedBox(height: 10),
              Text(
                name.isEmpty ? 'スタッフ' : name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.body(color: AppPalette.black),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ───────────────────────────────────────────────────────────────
/// 店舗チップ用 BottomSheet（既存のまま/色はデフォルト）
/// ───────────────────────────────────────────────────────────────
class _StoreTipBottomSheet extends StatefulWidget {
  final String tenantId;
  final String? tenantName;
  const _StoreTipBottomSheet({required this.tenantId, this.tenantName});

  @override
  State<_StoreTipBottomSheet> createState() => _StoreTipBottomSheetState();
}

class _StoreTipBottomSheetState extends State<_StoreTipBottomSheet> {
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
                  child: _YellowActionButton(
                    label: tr('button.cancel'),
                    onPressed: _loading ? null : () => Navigator.pop(context),
                    color: AppPalette.white,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  flex: 2,
                  child: _YellowActionButton(
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
