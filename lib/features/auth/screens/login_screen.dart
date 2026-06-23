import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/widgets/widgets.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';
import '../providers/auth_controller.dart';

/// Staff login. Uses the mock [AuthController]; on success the router's
/// redirect moves the user to their role home (or role selection for
/// multi-role users). Shows loading, error, and disabled-account messages.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    ref
        .read(authControllerProvider.notifier)
        .login(username: _username.text.trim(), password: _password.text);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);

    return SumouScaffold(
      appBar: SumouAppBar(
        title: 'تسجيل الدخول',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppRoutes.entry),
        ),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          Text('تسجيل دخول الموظفين', style: AppTextStyles.titleMedium),
          const SizedBox(height: 4),
          Text(
            'أدخل اسم المستخدم وكلمة المرور',
            style: AppTextStyles.bodyMuted,
          ),
          const SizedBox(height: 24),
          SumouTextField(
            controller: _username,
            label: 'اسم المستخدم',
            hint: 'اسم المستخدم',
            prefixIcon: Icons.person_outline,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 14),
          SumouTextField(
            controller: _password,
            label: 'كلمة المرور',
            hint: 'كلمة المرور',
            obscureText: true,
            prefixIcon: Icons.lock_outline,
            textInputAction: TextInputAction.done,
          ),
          if (auth.errorMessage != null) ...[
            const SizedBox(height: 14),
            _ErrorBox(message: auth.errorMessage!),
          ],
          const SizedBox(height: 24),
          SumouButton(
            label: 'دخول',
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
