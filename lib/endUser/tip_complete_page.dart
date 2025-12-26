import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:yourpay/endUser/public_store_page.dart';
import 'package:yourpay/endUser/utils/design.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:yourpay/endUser/utils/fetchUidByTenantId.dart';
import 'package:yourpay/endUser/utils/fetchPlan.dart';
import 'package:yourpay/endUser/utils/store_tip_bottomsheet.dart';
import 'package:yourpay/endUser/utils/yellow_action_buttom.dart';

class TipCompletePage extends StatefulWidget {
  /// Navigator で最低限 tenantId は渡す想定（URL直叩きでも拾えるようにハイブリッド対応済）
  final String? tenantId;
  final String? tenantName;
  final int? amount;
  final String? employeeName;
  final String? uid;

  const TipCompletePage({
    super.key,
    this.tenantId,
    this.tenantName,
    this.amount,
    this.employeeName,
    this.uid,
  });

  @override
  State<TipCompletePage> createState() => _TipCompletePageState();
}

class _TipCompletePageState extends State<TipCompletePage> {
  // ---- 実際に使う値（URL／引数をマージして保持） ----
  String? _tenantId;
  String? _tenantName;
  int? _amount;
  String? _employeeName;
  String? _uid;
  bool isC = false;
  bool isB = false;

  Future<_LinksGateResult>? _linksGateFuture;

  @override
  void initState() {
    super.initState();
    // 1) コンストラクタ引数で初期化
    _tenantId = widget.tenantId;
    _tenantName = widget.tenantName;
    _amount = widget.amount;
    _employeeName = widget.employeeName;
    _uid = widget.uid; // ← 受け取っても後で tenantIndex で上書きする

    // 2) URL から不足を補完（※ uid は拾わないよう 変更済）
    _mergeFromUrlIfNeeded();

    // ★ ここで uid を tenantIndex から必ず解決
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _resolveUidFromTenantIndexIfPossible();
      _reloadLinksGate();
      await initialize();
    });
  }

  Future<void> initialize() async {
    if (_uid == null || _tenantId == null) return;
    final c = await fetchIsCPlanById(_uid!, _tenantId!);
    final b = await fetchIsBPlanById(_uid!, _tenantId!);
    if (!mounted) return;
    setState(() {
      isC = c;
      isB = b;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Navigator の arguments が後から差し込まれるケースにも追従
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) {
      _mergeFromArgs(args);
    }
  }

  Future<void> _resolveUidFromTenantIndexIfPossible() async {
    final tid = _tenantId;
    if (tid == null || tid.isEmpty) return;
    // すでに uid がある場合でも、tenantIndex を正とする（上書き）
    final fetched = await fetchUidByTenantIndex(tid);
    if (!mounted) return;
    if (fetched != null && fetched.isNotEmpty) {
      setState(() => _uid = fetched);
    }
  }

  // ----------------- マージ系ヘルパー -----------------

  void _mergeFromArgs(Map args) {
    final beforeTid = _tenantId;

    _tenantId ??= (args['tenantId'] ?? args['t'])?.toString();
    _tenantName ??= (args['tenantName'] ?? args['store'] ?? args['s'])
        ?.toString();
    _employeeName ??= (args['employeeName'] ?? args['name'] ?? args['n'])
        ?.toString();
    _uid ??= (args['uid'] ?? args['u'] ?? args['user'])?.toString();

    final a = (args['amount'] ?? args['a'])?.toString();
    if (_amount == null && a != null) {
      final v = int.tryParse(a);
      if (v != null) _amount = v;
    }

    if (_tenantId != null && _tenantId != beforeTid) {
      // ★ tenantId が変わったら、uid を tenantIndex から取り直す
      _resolveUidFromTenantIndexIfPossible().then((_) {
        _reloadLinksGate();
      });
    } else {
      _reloadLinksGate();
    }
    setState(() {});
  }

  void _mergeFromUrlIfNeeded() {
    final uri = Uri.base;

    // 1) 通常の ?k=v
    final qp = <String, String>{}..addAll(uri.queryParameters);

    // 2) ハッシュルーター（/#/p?....）内のクエリも吸収
    final frag = uri.fragment;
    final qPos = frag.indexOf('?');
    if (qPos >= 0 && qPos < frag.length - 1) {
      try {
        qp.addAll(Uri.splitQueryString(frag.substring(qPos + 1)));
      } catch (_) {}
    }

    String? pick(List<String> keys) {
      for (final k in keys) {
        final v = qp[k];
        if (v != null && v.isNotEmpty) return v;
      }
      return null;
    }

    final beforeTid = _tenantId;

    _tenantId ??= pick(['t', 'tenantId']);
    _tenantName ??= pick(['tenantName', 'store', 's']);
    _employeeName ??= pick(['employeeName', 'name', 'n']);
    // _uid ??= pick(['u', 'uid', 'user']);

    final a = pick(['amount', 'a']);
    if (_amount == null && a != null) {
      final v = int.tryParse(a);
      if (v != null) _amount = v;
    }

    if (_tenantId != null && _tenantId != beforeTid) {
      // ★ tenantId が変わったら、uid を tenantIndex から取り直す
      _resolveUidFromTenantIndexIfPossible().then((_) {
        _reloadLinksGate();
      });
    } else {
      _reloadLinksGate();
    }
    setState(() {});
  }

  void _reloadLinksGate() {
    if (_tenantId == null || _tenantId!.isEmpty) return;
    _linksGateFuture = _loadLinksGate(
      tenantId: _tenantId!,
      uid: _uid,
      employeeName: _employeeName,
    );
    setState(() {});
  }

  // ----------------- Firestore 読み込み（あなたの既存ロジックを関数化） -----------------

  Future<_LinksGateResult> _loadLinksGate({
    required String tenantId,
    String? uid,
    String? employeeName,
  }) async {
    final fs = FirebaseFirestore.instance;

    Future<Map<String, dynamic>?> _read(DocumentReference ref) async {
      try {
        final snap = await ref.get();
        if (!snap.exists) return null;
        final data = snap.data();
        return (data is Map<String, dynamic>) ? data : null;
      } on FirebaseException catch (_) {
        return null;
      } catch (_) {
        return null;
      }
    }

    String _pickStr(List<dynamic> candidates) {
      for (final v in candidates) {
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
      return '';
    }

    String? _readPlan(Map<String, dynamic> m) {
      final sub = m['subscription'];
      if (sub is Map) {
        final p = sub['plan'];
        if (p is String && p.trim().isNotEmpty) return p.trim();
      }
      for (final k in const ['subscriptionPlan', 'plan', 'subscription_type']) {
        final v = m[k];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
      return null;
    }

    String? _getThanksPhoto(Map<String, dynamic> m) {
      final perks = m['c_perks'];
      final fromPerks = (perks is Map) ? perks['thanksPhotoUrl'] : null;
      return _pickStr([fromPerks, m['thanksPhotoUrl']]);
    }

    String? _getThanksVideo(Map<String, dynamic> m) {
      final candidates = <String?>[];
      if (m['c_perks'] is Map) {
        candidates.add((m['c_perks'] as Map)['thanksVideoUrl'] as String?);
      }
      candidates.addAll([
        m['thanksVideoUrl'] as String?,
        m['downloadUrl'] as String?,
        m['url'] as String?,
        m['storagePath'] as String?,
      ]);
      return _pickStr(candidates);
    }

    String? _getGoogleReview(Map<String, dynamic> m) {
      final url = m['c_perks.reviewUrl'];
      return (url is String && url.trim().isNotEmpty) ? url.trim() : null;
    }

    String? _getLineOfficial(Map<String, dynamic> m) {
      final url = m['c_perks.lineUrl'];
      return (url is String && url.trim().isNotEmpty) ? url.trim() : null;
    }

    Map<String, dynamic> userTenant = const {};
    Map<String, dynamic> publicTenant = const {};
    Map<String, dynamic> publicThanks = const {};
    Map<String, dynamic> publicThanksStaff = const {};

    if (uid != null && uid.isNotEmpty) {
      userTenant = await _read(fs.collection(uid).doc(tenantId)) ?? const {};
    }
    publicTenant =
        await _read(fs.collection('tenants').doc(tenantId)) ?? const {};
    publicThanks =
        await _read(fs.collection('publicThanks').doc(tenantId)) ?? const {};

    if (employeeName != null && employeeName.isNotEmpty) {
      try {
        final qs = await fs
            .collection('publicThanks')
            .doc(tenantId)
            .collection('staff')
            .doc(employeeName)
            .collection('videos')
            .limit(1)
            .get();
        if (qs.docs.isNotEmpty) {
          publicThanksStaff = Map<String, dynamic>.from(
            qs.docs.first.data() as Map,
          );
        }
      } catch (_) {}
    }

    final planRaw = _readPlan(userTenant) ?? _readPlan(publicTenant) ?? '';
    final isSubC = planRaw.toUpperCase().trim() == 'C';

    final googleReviewUrl = _pickStr([
      _getGoogleReview(userTenant),
      _getGoogleReview(publicTenant),
    ]);
    final lineOfficialUrl = _pickStr([
      _getLineOfficial(userTenant),
      _getLineOfficial(publicTenant),
    ]);
    final thanksPhotoUrl = _pickStr([
      _getThanksPhoto(userTenant),
      _getThanksPhoto(publicThanks),
      _getThanksPhoto(publicTenant),
    ]);
    final thanksVideoUrl = _pickStr([
      _getThanksVideo(userTenant),
      _getThanksVideo(publicThanks),
      _getThanksVideo(publicTenant),
      _getThanksVideo(publicThanksStaff),
    ]);

    return _LinksGateResult(
      isSubC: isSubC,
      googleReviewUrl: googleReviewUrl,
      lineOfficialUrl: lineOfficialUrl,
      thanksVideoUrl: thanksVideoUrl,
      thanksPhotoUrl: thanksPhotoUrl,
    );
  }

  // ----------------- 画面内遷移／外部リンク -----------------

  void _navigatePublicStorePage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const PublicStorePage(),
        settings: RouteSettings(
          arguments: {'tenantId': _tenantId, 'tenantName': _tenantName},
        ),
      ),
    );
  }

  Future<void> _openStoreTipBottomSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppPalette.yellow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => StoreTipBottomSheet(
        tenantId: _tenantId ?? '',
        tenantName: _tenantName,
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    if (url.isEmpty) return;
    await launchUrlString(
      url,
      mode: LaunchMode.externalApplication,
      webOnlyWindowName: '_self',
    );
  }

  Future<void> _openThanksVideo(String url) async {
    if (url.isEmpty) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _VideoPlayerDialog(url: url),
    );
  }

  // ----------------- UI -----------------

  @override
  Widget build(BuildContext context) {
    // tenantId 必須
    if ((_tenantId ?? '').isEmpty) {
      return Scaffold(
        body: SafeArea(
          child: Center(child: Text(tr('status.store_info_missing'))),
        ),
      );
    }

    //final storeLabel = _tenantName ?? tr('success_page.store');

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Column(
                      children: [
                        Image.asset(
                          'assets/endUser/checked.png',
                          width: 80,
                          height: 80,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          tr("success_page.success"),
                          style: AppTypography.label(),
                        ),
                        if (_employeeName != null || _amount != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            [
                              if (_employeeName != null)
                                tr(
                                  'success_page.for',
                                  namedArgs: {"Name": _employeeName ?? ''},
                                ),
                              if (_amount != null)
                                tr(
                                  'success_page.amount',
                                  namedArgs: {
                                    "Amount": _amount?.toString() ?? '',
                                  },
                                ),
                            ].join(' / '),
                            style: AppTypography.body(),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  FutureBuilder<_LinksGateResult>(
                    future: _linksGateFuture,
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        );
                      }
                      if (!snap.hasData) return const SizedBox.shrink();

                      final r = snap.data!;
                      final videoUrl = (r.thanksVideoUrl ?? '').trim();
                      final hasVideo = videoUrl.isNotEmpty;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            tr('success_page.thanks_from_store'),
                            style: AppTypography.body(),
                          ),
                          const SizedBox(height: 8),

                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () {
                                if (hasVideo) {
                                  _openThanksVideo(videoUrl);
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        tr('success_page.no_video'),
                                      ),
                                    ),
                                  );
                                }
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: AppPalette.black,
                                    width: AppDims.border,
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: AspectRatio(
                                    aspectRatio: 16 / 9,
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        Image.asset(
                                          'assets/posters/play.jpg',
                                          fit: BoxFit.cover,
                                        ),
                                        const Center(
                                          child: Icon(
                                            Icons.play_circle_fill,
                                            size: 56,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Divider(),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 12),
                  if (isB) ...[
                    FutureBuilder<_LinksGateResult>(
                      future: _linksGateFuture,
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          );
                        }
                        if (snap.hasError || !snap.hasData)
                          return const SizedBox.shrink();

                        final r = snap.data!;
                        if (!r.isSubC) return const SizedBox.shrink();

                        final hasReview = (r.googleReviewUrl ?? '').isNotEmpty;
                        final hasLine = (r.lineOfficialUrl ?? '').isNotEmpty;
                        if (!hasReview && !hasLine)
                          return const SizedBox.shrink();

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (hasLine)
                              SizedBox(
                                height: 80,
                                child: YellowActionButton(
                                  label: tr("success_page.initiate22"),

                                  onPressed: () => _openUrl(r.lineOfficialUrl!),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ],

                  if (isC) ...[
                    FutureBuilder<_LinksGateResult>(
                      future: _linksGateFuture,
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          );
                        }
                        if (snap.hasError || !snap.hasData)
                          return const SizedBox.shrink();

                        final r = snap.data!;
                        if (!r.isSubC) return const SizedBox.shrink();

                        final hasReview = (r.googleReviewUrl ?? '').isNotEmpty;
                        final hasLine = (r.lineOfficialUrl ?? '').isNotEmpty;
                        if (!hasReview && !hasLine)
                          return const SizedBox.shrink();

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (hasReview)
                              SizedBox(
                                height: 80,
                                child: YellowActionButton(
                                  label: tr('success_page.initiate21'),

                                  onPressed: () => _openUrl(r.googleReviewUrl!),
                                ),
                              ),

                            if (hasReview && hasLine) const SizedBox(height: 8),

                            if (hasLine)
                              SizedBox(
                                height: 80,
                                child: YellowActionButton(
                                  label: tr("success_page.initiate22"),

                                  onPressed: () => _openUrl(r.lineOfficialUrl!),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ],

                  const SizedBox(height: 12),
                  const Divider(),

                  const SizedBox(height: 12),
                  YellowActionButton(
                    label: tr("stripe.tip_for_store"),
                    onPressed: _openStoreTipBottomSheet,
                  ),
                  const SizedBox(height: 8),

                  // ② 他のスタッフへ
                  YellowActionButton(
                    label: tr('success_page.initiate1'),
                    onPressed: _navigatePublicStorePage,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// =================== サポートクラス/ウィジェット ===================

/// “Cプラン判定 + 特典リンク + 感謝の写真/動画” をまとめて返す
class _LinksGateResult {
  final bool isSubC;
  final String? googleReviewUrl;
  final String? lineOfficialUrl;
  final String? thanksPhotoUrl;
  final String? thanksVideoUrl;

  _LinksGateResult({
    required this.isSubC,
    this.googleReviewUrl,
    this.lineOfficialUrl,
    this.thanksPhotoUrl,
    this.thanksVideoUrl,
  });
}

/// 動画再生ダイアログ（URL再生）
class _VideoPlayerDialog extends StatefulWidget {
  const _VideoPlayerDialog({required this.url});
  final String url;

  @override
  State<_VideoPlayerDialog> createState() => _VideoPlayerDialogState();
}

class _VideoPlayerDialogState extends State<_VideoPlayerDialog> {
  late final VideoPlayerController _videoCtrl;
  ChewieController? _chewieCtrl;
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      _videoCtrl = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await _videoCtrl.initialize();
      _chewieCtrl = ChewieController(
        videoPlayerController: _videoCtrl,
        autoPlay: true,
        looping: false,
        allowMuting: true,
        allowPlaybackSpeedChanging: true,
        materialProgressColors: ChewieProgressColors(),
      );
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    _chewieCtrl?.dispose();
    _videoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    final maxW = screen.width * 0.95;
    final maxH = screen.height * 0.90;

    double aspect = 16 / 9;
    if (_ready && _videoCtrl.value.isInitialized) {
      aspect = _videoCtrl.value.aspectRatio;
    }

    double w, h;
    if (_ready) {
      if (aspect >= 1) {
        w = maxW;
        h = w / aspect;
        if (h > maxH) {
          h = maxH;
          w = h * aspect;
        }
      } else {
        h = maxH;
        w = h * aspect;
        if (w > maxW) {
          w = maxW;
          h = w / aspect;
        }
      }
    } else {
      w = (maxW * 0.8).clamp(280.0, maxW);
      h = w / aspect;
      if (h > maxH) {
        h = maxH;
        w = h * aspect;
      }
    }

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: w,
        height: h,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: _error != null
              ? Center(
                  child: Text(
                    tr('video.play_failed', namedArgs: {'error': _error ?? ''}),
                  ),
                )
              : (_ready
                    ? Chewie(controller: _chewieCtrl!)
                    : const Center(child: CircularProgressIndicator())),
        ),
      ),
    );
  }
}
