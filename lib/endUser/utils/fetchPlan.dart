import 'package:cloud_firestore/cloud_firestore.dart';

/// -------- 内部共通: 正規化 & 取り出し --------
String _norm(Object? v) => (v is String)
    ? v.trim().toLowerCase().replaceAll(RegExp(r'[\s_-]'), '')
    : (v == null
          ? ''
          : v.toString().trim().toLowerCase().replaceAll(
              RegExp(r'[\s_-]'),
              '',
            ));

String? _extractPlanRaw(Map<String, dynamic>? data) {
  if (data == null) return null;
  final sub = (data['subscription'] is Map)
      ? Map<String, dynamic>.from(data['subscription'] as Map)
      : null;

  final candidates = <Object?>[
    sub?['plan'],
    sub?['tier'],
    data['plan'],
    data['tier'],
    data['productPlan'],
    data['skuPlan'],
  ];

  for (final v in candidates) {
    if (v == null) continue;
    final s = (v is String) ? v.trim() : v.toString().trim();
    if (s.isNotEmpty) return s;
  }
  return null;
}

String _canonicalizePlan(String raw) {
  final n = _norm(raw);

  const aAliases = {'a', 'aplan', 'plana', 'free', 'basic', '1'};
  const bAliases = {'b', 'bplan', 'planb', 'pro', 'standard', '2'};
  const cAliases = {'c', 'cplan', 'planc', 'premium', '3'};

  if (aAliases.contains(n)) return 'A';
  if (bAliases.contains(n)) return 'B';
  if (cAliases.contains(n)) return 'C';
  return raw.trim();
}

/// 0) Map から
String? planStringFromData(
  Map<String, dynamic>? data, {
  bool canonical = true,
}) {
  final raw = _extractPlanRaw(data);
  if (raw == null || raw.isEmpty) return null;
  return canonical ? _canonicalizePlan(raw) : raw;
}

/// 1) 単発取得
Future<String> fetchPlanString(
  DocumentReference<Map<String, dynamic>> tenantRef, {
  String defaultValue = 'UNKNOWN',
  bool canonical = true,
}) async {
  final snap = await tenantRef.get();
  if (!snap.exists) return defaultValue;
  return planStringFromData(snap.data(), canonical: canonical) ?? defaultValue;
}

/// 2) 監視
Stream<String> watchPlanString(
  DocumentReference<Map<String, dynamic>> tenantRef, {
  String defaultValue = 'UNKNOWN',
  bool canonical = true,
}) {
  return tenantRef.snapshots().map(
    (snap) =>
        planStringFromData(snap.data(), canonical: canonical) ?? defaultValue,
  );
}

/// ---- ここから “ById” の多段パス解決（署名はそのまま） ----

List<DocumentReference<Map<String, dynamic>>> _candidateTenantRefs(
  String uid,
  String tenantId,
) {
  final fs = FirebaseFirestore.instance;
  return [
    // // よくあるストレージ構造を上から順に試す（必要なら順序を入れ替えてOK）
    // fs.collection('users').doc(uid).collection('tenants').doc(tenantId),
    // fs.collection('tenantIndex').doc(tenantId),
    // fs.collection('tenants').doc(tenantId),
    // 互換：もともとの「collection(uid)/doc(tenantId)」
    fs.collection(uid).doc(tenantId),
  ];
}

Future<DocumentSnapshot<Map<String, dynamic>>?> _firstExisting(
  List<DocumentReference<Map<String, dynamic>>> refs,
) async {
  for (final r in refs) {
    final s = await r.get();
    if (s.exists) return s;
  }
  return null;
}

/// 3) uid / tenantId から（署名そのまま）
Future<String> fetchPlanStringById(
  String uid,
  String tenantId, {
  String defaultValue = 'UNKNOWN',
  bool canonical = true,
}) async {
  final snap = await _firstExisting(_candidateTenantRefs(uid, tenantId));
  if (snap == null) return defaultValue;
  return planStringFromData(snap.data(), canonical: canonical) ?? defaultValue;
}

/// ---- B / C 判定は canonical 比較で統一 ----

bool isBPlanFromData(Map<String, dynamic>? data) =>
    planStringFromData(data, canonical: true) == 'B';

bool isCPlanFromData(Map<String, dynamic>? data) =>
    planStringFromData(data, canonical: true) == 'C';

Future<bool> fetchIsBPlan(
  DocumentReference<Map<String, dynamic>> tenantRef,
) async => (await fetchPlanString(tenantRef)) == 'B';

Future<bool> fetchIsCPlan(
  DocumentReference<Map<String, dynamic>> tenantRef,
) async => (await fetchPlanString(tenantRef)) == 'C';

Stream<bool> watchIsBPlan(DocumentReference<Map<String, dynamic>> tenantRef) =>
    watchPlanString(tenantRef).map((v) => v == 'B');

Stream<bool> watchIsCPlan(DocumentReference<Map<String, dynamic>> tenantRef) =>
    watchPlanString(tenantRef).map((v) => v == 'C');

Future<bool> fetchIsBPlanById(String uid, String tenantId) async =>
    (await fetchPlanStringById(uid, tenantId)) == 'B';

Future<bool> fetchIsCPlanById(String uid, String tenantId) async =>
    (await fetchPlanStringById(uid, tenantId)) == 'C';
