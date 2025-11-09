import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:easy_localization/easy_localization.dart';

// ===== あなたの既存ページ =====
import 'package:yourpay/endUser/tip_complete_page.dart';
import 'package:yourpay/endUser/public_store_page.dart';
import 'package:yourpay/endUser/staff_detail_page.dart';
import 'endUser/payer_landing_screen.dart';

// ===== Firebase Web 設定 =====
FirebaseOptions web = const FirebaseOptions(
  apiKey: 'AIzaSyAIfxdoGM5TWDVRjtfazvWZ9LnLlMnOuZ4',
  appId: '1:1005883564338:web:ad2b27b5bbd8c0993d772b',
  messagingSenderId: '1005883564338',
  projectId: 'yourpay-c5aaf',
  authDomain: 'yourpay-c5aaf.firebaseapp.com',
  storageBucket: 'yourpay-c5aaf.firebasestorage.app',
);

Future<void> main() async {
  setUrlStrategy(const HashUrlStrategy());
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  await Firebase.initializeApp(options: web);

  // 画面が真っ白になっても原因が見えるように
  ErrorWidget.builder = (FlutterErrorDetails details) {
    if (kReleaseMode) {
      return const Material(
        color: Colors.white,
        child: Center(
          child: Text('Unexpected error', style: TextStyle(color: Colors.red)),
        ),
      );
    }
    return Material(
      color: Colors.white,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Text(
          details.exceptionAsString(),
          style: const TextStyle(color: Colors.red),
        ),
      ),
    );
  };

  runZonedGuarded(
    () {
      runApp(
        EasyLocalization(
          supportedLocales: const [
            Locale('en'),
            Locale('ja'),
            Locale('ko'),
            Locale('zh'),
          ],
          path: 'assets/translations',
          fallbackLocale: const Locale('en'),
          useOnlyLangCode: true,
          child: const MyApp(),
        ),
      );
    },
    (error, stack) {
      // Webのコンソールにも確実に出す
      // ignore: avoid_print
      print('Uncaught zone error: $error\n$stack');
    },
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  Route<dynamic> _onGenerateRoute(RouteSettings settings) {
    final name = settings.name ?? '/';
    final uri = Uri.parse(name);

    // /payer?sid=...
    if (uri.path == '/payer') {
      final sid = uri.queryParameters['sid'] ?? '';
      return MaterialPageRoute(
        builder: (_) => PayerLandingScreen(sessionId: sid),
        settings: settings,
      );
    }

    // /p?t=... [&thanks=true|&canceled=true]
    if (uri.path == '/p') {
      final tid = uri.queryParameters['t'] ?? '';
      final thanks = uri.queryParameters['thanks'] == 'true';
      final canceled = uri.queryParameters['canceled'] == 'true';

      if (thanks || canceled) {
        return MaterialPageRoute(
          builder: (_) => TipCompletePage(
            tenantId: tid,
            tenantName: uri.queryParameters['tenantName'],
            amount: int.tryParse(uri.queryParameters['amount'] ?? ''),
            employeeName: uri.queryParameters['employeeName'],
          ),
          settings: settings,
        );
      }

      // t のみ or パラメータ無しの場合は公開ページへ
      return MaterialPageRoute(
        builder: (_) => const PublicStorePage(),
        settings: RouteSettings(
          name: settings.name,
          arguments: {'tenantId': tid},
        ),
      );
    }

    // それ以外の静的ルート
    final staticRoutes = <String, WidgetBuilder>{
      '/': (_) => const Root(),
      '/staff': (_) => const StaffDetailPage(),
      // '/p' はクエリ駆動のため staticRoutes には入れない
    };

    final builder = staticRoutes[uri.path];
    if (builder != null) {
      return MaterialPageRoute(builder: builder, settings: settings);
    }

    // どれにも該当しない場合は404
    return MaterialPageRoute(
      builder: (_) => NotFoundPage(requestedPath: name),
      settings: settings,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,

      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,

      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.black,
          brightness: Brightness.light,
        ),
        fontFamily: 'LINEseed',
        scaffoldBackgroundColor: Colors.white,
      ),

      onGenerateRoute: _onGenerateRoute,
    );
  }
}

class Root extends StatelessWidget {
  const Root({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // 現在のパス（HashStrategy対応）
        String currentPath() {
          final uri = Uri.base;
          if (uri.fragment.isNotEmpty) {
            final frag = uri.fragment;
            final q = frag.indexOf('?');
            return q >= 0 ? frag.substring(0, q) : frag;
          }
          return uri.path;
        }

        final path = currentPath();

        // ログイン不要で直接表示したい公開パス
        const publicPaths = {
          '/qr-all',
          '/qr-all/qr-builder',
          '/staff',
          '/p',
          '/payer',
        };

        // ❶ パブリックパスはログインに関係なくそのまま画面を返す
        if (publicPaths.contains(path)) {
          switch (path) {
            case '/staff':
              return const StaffDetailPage();
            case '/p':
              // /#/p?t=... のようにクエリで分岐するのは onGenerateRoute 側に実装済み
              return const PublicStorePage();
            case '/payer':
              // 実際は onGenerateRoute 側で sid クエリを読む
              return const _PlaceholderScaffold(title: 'Payer Landing');
            case '/qr-all':
            case '/qr-all/qr-builder':
              return const _PlaceholderScaffold(title: 'QR Builder');
          }
        }

        // ❷ それ以外はログイン状態で分岐（必要に応じて変更してください）
        final user = snap.data;
        if (user == null) {
          // 未ログイン時のトップ（公開トップ等に差し替え可）
          return const PublicStorePage();
        }

        // ログイン済みのホーム画面（必要ならあなたの Home へ置き換え）
        return const _PlaceholderScaffold(title: 'Home (signed in)');
      },
    );
  }
}

class NotFoundPage extends StatelessWidget {
  final String requestedPath;
  const NotFoundPage({super.key, required this.requestedPath});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('404')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off, size: 56),
            const SizedBox(height: 12),
            const Text('Page not found'),
            const SizedBox(height: 8),
            Text(
              requestedPath,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pushReplacementNamed('/'),
              child: const Text('Go Home'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 簡易プレースホルダー（本番では該当画面に置き換えてください）
class _PlaceholderScaffold extends StatelessWidget {
  final String title;
  const _PlaceholderScaffold({required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(child: Text(title)),
    );
  }
}
