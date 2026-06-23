import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../theme/app_theme.dart';
import 'app_placeholder_home.dart';

/// Root of the Sumou Mobile App.
///
/// Arabic RTL is the primary interface: the app locale is fixed to Arabic and
/// the whole tree is forced to [TextDirection.rtl]. Theme comes from
/// [AppTheme]. Auth, routing, and feature screens arrive in later steps.
class SumouApp extends StatelessWidget {
  const SumouApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sumou',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      // Arabic-first.
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // Force RTL across the app regardless of platform/device locale.
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const AppPlaceholderHome(),
    );
  }
}
