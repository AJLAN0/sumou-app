import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/widgets/widgets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import 'providers/tracking_providers.dart';

/// Public screen where a client enters a secret project code to track it.
///
/// No employee login required. Uses the (mock) [TrackingRepository]; on a valid
/// code it stores the result and routes to the result screen.
class TrackProjectScreen extends ConsumerStatefulWidget {
  const TrackProjectScreen({super.key});

  @override
  ConsumerState<TrackProjectScreen> createState() => _TrackProjectScreenState();
}

class _TrackProjectScreenState extends ConsumerState<TrackProjectScreen> {
  static const int _minLength = 4;

  final _code = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _track() async {
    FocusScope.of(context).unfocus();
    final code = _code.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'يرجى إدخال الرمز السري للمشروع');
      return;
    }
    if (code.length < _minLength) {
      setState(() => _error = 'الرمز قصير جداً، تحقق منه وحاول مجدداً');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final result = await ref
        .read(trackingRepositoryProvider)
        .trackBySerial(code);
    if (!mounted) return;

    setState(() => _loading = false);
    if (result == null) {
      setState(() => _error = 'لم يتم العثور على مشروع بهذا الرمز');
      return;
    }

    ref.read(trackingResultProvider.notifier).state = result;
    context.push(AppRoutes.trackResult);
  }

  @override
  Widget build(BuildContext context) {
    return SumouScaffold(
      appBar: SumouAppBar(
        title: 'تتبع مشروع',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppRoutes.entry),
        ),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 16),
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.accentGreen.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.search,
                color: AppColors.accentGreen,
                size: 36,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'تتبع مشروعك',
            style: AppTextStyles.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'أدخل الرمز السري الذي استلمته لمتابعة حالة المشروع',
            style: AppTextStyles.bodyMuted,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          SumouTextField(
            controller: _code,
            label: 'الرمز السري',
            hint: 'مثال: X7K-29QM-4R',
            prefixIcon: Icons.qr_code_2,
            textInputAction: TextInputAction.done,
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            SumouErrorBox(message: _error!),
          ],
          const SizedBox(height: 24),
          SumouButton(
            label: 'تتبع',
            loading: _loading,
            onPressed: _loading ? null : _track,
          ),
        ],
      ),
    );
  }
}
