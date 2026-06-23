import 'package:flutter/material.dart';

import '../core/widgets/widgets.dart';
import '../theme/app_colors.dart';

/// Developer-only gallery that renders every design-system component.
///
/// Used during Sprint 1 to eyeball the components and verify RTL/theme. It is
/// not a product screen and will not be part of the navigation flow.
class ComponentPreviewScreen extends StatelessWidget {
  const ComponentPreviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SumouScaffold(
      appBar: const SumouAppBar(title: 'مكوّنات سمو'),
      body: ListView(
        children: [
          const SumouSectionHeader(title: 'الأزرار'),
          const SizedBox(height: 12),
          SumouButton(label: 'زر رئيسي', onPressed: () {}),
          const SizedBox(height: 10),
          SumouButton(
            label: 'زر ثانوي',
            variant: SumouButtonVariant.secondary,
            icon: Icons.add,
            onPressed: () {},
          ),
          const SizedBox(height: 10),
          SumouButton(
            label: 'رفض',
            variant: SumouButtonVariant.danger,
            onPressed: () {},
          ),
          const SizedBox(height: 10),
          const SumouButton(label: 'جارٍ التحميل', loading: true),
          const SizedBox(height: 24),

          const SumouSectionHeader(
            title: 'حالات المشروع',
            actionLabel: 'عرض الكل',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: const [
              SumouStatusChip(SumouStatus.active),
              SumouStatusChip(SumouStatus.pendingApproval),
              SumouStatusChip(SumouStatus.accepted),
              SumouStatusChip(SumouStatus.rejected),
              SumouStatusChip(SumouStatus.inProgress),
              SumouStatusChip(SumouStatus.creating),
              SumouStatusChip(SumouStatus.delivered),
              SumouStatusChip(SumouStatus.ended),
            ],
          ),
          const SizedBox(height: 24),

          const SumouSectionHeader(title: 'البطاقات الإحصائية'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SumouStatCard(
                  value: '8',
                  label: 'مشاريع نشطة',
                  icon: Icons.work_outline,
                  accentColor: AppColors.projectTeal,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SumouStatCard(
                  value: '3',
                  label: 'طلبات إنهاء',
                  icon: Icons.inbox_outlined,
                  accentColor: AppColors.financeYellow,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          const SumouSectionHeader(title: 'بطاقة وحقل إدخال'),
          const SizedBox(height: 12),
          const SumouCard(
            child: SumouTextField(
              label: 'اسم المشروع',
              hint: 'أدخل اسم المشروع',
              prefixIcon: Icons.edit_outlined,
            ),
          ),
          const SizedBox(height: 24),

          const SumouSectionHeader(title: 'الحالة الفارغة'),
          const SizedBox(height: 12),
          const SumouCard(
            child: SizedBox(
              height: 220,
              child: SumouEmptyState(
                title: 'لا توجد مشاريع بعد',
                message: 'ستظهر المشاريع هنا عند إضافتها',
                icon: Icons.folder_open_outlined,
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
