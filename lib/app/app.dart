import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_theme.dart';
import 'router.dart';

/// Root of the Sumou Mobile App.
///
/// Arabic RTL is the primary interface: the app locale is fixed to Arabic and
/// the whole tree is forced to [TextDirection.rtl]. Navigation is driven by
/// [goRouterProvider], whose redirects key off the auth/session state.
class SumouApp extends ConsumerWidget {
  const SumouApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(goRouterProvider);

    return MaterialApp.router(
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
      routerConfig: router,
      // Force RTL across the app regardless of platform/device locale.
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
