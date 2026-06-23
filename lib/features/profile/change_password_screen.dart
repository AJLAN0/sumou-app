import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/widgets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../auth/providers/auth_controller.dart';

/// Change-password form. Validates locally then calls the (mock) auth
/// controller. Shows loading, error, and success states. No real backend.
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  static const int _minLength = 6;

  final _current = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirm = TextEditingController();

  String? _localError;

  @override
  void dispose() {
    _current.dispose();
    _newPassword.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final current = _current.text;
    final next = _newPassword.text;
    final confirm = _confirm.text;

    if (current.isEmpty || next.isEmpty || confirm.isEmpty) {
      setState(() => _localError = 'يرجى تعبئة جميع الحقول');
      return;
    }
    if (next.length < _minLength) {
      setState(
        () =>
            _localError = 'كلمة المرور يجب أن تكون $_minLength أحرف على الأقل',
      );
      return;
    }
    if (next != confirm) {
      setState(() => _localError = 'كلمتا المرور غير متطابقتين');
      return;
    }
    setState(() => _localError = null);

    final ok = await ref
        .read(authControllerProvider.notifier)
        .changePassword(currentPassword: current, newPassword: next);
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تغيير كلمة المرور بنجاح')),
      );
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final errorText = _localError ?? auth.errorMessage;

    return SumouScaffold(
      appBar: SumouAppBar(
        title: 'تغيير كلمة المرور',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          Text('تحديث كلمة المرور', style: AppTextStyles.titleMedium),
          const SizedBox(height: 4),
          Text(
            'أدخل كلمة المرور الحالية ثم كلمة المرور الجديدة',
            style: AppTextStyles.bodyMuted,
          ),
          const SizedBox(height: 24),
          SumouTextField(
            controller: _current,
            label: 'كلمة المرور الحالية',
            hint: 'كلمة المرور الحالية',
            obscureText: true,
            prefixIcon: Icons.lock_outline,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 14),
          SumouTextField(
            controller: _newPassword,
            label: 'كلمة المرور الجديدة',
            hint: 'كلمة المرور الجديدة',
            obscureText: true,
            prefixIcon: Icons.lock_reset,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 14),
          SumouTextField(
            controller: _confirm,
            label: 'تأكيد كلمة المرور',
            hint: 'تأكيد كلمة المرور',
            obscureText: true,
            prefixIcon: Icons.lock_outline,
            textInputAction: TextInputAction.done,
          ),
          if (errorText != null) ...[
            const SizedBox(height: 14),
            _ErrorBox(message: errorText),
          ],
          const SizedBox(height: 24),
          SumouButton(
            label: 'حفظ',
            loading: auth.isLoading,
            onPressed: auth.isLoading ? null : _submit,
          ),
        ],
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.body.copyWith(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }
}
