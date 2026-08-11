import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/models/client_tracking_model.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/widgets/widgets.dart';
import '../../data/repositories/tracking_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import 'providers/tracking_providers.dart';

/// Public screen where a client enters a secret project code to track it.
///
/// No employee login required. Uses the anonymous RPC-backed
/// [TrackingRepository]; on a valid code it stores the minimized result and
/// routes to the result screen.
class TrackProjectScreen extends ConsumerStatefulWidget {
  const TrackProjectScreen({super.key});

  @override
  ConsumerState<TrackProjectScreen> createState() => _TrackProjectScreenState();
}

class _TrackProjectScreenState extends ConsumerState<TrackProjectScreen> {
  final _code = TextEditingController();
  bool _loading = false;
  bool _loadFailed = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _track() async {
    if (_loading) return;
    FocusScope.of(context).unfocus();

    setState(() {
      _loading = true;
      _loadFailed = false;
      _error = null;
    });

    ClientTrackingModel? result;
    try {
      result = await ref
          .read(trackingRepositoryProvider)
          .trackBySerial(_code.text);
    } on TrackingRepositoryException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
        _error = error.messageAr;
      });
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
        _error = 'تعذّر تتبع المشروع الآن، حاول مرة أخرى';
      });
      return;
    }
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
            hint: 'مثال: FLD-A1B2-C3',
            prefixIcon: Icons.qr_code_2,
            textInputAction: TextInputAction.done,
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            SumouErrorBox(message: _error!),
          ],
          const SizedBox(height: 24),
          SumouButton(
            label: _loadFailed ? 'إعادة المحاولة' : 'تتبع',
            loading: _loading,
            onPressed: _loading ? null : _track,
          ),
        ],
      ),
    );
  }
}
