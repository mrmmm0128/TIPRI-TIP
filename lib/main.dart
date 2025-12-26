import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:yourpay/endUser/select_onetime_or_subscription.dart';
import 'package:yourpay/endUser/subscription_delete_page.dart';
import 'package:yourpay/endUser/tip_complete_page.dart';
import 'package:yourpay/endUser/public_store_page.dart';
import 'package:yourpay/endUser/staff_detail_page.dart';
import 'endUser/payer_landing_screen.dart';

FirebaseOptions web = const FirebaseOptions(
  apiKey: 'AIzaSyAIfxdoGM5TWDVRjtfazvWZ9LnLlMnOuZ4',
  appId: '1:1005883564338:web:ad2b27b5bbd8c0993d772b',
  messagingSenderId: '1005883564338',
  projectId: 'yourpay-c5aaf',
  authDomain: 'yourpay-c5aaf.firebaseapp.com',
  storageBucket: 'yourpay-c5aaf.firebasestorage.app',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  setUrlStrategy(const HashUrlStrategy());

  runApp(const _BootstrapApp());

  unawaited(_startRealApp());
}

Future<void> _startRealApp() async {
  // Firebase 初期化（これが Web だと重い → 遅延するのが正解）
  await Firebase.initializeApp(options: web);

  // EasyLocalization の初期化も後回しにする
  await EasyLocalization.ensureInitialized();

  // エラーウィジェット（白画面のまま固まるのを防ぐ）
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

  // 本物のアプリを起動
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
}

class _BootstrapApp extends StatelessWidget {
  const _BootstrapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(backgroundColor: Colors.white),
    );
  }
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

      return MaterialPageRoute(
        builder: (_) => const PublicStorePage(),
        settings: RouteSettings(
          name: settings.name,
          arguments: {'tenantId': tid},
        ),
      );
    }

    final staticRoutes = <String, WidgetBuilder>{
      '/': (_) => const Root(),
      '/staff': (_) => const TipModeSelectPage(),
      '/staff_selected': (_) => const StaffDetailPage(),
      '/subscription_delete': (_) => const SubscriptionDeletePage(),
      '/tip-complete': (_) => const TipCompletePage(tenantId: ''),
    };

    final builder = staticRoutes[uri.path];
    if (builder != null) {
      return MaterialPageRoute(builder: builder, settings: settings);
    }

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

        const publicPaths = {
          '/qr-all',
          '/qr-all/qr-builder',
          '/staff',
          '/p',
          '/payer',
          '/subscription_delete',
          '/tip-complete',
        };

        if (publicPaths.contains(path)) {
          switch (path) {
            case '/staff':
              return const TipModeSelectPage();
            case '/p':
              return const PublicStorePage();
            case '/payer':
              return const _PlaceholderScaffold(title: 'Payer Landing');
            case '/qr-all':
            case '/qr-all/qr-builder':
              return const _PlaceholderScaffold(title: 'QR Builder');
            case '/subscription_delete':
              return const SubscriptionDeletePage();
            case '/tip-complete':
              return const TipCompletePage();
          }
        }

        final user = snap.data;
        if (user == null) {
          return const PublicStorePage();
        }

        return const _PlaceholderScaffold(title: 'Home');
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
