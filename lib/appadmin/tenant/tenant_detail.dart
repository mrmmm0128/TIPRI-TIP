// ======= 店舗詳細 =======
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:yourpay/appadmin/util.dart';
import 'package:yourpay/tenant/store_detail/tabs/store_qr_tab.dart';

class AdminTenantDetailPage extends StatelessWidget {
  final String ownerUid;
  final String tenantId;
  final String tenantName;

  const AdminTenantDetailPage({
    super.key,
    required this.ownerUid,
    required this.tenantId,
    required this.tenantName,
  });

  String _yen(int v) => '¥${v.toString()}';
  String _ymdhm(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  void _openQrPoster(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('QRポスター作成')),
          body: StoreQrTab(
            tenantId: tenantId,
            tenantName: tenantName,
            ownerId: ownerUid,
            agency: true,
          ),
        ),
      ),
    );
  }

  Future<void> _openEditContactSheet(
    BuildContext context,
    DocumentReference<Map<String, dynamic>> tenantRef, {
    String? currentPhone,
    String? currentMemo,
  }) async {
    final phoneCtrl = TextEditingController(text: currentPhone ?? '');
    final memoCtrl = TextEditingController(text: currentMemo ?? '');
    bool saving = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return AnimatedPadding(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: SafeArea(
            child: StatefulBuilder(
              builder: (ctx, setLocal) {
                Future<void> save() async {
                  if (saving) return;
                  setLocal(() => saving = true);
                  try {
                    final phone = phoneCtrl.text.trim();
                    final memo = memoCtrl.text.trim();

                    await tenantRef.set({
                      'contact': {
                        'phone': phone.isEmpty ? FieldValue.delete() : phone,
                        'memo': memo.isEmpty ? FieldValue.delete() : memo,
                      },
                      'contactUpdatedAt': FieldValue.serverTimestamp(),
                    }, SetOptions(merge: true));

                    if (Navigator.canPop(ctx)) Navigator.pop(ctx);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('連絡先を保存しました')),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text('保存に失敗しました: $e')));
                    }
                  } finally {
                    setLocal(() => saving = false);
                  }
                }

                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        height: 4,
                        width: 40,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.black12,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Row(
                        children: [
                          const Text(
                            '連絡先を編集',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      TextField(
                        controller: phoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: '電話番号（任意）',
                          hintText: '例: 03-1234-5678 / 090-1234-5678',
                          prefixIcon: Icon(Icons.phone_outlined),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: memoCtrl,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'メモ（任意）',
                          hintText: '店舗メモ・注意事項など',
                          prefixIcon: Icon(Icons.notes_outlined),
                        ),
                      ),

                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: saving ? null : save,
                              icon: saving
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.save),
                              label: const Text('保存'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
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
    final tenantRef = FirebaseFirestore.instance
        .collection(ownerUid)
        .doc(tenantId);

    final pageTheme = Theme.of(context).copyWith(
      useMaterial3: true,
      colorScheme: const ColorScheme.light(
        primary: Colors.black,
        onPrimary: Colors.white,
        secondary: Colors.black,
        onSecondary: Colors.white,
        surface: Colors.white,
        onSurface: Colors.black,
        background: Colors.white,
        onBackground: Colors.black,
      ),
      scaffoldBackgroundColor: Colors.white,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      dividerTheme: const DividerThemeData(
        color: Colors.black12,
        thickness: 1,
        space: 1,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
            side: BorderSide(color: Colors.black),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
            side: BorderSide(color: Colors.black),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: Colors.black),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white,
        selectedColor: Colors.black,
        disabledColor: Colors.white,
        checkmarkColor: Colors.white,
        labelStyle: const TextStyle(color: Colors.black),
        secondaryLabelStyle: const TextStyle(color: Colors.white),
        side: const BorderSide(color: Colors.black),
        shape: const StadiumBorder(),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: MaterialStateProperty.resolveWith(
            (s) => s.contains(MaterialState.selected)
                ? Colors.black
                : Colors.white,
          ),
          foregroundColor: MaterialStateProperty.resolveWith(
            (s) => s.contains(MaterialState.selected)
                ? Colors.white
                : Colors.black,
          ),
          side: MaterialStateProperty.all(
            const BorderSide(color: Colors.black),
          ),
          shape: MaterialStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
    );

    return Theme(
      data: pageTheme,
      child: Scaffold(
        appBar: AppBar(title: Text('店舗詳細：$tenantName')),
        body: ListView(
          children: [
            // 基本情報カード
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: tenantRef.snapshots(),
              builder: (context, snap) {
                final m = snap.data?.data();
                final plan = (m?['subscription']?['plan'] ?? '').toString();
                final status = (m?['status'] ?? '').toString();
                final chargesEnabled =
                    m?['connect']?['charges_enabled'] == true;

                // 作成者メールの候補（ドキュメント内）
                final creatorEmailFromDoc =
                    (m?['creatorEmail'] ?? m?['createdBy']?['email'])
                        ?.toString();

                return myCard(
                  title: '基本情報',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _kv('Tenant ID', tenantId),
                      _kv('Owner UID', ownerUid),
                      _kv('Name', tenantName),
                      _kv('Plan', plan.isEmpty ? '-' : plan),
                      _kv('Status', status),
                      _kv('Stripe', chargesEnabled ? 'charges_enabled' : '—'),

                      // 作成者メール：tenant doc に無ければ users/{ownerUid} から取得して表示
                      if (creatorEmailFromDoc != null &&
                          creatorEmailFromDoc.isNotEmpty)
                        _kv('Creator Email', creatorEmailFromDoc)
                      else
                        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                          stream: FirebaseFirestore.instance
                              .collection('users')
                              .doc(ownerUid)
                              .snapshots(),
                          builder: (context, userSnap) {
                            final mail =
                                userSnap.data?.data()?['email']?.toString() ??
                                '-';
                            return _kv('Creator Email', mail);
                          },
                        ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton.icon(
                          onPressed: () => _openQrPoster(context),
                          icon: const Icon(Icons.qr_code_2),
                          label: const Text('QRポスターを作成・ダウンロード'),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

            // 連絡先カード（電話・メモ）
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: tenantRef.snapshots(),
              builder: (context, snap) {
                final m = snap.data?.data() ?? const <String, dynamic>{};
                final contact =
                    (m['contact'] as Map?)?.cast<String, dynamic>() ?? const {};
                final phone = (contact['phone'] as String?) ?? '';
                final memo = (contact['memo'] as String?) ?? '';

                return myCard(
                  title: '連絡先',
                  action: TextButton.icon(
                    onPressed: () => _openEditContactSheet(
                      context,
                      tenantRef,
                      currentPhone: phone,
                      currentMemo: memo,
                    ),
                    icon: const Icon(Icons.edit),
                    label: const Text('編集'),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _kv('電話番号', phone.isEmpty ? '—' : phone),
                      const SizedBox(height: 6),
                      const Text('メモ', style: TextStyle(color: Colors.black54)),
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.03),
                          border: Border.all(color: Colors.black12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(memo.isEmpty ? '—' : memo),
                      ),
                    ],
                  ),
                );
              },
            ),

            // 登録状況カード（既存）
            StatusCard(tenantId: tenantId),

            // 直近チップ（既存）
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: tenantRef
                  .collection('tips')
                  .where('status', isEqualTo: 'succeeded')
                  .orderBy('createdAt', descending: true)
                  .limit(50)
                  .snapshots(),
              builder: (context, snap) {
                final docs = snap.data?.docs ?? const [];
                return myCard(
                  title: '直近のチップ（50件）',
                  child: Column(
                    children: docs.isEmpty
                        ? [const ListTile(title: Text('データがありません'))]
                        : docs.map((d) {
                            final m = d.data();
                            final amount = (m['amount'] as num?)?.toInt() ?? 0;
                            final emp = (m['employeeName'] ?? 'スタッフ')
                                .toString();
                            final ts = m['createdAt'];
                            final when = (ts is Timestamp) ? ts.toDate() : null;
                            return ListTile(
                              dense: true,
                              title: Text('${_yen(amount)}  /  $emp'),
                              subtitle: Text(when == null ? '-' : _ymdhm(when)),
                              trailing: Text(
                                (m['currency'] ?? 'JPY')
                                    .toString()
                                    .toUpperCase(),
                              ),
                            );
                          }).toList(),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(k, style: const TextStyle(color: Colors.black54)),
        ),
        Expanded(child: Text(v)),
      ],
    ),
  );
}
