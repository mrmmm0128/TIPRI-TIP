import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:yourpay/endUser/utils/design.dart';

// AppDims / AppTypography / AppPalette / _RankedMemberCard は既存のものを利用する前提

class StaffRankingSection extends StatefulWidget {
  final Stream<QuerySnapshot> tipsStream;
  final String uid;
  final String tenantId;
  final String? tenantName;
  final String query; // 検索用のクエリ文字列（_query）

  const StaffRankingSection({
    super.key,
    required this.tipsStream,
    required this.uid,
    required this.tenantId,
    required this.tenantName,
    required this.query,
  });

  @override
  State<StaffRankingSection> createState() => _StaffRankingSectionState();
}

class _StaffRankingSectionState extends State<StaffRankingSection> {
  // 「もっとみる」状態
  final ValueNotifier<bool> _showAllMembersVN = ValueNotifier<bool>(false);

  /// employees コレクションの Stream（initState で一度だけ生成）
  late final Stream<QuerySnapshot> _employeesStream;

  @override
  void initState() {
    super.initState();
    _employeesStream = FirebaseFirestore.instance
        .collection(widget.uid)
        .doc(widget.tenantId)
        .collection('employees')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  @override
  void dispose() {
    _showAllMembersVN.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uid = widget.uid;
    final tenantId = widget.tenantId;
    final tenantName = widget.tenantName;
    final _query = widget.query.toLowerCase();

    return StreamBuilder<QuerySnapshot>(
      stream: widget.tipsStream,
      builder: (context, tipSnap) {
        // ---- ① チップ金額の集計（employeeId ごと） ----
        final Map<String, int> totals = {};
        if (tipSnap.hasData) {
          for (final d in tipSnap.data!.docs) {
            final data = d.data() as Map<String, dynamic>;
            final rec = (data['recipient'] as Map?)?.cast<String, dynamic>();
            final employeeId =
                (data['employeeId'] as String?) ??
                rec?['employeeId'] as String?;
            final cur = (data['currency'] as String?)?.toUpperCase() ?? 'JPY';
            if (employeeId == null || employeeId.isEmpty) continue;
            if (cur != 'JPY') continue;
            final amount = (data['amount'] as num?)?.toInt() ?? 0;
            totals[employeeId] = (totals[employeeId] ?? 0) + amount;
          }
        }

        // ---- ② employees ストリーム（initState で生成済み） ----
        return StreamBuilder<QuerySnapshot>(
          stream: _employeesStream,
          builder: (context, snap) {
            if (snap.hasError) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Text(tr("stripe.error", args: [snap.toString()])),
              );
            }
            if (!snap.hasData) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: CircularProgressIndicator(color: AppPalette.yellow),
                ),
              );
            }

            final all = snap.data!.docs.toList();

            // ---- ③ 検索キーワードでフィルタ ----
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

            // ---- ④ ソート（チップ総額降順 → createdAt 降順） ----
            filtered.sort((a, b) {
              final ta = totals[a.id] ?? 0;
              final tb = totals[b.id] ?? 0;
              if (tb != ta) return tb.compareTo(ta);

              final ca = (a.data() as Map<String, dynamic>)['createdAt'];
              final cb = (b.data() as Map<String, dynamic>)['createdAt'];
              final da = (ca is Timestamp)
                  ? ca.toDate()
                  : DateTime.fromMillisecondsSinceEpoch(0);
              final db = (cb is Timestamp)
                  ? cb.toDate()
                  : DateTime.fromMillisecondsSinceEpoch(0);
              return db.compareTo(da);
            });

            // ---- ⑤ ランク計算を Map<String,int> で事前に用意（O(n)） ----

            // ランク母集団は「チップ > 0 の人だけ」
            final rankedIdsByTip = filtered
                .map((d) => d.id)
                .where((id) => (totals[id] ?? 0) > 0)
                .toList();

            final Map<String, int> rankMap = {};
            for (var i = 0; i < rankedIdsByTip.length; i++) {
              rankMap[rankedIdsByTip[i]] = i + 1; // 1位始まり
            }

            int? rankOf(String id) => rankMap[id];

            // ---- ⑥ UI ----
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
                            key: ValueKey('grid-${showAll ? "all" : "top6"}'),
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
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
                              final data = doc.data() as Map<String, dynamic>;
                              final id = doc.id;
                              final name = (data['name'] ?? '') as String;
                              final email = (data['email'] ?? '') as String;
                              final photoUrl =
                                  (data['photoUrl'] ?? '') as String;

                              // 1〜4位のみラベル表示（0円 or 圏外は null）
                              final r = rankOf(id);
                              final String? rankLabel =
                                  (r != null && r >= 1 && r <= 4)
                                  ? tr(
                                      'staff.number',
                                      namedArgs: {'rank': '$r'},
                                    )
                                  : null;

                              return _RankedMemberCard(
                                rankLabel: rankLabel,
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
                                      'direct': false,
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
                Center(
                  child: ValueListenableBuilder<bool>(
                    valueListenable: _showAllMembersVN,
                    builder: (context, showAll, _) {
                      return TextButton(
                        onPressed: () => _showAllMembersVN.value = !showAll,
                        child: Text(
                          showAll ? tr('button.close') : tr('button.see_more'),
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
    );
  }
}

/// ランキング風メンバーカード（黄色地＋黒枠）
class _RankedMemberCard extends StatelessWidget {
  /// 1〜4位などの文言。null なら順位UIは一切出さない
  final String? rankLabel;
  final String name;
  final String photoUrl;
  final VoidCallback? onTap;

  const _RankedMemberCard({
    this.rankLabel, // ← nullable
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
                      rankLabel!,
                      style: AppTypography.body(color: AppPalette.black),
                    )
                  : Text(
                      "",
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
              const SizedBox(height: 8),
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
