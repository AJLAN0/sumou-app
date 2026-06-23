import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// Standard page scaffold for the app.
///
/// Applies the Sumou background, optional [SafeArea], and consistent body
/// padding so screens don't repeat boilerplate. RTL is inherited from the app
/// root, so children lay out right-to-left automatically.
class SumouScaffold extends StatelessWidget {
  const SumouScaffold({
    super.key,
    required this.body,
    this.appBar,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.padding = const EdgeInsets.all(16),
    this.safeArea = true,
  });

  final Widget body;
  final PreferredSizeWidget? appBar;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final EdgeInsetsGeometry padding;
  final bool safeArea;

  @override
  Widget build(BuildContext context) {
    Widget content = Padding(padding: padding, child: body);
    if (safeArea) {
      content = SafeArea(child: content);
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: appBar,
      body: content,
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
    );
  }
}
