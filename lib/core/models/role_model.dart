import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'role_type.dart';

/// UI-facing description of a role: its labels plus its brand [color] and
/// [icon]. Built from a [RoleType] so labels stay in one place.
///
/// Unlike the other models, this one is presentation-aware (imports Flutter)
/// because color and icon are part of the spec's RoleModel.
class RoleModel {
  const RoleModel({
    required this.type,
    required this.nameAr,
    required this.nameEn,
    required this.color,
    required this.icon,
  });

  final RoleType type;
  final String nameAr;
  final String nameEn;
  final Color color;
  final IconData icon;

  String get id => type.key;

  /// Build the [RoleModel] for a given [RoleType].
  factory RoleModel.of(RoleType type) => RoleModel(
    type: type,
    nameAr: type.nameAr,
    nameEn: type.nameEn,
    color: _colors[type] ?? AppColors.primaryTeal,
    icon: _icons[type] ?? Icons.person_outline,
  );

  static const Map<RoleType, Color> _colors = {
    RoleType.admin: AppColors.projectTeal,
    RoleType.manager: AppColors.primaryTeal,
    RoleType.photographer: AppColors.photographerPurple,
    RoleType.designer: AppColors.designerCoral,
    RoleType.finance: AppColors.financeYellow,
    RoleType.weddingAdmin: AppColors.weddingPink,
    RoleType.weddingFinance: AppColors.financeYellow,
    RoleType.attendance: AppColors.projectTeal,
    RoleType.personalPhoto: AppColors.photographerPurple,
    RoleType.clientTracking: AppColors.accentGreen,
  };

  static const Map<RoleType, IconData> _icons = {
    RoleType.admin: Icons.dashboard_outlined,
    RoleType.manager: Icons.work_outline,
    RoleType.photographer: Icons.camera_alt_outlined,
    RoleType.designer: Icons.brush_outlined,
    RoleType.finance: Icons.payments_outlined,
    RoleType.weddingAdmin: Icons.favorite_outline,
    RoleType.weddingFinance: Icons.account_balance_wallet_outlined,
    RoleType.attendance: Icons.access_time,
    RoleType.personalPhoto: Icons.photo_camera_outlined,
    RoleType.clientTracking: Icons.search,
  };
}
