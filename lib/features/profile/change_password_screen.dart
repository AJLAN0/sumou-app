import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/widgets/widgets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../auth/providers/auth_controller.dart';
import 'password_policy.dart';

/// Change-password form used both voluntarily and as the forced first-login
/// flow. Passwords stay only in controllers for the lifetime of this widget.
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _current = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirm = TextEditingController();

  String? _localError;
  bool _showCurrent = false;
  bool _showNew = false;
  bool _showConfirm = false;
  bool _submitting = false;

  @override
  void dispose() {
    _current.clear();
    _newPassword.clear();
    _confirm.clear();
    _current.dispose();
    _newPassword.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _fieldChanged(String _) {
    if (ref.read(authControllerProvider).errorMessage != null) {
      ref.read(authControllerProvider.notifier).clearError();
    }
    setState(() => _localError = null);
  }

  Future<void> _submit() async {
    if (_submitting || ref.read(authControllerProvider).isLoading) return;
    FocusScope.of(context).unfocus();
    final current = _current.text;
    final next = _newPassword.text;
    final confirm = _confirm.text;
    final wasForced = ref.read(authControllerProvider).requiresPasswordChange;

    if (current.isEmpty || next.isEmpty || confirm.isEmpty) {
      setState(() => _localError = 'يرجى تعبئة جميع الحقول');
      return;
    }
    final policy = PasswordPolicy.validate(
      currentPassword: current,
      newPassword: next,
    );
    if (policy.failures.contains(PasswordPolicyFailure.matchesCurrent)) {
      setState(
        () => _localError = 'يجب أن تختلف كلمة المرور الجديدة عن الحالية',
      );
      return;
    }
    if (!policy.isValid) {
      setState(() => _localError = _policyError(policy));
      return;
    }
    if (next != confirm) {
      setState(() => _localError = 'كلمتا المرور غير متطابقتين');
      return;
    }
    setState(() {
      _localError = null;
      _submitting = true;
    });

    final ok = await ref
        .read(authControllerProvider.notifier)
        .changePassword(currentPassword: current, newPassword: next);
    if (!mounted) return;
    if (!ok) {
      setState(() => _submitting = false);
      return;
    }

    _current.clear();
    _newPassword.clear();
    _confirm.clear();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('تم تغيير كلمة المرور بنجاح')));

    if (wasForced) {
      final auth = ref.read(authControllerProvider);
      if (auth.needsRoleSelection) {
        context.go(AppRoutes.roleSelect);
      } else {
        context.go(homePathFor(auth.activeRole));
      }
    } else {
      context.pop();
    }
  }

  String _policyError(PasswordPolicyResult policy) {
    if (policy.failures.contains(PasswordPolicyFailure.surroundingWhitespace)) {
      return 'يجب ألا تبدأ أو تنتهي كلمة المرور بمسافة';
    }
    if (policy.failures.contains(PasswordPolicyFailure.tooShort) ||
        policy.failures.contains(PasswordPolicyFailure.tooLong)) {
      return 'كلمة المرور يجب أن تكون من 12 إلى 72 حرفاً';
    }
    return 'استخدم حرفاً كبيراً وصغيراً ورقماً ورمزاً على الأقل';
  }

  Future<void> _logout() async {
    if (_submitting || ref.read(authControllerProvider).isLoading) return;
    await ref.read(authControllerProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final errorText = _localError ?? auth.errorMessage;
    final forced = auth.requiresPasswordChange;
    final loading = auth.isLoading || _submitting;
    final policy = PasswordPolicy.validate(
      currentPassword: _current.text,
      newPassword: _newPassword.text,
    );

    return PopScope(
      canPop: !forced,
      child: SumouScaffold(
        appBar: SumouAppBar(
          title: 'تغيير كلمة المرور',
          leading:
              forced
                  ? const SizedBox.shrink()
                  : IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: loading ? null : () => context.pop(),
                  ),
          actions:
              forced
                  ? [
                    IconButton(
                      key: const ValueKey('forced-password-logout'),
                      tooltip: 'تسجيل الخروج',
                      onPressed: loading ? null : _logout,
                      icon: const Icon(Icons.logout),
                    ),
                  ]
                  : null,
        ),
        body: ListView(
          children: [
            const SizedBox(height: 8),
            Text(
              forced ? 'تحديث كلمة المرور مطلوب' : 'تحديث كلمة المرور',
              style: AppTextStyles.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              forced
                  ? 'لحماية حسابك، غيّر كلمة المرور المؤقتة قبل المتابعة'
                  : 'أدخل كلمة المرور الحالية ثم كلمة المرور الجديدة',
              style: AppTextStyles.bodyMuted,
            ),
            const SizedBox(height: 24),
            SumouTextField(
              controller: _current,
              label: 'كلمة المرور الحالية',
              hint: 'كلمة المرور الحالية',
              obscureText: !_showCurrent,
              prefixIcon: Icons.lock_outline,
              suffixIcon: IconButton(
                key: const ValueKey('toggle-current-password'),
                onPressed: () => setState(() => _showCurrent = !_showCurrent),
                icon: Icon(
                  _showCurrent ? Icons.visibility_off : Icons.visibility,
                ),
              ),
              onChanged: _fieldChanged,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 14),
            SumouTextField(
              controller: _newPassword,
              label: 'كلمة المرور الجديدة',
              hint: 'كلمة المرور الجديدة',
              obscureText: !_showNew,
              prefixIcon: Icons.lock_reset,
              suffixIcon: IconButton(
                key: const ValueKey('toggle-new-password'),
                onPressed: () => setState(() => _showNew = !_showNew),
                icon: Icon(_showNew ? Icons.visibility_off : Icons.visibility),
              ),
              onChanged: _fieldChanged,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            _PolicyFeedback(
              result: policy,
              hasCurrent: _current.text.isNotEmpty,
              hasNew: _newPassword.text.isNotEmpty,
            ),
            const SizedBox(height: 14),
            SumouTextField(
              controller: _confirm,
              label: 'تأكيد كلمة المرور',
              hint: 'تأكيد كلمة المرور',
              obscureText: !_showConfirm,
              prefixIcon: Icons.lock_outline,
              suffixIcon: IconButton(
                key: const ValueKey('toggle-confirm-password'),
                onPressed: () => setState(() => _showConfirm = !_showConfirm),
                icon: Icon(
                  _showConfirm ? Icons.visibility_off : Icons.visibility,
                ),
              ),
              onChanged: _fieldChanged,
              textInputAction: TextInputAction.done,
            ),
            if (errorText != null) ...[
              const SizedBox(height: 14),
              SumouErrorBox(message: errorText),
            ],
            const SizedBox(height: 24),
            SumouButton(
              label: 'حفظ',
              loading: loading,
              onPressed: loading ? null : _submit,
            ),
            if (forced) ...[
              const SizedBox(height: 12),
              SumouButton(
                label: 'تسجيل الخروج',
                icon: Icons.logout,
                variant: SumouButtonVariant.secondary,
                onPressed: loading ? null : _logout,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PolicyFeedback extends StatelessWidget {
  const _PolicyFeedback({
    required this.result,
    required this.hasCurrent,
    required this.hasNew,
  });

  final PasswordPolicyResult result;
  final bool hasCurrent;
  final bool hasNew;

  bool met(PasswordPolicyFailure failure) =>
      hasNew && !result.failures.contains(failure);

  @override
  Widget build(BuildContext context) {
    final lengthMet =
        hasNew &&
        !result.failures.contains(PasswordPolicyFailure.tooShort) &&
        !result.failures.contains(PasswordPolicyFailure.tooLong);
    return Semantics(
      label: 'متطلبات كلمة المرور',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('متطلبات كلمة المرور', style: AppTextStyles.label),
          const SizedBox(height: 8),
          _PolicyLine(label: 'من 12 إلى 72 حرفاً', complete: lengthMet),
          _PolicyLine(
            label: 'حرف كبير وحرف صغير',
            complete:
                met(PasswordPolicyFailure.missingUppercase) &&
                met(PasswordPolicyFailure.missingLowercase),
          ),
          _PolicyLine(
            label: 'رقم ورمز واحد على الأقل',
            complete:
                met(PasswordPolicyFailure.missingDigit) &&
                met(PasswordPolicyFailure.missingSymbol),
          ),
          _PolicyLine(
            label: 'من دون مسافة في البداية أو النهاية',
            complete: met(PasswordPolicyFailure.surroundingWhitespace),
          ),
          _PolicyLine(
            label: 'مختلفة عن كلمة المرور الحالية',
            complete:
                hasCurrent &&
                hasNew &&
                !result.failures.contains(PasswordPolicyFailure.matchesCurrent),
          ),
        ],
      ),
    );
  }
}

class _PolicyLine extends StatelessWidget {
  const _PolicyLine({required this.label, required this.complete});

  final String label;
  final bool complete;

  @override
  Widget build(BuildContext context) {
    final color = complete ? AppColors.accentGreen : AppColors.textMuted;
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          Icon(
            complete ? Icons.check_circle : Icons.circle_outlined,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.label.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
