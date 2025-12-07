// tip_mode_select_page.dart など

import 'package:flutter/material.dart';
import 'package:yourpay/endUser/subscription_tip.dart';
import 'package:yourpay/endUser/utils/design.dart';
import 'package:yourpay/endUser/utils/Intro_scaffold.dart';
import 'staff_detail_page.dart'; // StaffDetailPage を import

class TipModeSelectPage extends StatefulWidget {
  const TipModeSelectPage({super.key});

  @override
  State<TipModeSelectPage> createState() => _TipModeSelectPageState();
}

class _TipModeSelectPageState extends State<TipModeSelectPage> {
  String? tenantId;
  String? employeeId;
  String? name;
  String? photoUrl;
  String? tenantName;
  String? uid;
  bool direct = true;

  bool _showIntro = true;
  bool _initStarted = false;
  static const int _minSplashMs = 2000;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initSplash();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) {
      tenantId = args['tenantId'] as String?;
      employeeId = args['employeeId'] as String?;
      name = args['name'] as String?;
      photoUrl = args['photoUrl'] as String?;
      tenantName = args['tenantName'] as String?;
      uid = args['uid'] as String?;
      direct = args['direct'] as bool? ?? true;
    }
  }

  Future<void> _initSplash() async {
    if (_initStarted) return;
    _initStarted = true;

    final started = DateTime.now();
    // 必要ならここで Firestore から補完してもOK

    final elapsed = DateTime.now().difference(started).inMilliseconds;
    final remain = _minSplashMs - elapsed;
    if (remain > 0) {
      await Future.delayed(Duration(milliseconds: remain));
    }
    if (!mounted) return;
    setState(() => _showIntro = false);
  }

  void _goToDetail(String mode) {
    if (tenantId == null || employeeId == null) {
      // 本当は SnackBar などでエラー表示しても良い
      return;
    }
    if (mode != "subscription") {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const StaffDetailPage(),
          settings: RouteSettings(
            arguments: {
              'tenantId': tenantId,
              'employeeId': employeeId,
              'name': name,
              'photoUrl': photoUrl,
              'tenantName': tenantName,
              'uid': uid,
              'initialMode': mode, // ← oneTime / subscription を渡す
            },
          ),
        ),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SubscriptionTipPage(
            tenantId: tenantId!,
            employeeId: employeeId!,
            staffName: name,
            photoUrl: photoUrl,
          ),
        ),
      );
    }
  }

  Widget _buildMain() {
    final title = name ?? 'スタッフ';
    const avatarSize = 72.0;

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
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 24,
                  horizontal: 20,
                ),
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
                    // 名前＋写真
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
                    const SizedBox(height: 8),
                    Text(
                      title,
                      style: AppTypography.label(color: AppPalette.black),
                    ),
                    if (tenantName != null && tenantName!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        tenantName!,
                        style: AppTypography.small(
                          color: AppPalette.textSecondary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),

                    // 「今回限りで贈る」
                    _ModeCard(
                      title: '今回限りで贈る',
                      description: 'チップを都度払いで贈ることができます。',
                      icon: Icons.flash_on,
                      filled: true,
                      onTap: () => _goToDetail('oneTime'),
                    ),
                    const SizedBox(height: 12),

                    // 「サブスクで贈る」
                    _ModeCard(
                      title: 'サブスクで贈る',
                      description: 'チップを定期的に贈ることができます。',
                      icon: Icons.repeat,
                      filled: false,
                      onTap: () => _goToDetail('subscription'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: _showIntro ? const IntroScaffold() : _buildMain(),
    );
  }
}

/// モード選択用のカード
class _ModeCard extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final bool filled; // true: 黒背景 / false: 白背景
  final VoidCallback onTap;

  const _ModeCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = filled ? AppPalette.black : AppPalette.white;
    final fg = filled ? AppPalette.white : AppPalette.black;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppPalette.black, width: AppDims.border),
        ),
        child: Row(
          children: [
            Icon(icon, color: filled ? AppPalette.yellow : AppPalette.black),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTypography.label(color: fg)),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: AppTypography.small(
                      color: filled
                          ? AppPalette.white
                          : AppPalette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.black54),
          ],
        ),
      ),
    );
  }
}
