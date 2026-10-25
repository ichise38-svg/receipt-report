import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'screens/home_screen.dart';
import 'services/bug_reporter.dart';
import 'widgets/adaptive_width_frame.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ja');
  // 不具合の自動収集を開始（エラーを端末に記録する）
  await BugReporter.init();
  runApp(const ReceiptReportApp());
}

class ReceiptReportApp extends StatelessWidget {
  const ReceiptReportApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Receipt Report',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ja'),
      supportedLocales: const [Locale('ja'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1E88E5)),
        useMaterial3: true,
        fontFamily: null,
      ),
      // タブレットなど横幅の広い画面では、内容を中央の最大幅に収める
      builder: (context, child) =>
          AdaptiveWidthFrame(child: child ?? const SizedBox.shrink()),
      home: const HomeScreen(),
    );
  }
}
