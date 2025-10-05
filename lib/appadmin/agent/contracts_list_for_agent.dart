import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:yourpay/appadmin/tenant/tenant_detail.dart';

enum _ChipKind { good, warn, bad }

enum Tri { any, yes, no }

class ContractsListForAgent extends StatelessWidget {
  final String agentId;
  final String query; // ← 追加（空なら無視）
  final Tri initialPaid; // ← 追加
  final Tri subActive; // ← 追加（active/trialing を「登録済み」とみなす）
  final Tri connectCreated; // ← 追加

  const ContractsListForAgent({
    super.key,
    required this.agentId,
    this.query = '',
    this.initialPaid = Tri.any,
    this.subActive = Tri.any,
    this.connectCreated = Tri.any,
  });

  String _ymdhm(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  String _ymd(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('agencies')
          .doc(agentId)
          .collection('contracts')
          .orderBy('contractedAt', descending: true)
          .limit(200)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return ListTile(title: Text('読込エラー: ${snap.error}'));
        }
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return const ListTile(title: Text('登録店舗はまだありません'));
        }

        return Column(
          children: docs.map((d) {
            final m = d.data();
            final tenantId = (m['tenantId'] ?? '').toString();
            final tenantName = (m['tenantName'] ?? '(no name)').toString();
            final whenTs = m['contractedAt'];
            final when = (whenTs is Timestamp) ? whenTs.toDate() : null;
            final ownerUidFromContract = (m['ownerUid'] ?? '').toString();

            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection(ownerUidFromContract)
                  .doc(tenantId)
                  .snapshots(),
              builder: (context, st) {
                final tm = st.data?.data() ?? {};

                // ====== フィルタ判定 ======
                bool passes = true;

                final init =
                    (tm['initialFee']?['status'] ??
                            tm['billing']?['initialFee']?['status'] ??
                            'none')
                        .toString();

                final subSt = (tm['subscription']?['status'] ?? '').toString();
                final subPl = (tm['subscription']?['plan'] ?? '選択なし')
                    .toString();
                final chg = tm['connect']?['charges_enabled'] == true;

                // 次回日（nextPaymentAt or currentPeriodEnd）
                final _nextRaw =
                    tm['subscription']?['nextPaymentAt'] ??
                    tm['subscription']?['currentPeriodEnd'];
                final nextAt = (_nextRaw is Timestamp)
                    ? _nextRaw.toDate()
                    : null;

                // 未払いフラグ
                final overdue =
                    tm['subscription']?['overdue'] == true ||
                    subSt == 'past_due' ||
                    subSt == 'unpaid';

                // ownerUid は contracts に無ければ index の uid をフォールバック
                final ownerUid = ownerUidFromContract.isNotEmpty
                    ? ownerUidFromContract
                    : (tm['uid'] ?? '').toString();

                // キーワード（tenantName / tenantId / ownerUid）
                final q = query.trim().toLowerCase();
                if (q.isNotEmpty) {
                  final hay = [
                    tenantName.toLowerCase(),
                    tenantId.toLowerCase(),
                    ownerUid.toLowerCase(),
                  ].join(' ');
                  passes = hay.contains(q);
                }
                // ▼ 追加：trial かつ 終了日 取得
                DateTime? _toDate(dynamic v) {
                  if (v is Timestamp) return v.toDate();
                  if (v is int)
                    return DateTime.fromMillisecondsSinceEpoch(v * 1000);
                  if (v is double)
                    return DateTime.fromMillisecondsSinceEpoch(
                      (v * 1000).round(),
                    );
                  return null;
                }

                final subMap = (tm['subscription'] as Map?) ?? const {};
                final bool isTrialing = subMap["trial"]["status"] == 'trialing';

                // trialEnd 候補：subscription.trialEnd / trial_end / currentPeriodEnd（運用のキーに合わせて）
                DateTime? trialEnd =
                    _toDate(subMap['trialEnd']) ??
                    _toDate(subMap['trial_end']) ??
                    _toDate(subMap['currentPeriodEnd']);
                // ▼ 初期費用バッジのラベルと色を決める
                String initLabel;
                _ChipKind initKind;
                if (isTrialing && trialEnd != null) {
                  // ここが今回の要件
                  initLabel = '${_ymd(trialEnd)} 支払予定';
                  initKind = _ChipKind.warn; // 色はお好みで（good/warn/bad）
                } else if (init == 'paid') {
                  initLabel = '初期費用済';
                  initKind = _ChipKind.good;
                } else if (init == 'checkout_open') {
                  initLabel = '初期費用:決済中';
                  initKind = _ChipKind.warn;
                } else {
                  initLabel = '初期費用:未払い';
                  initKind = _ChipKind.bad;
                }

                // 初期費用：paid が「yes」
                if (passes && initialPaid != Tri.any) {
                  final isPaid = init == 'paid';
                  passes = (initialPaid == Tri.yes) ? isPaid : !isPaid;
                }

                // サブスク：active or trialing を「yes」
                if (passes && subActive != Tri.any) {
                  final isActive = (subSt == 'active' || subSt == 'trialing');
                  passes = (subActive == Tri.yes) ? isActive : !isActive;
                }

                // Connect：charges_enabled を「yes」
                if (passes && connectCreated != Tri.any) {
                  passes = (connectCreated == Tri.yes) ? chg : !chg;
                }

                if (!passes) {
                  return const SizedBox.shrink(); // ← 非表示にする
                }

                return ResponsiveContractTile(
                  tenantName: tenantName,
                  subtitleLines: [
                    if (ownerUid.isNotEmpty) 'ownerUid: $ownerUid',
                    if (when != null) '登録: ${_ymdhm(when)}',
                  ],
                  chips: [
                    _mini(initLabel, initKind), // ← ここを差し替え
                    _mini(
                      'サブスク:$subPl ${subSt.toUpperCase()}'
                      '${nextAt != null ? '・次回:${_ymd(nextAt)}' : ''}'
                      '${overdue ? '・未払い' : ''}',
                      overdue
                          ? _ChipKind.bad
                          : ((subSt == 'active' || subSt == 'trialing')
                                ? _ChipKind.good
                                : _ChipKind.bad),
                    ),
                    _mini(
                      chg ? 'コネクトアカウント登録済' : 'コネクトアカウント未登録',
                      chg ? _ChipKind.good : _ChipKind.bad,
                    ),
                  ],
                  onTap: () {
                    if (tenantId.isEmpty) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AdminTenantDetailPage(
                          ownerUid: ownerUid,
                          tenantId: tenantId,
                          tenantName: tenantName,
                        ),
                      ),
                    );
                  },
                );
              },
            );
          }).toList(),
        );
      },
    );
  }

  Widget _mini(String label, _ChipKind kind) {
    final color = switch (kind) {
      _ChipKind.good => const Color(0xFF1B5E20),
      _ChipKind.warn => const Color(0xFFB26A00),
      _ChipKind.bad => const Color(0xFFB00020),
    };
    final bg = color.withOpacity(0.08);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
      ),
    );
  }
}

class ResponsiveContractTile extends StatelessWidget {
  final String tenantName;
  final List<String> subtitleLines;
  final List<Widget> chips;
  final VoidCallback? onTap;

  const ResponsiveContractTile({
    super.key,
    required this.tenantName,
    required this.subtitleLines,
    required this.chips,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final isCompact = w < 420; // スマホ閾値。必要なら調整

    // タイトルは省略表示にして縦崩れ防止
    final title = Text(
      tenantName,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
    );

    final subtitle = Text(
      subtitleLines.join('  •  '),
      maxLines: isCompact ? 2 : 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(color: Colors.black54, height: 1.2),
    );

    // バッジはコンパクト時は下段にまとめる。横スクロールも許可して窮屈さ回避
    final badges = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          for (int i = 0; i < chips.length; i++) ...[
            if (i != 0) const SizedBox(width: 6),
            chips[i],
          ],
        ],
      ),
    );

    // 右端の矢印
    const chevron = Icon(Icons.chevron_right);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: isCompact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1行目：店舗名 + 矢印
                  Row(
                    children: [
                      const Icon(Icons.store, size: 20),
                      const SizedBox(width: 8),
                      Expanded(child: title),
                      chevron,
                    ],
                  ),
                  const SizedBox(height: 4),
                  // 2行目：サブタイトル
                  subtitle,
                  const SizedBox(height: 6),
                  // 3行目：バッジ（横スクロール）
                  badges,
                ],
              )
            : Row(
                children: [
                  const Icon(Icons.store, size: 22),
                  const SizedBox(width: 10),
                  // 左：タイトル＋サブタイトル（縦）
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [title, const SizedBox(height: 2), subtitle],
                    ),
                  ),
                  const SizedBox(width: 10),
                  // 右：バッジ（横並び、幅が足りない時はスクロール）
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: badges,
                  ),
                  const SizedBox(width: 6),
                  chevron,
                ],
              ),
      ),
    );
  }
}
