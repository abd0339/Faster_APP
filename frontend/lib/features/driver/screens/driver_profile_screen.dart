import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';

class DriverProfileScreen extends StatefulWidget {
  const DriverProfileScreen({super.key});

  @override
  State<DriverProfileScreen> createState() => _DriverProfileScreenState();
}

class _DriverProfileScreenState extends State<DriverProfileScreen> {
  String _selectedVehicle = 'MOTO';
  final _plateController = TextEditingController();
  bool _isLoading = false;
  String? _statusMessage;

  final List<Map<String, dynamic>> _vehicles = [
    {
      'value': 'MOTO',
      'label': 'Motorcycle',
      'icon': '🏍️',
    },
    {
      'value': 'CAR',
      'label': 'Car',
      'icon': '🚗',
    },
    {
      'value': 'TOKTOK',
      'label': 'Toktok',
      'icon': '🛺',
    },
    {
      'value': 'VAN',
      'label': 'Van',
      'icon': '🚐',
    },
  ];

  Future<void> _submit() async {
    if (_plateController.text.isEmpty) {
      setState(() => _statusMessage = 'Please enter your plate number');
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = null;
    });

    try {
      await ApiService.instance.post(
        '/api/driver/profile',
        data: {
          'vehicleType': _selectedVehicle,
          'vehiclePlate': _plateController.text.trim(),
        },
      );

      setState(() =>
          _statusMessage = '✅ Profile submitted! Waiting for admin approval.');
    } catch (e) {
      setState(() => _statusMessage = ApiService.getErrorMessage(e));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Complete Your Profile'),
        actions: [
          TextButton(
            onPressed: () => context.read<AuthBloc>().add(LogoutRequested()),
            child: const Text(
              'Logout',
              style: TextStyle(
                color: AppColors.error,
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── Status banner ────────────────
            GlassCard(
              color: AppColors.warning,
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    color: AppColors.warning,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Account Pending Verification',
                          style: AppTextStyles.headlineSmall.copyWith(
                            color: AppColors.warning,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Complete your profile to '
                          'start delivering.',
                          style: AppTextStyles.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // ─── Vehicle type ─────────────────
            Text(
              'Vehicle Type',
              style: AppTextStyles.headlineSmall,
            ),
            const SizedBox(height: 16),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 2.5,
              children: _vehicles.map((v) {
                final isSelected = _selectedVehicle == v['value'];
                return GestureDetector(
                  onTap: () => setState(() => _selectedVehicle = v['value']),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary.withValues(alpha: 0.15)
                          : AppColors.glassWhite,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.glassBorder,
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          v['icon'],
                          style: const TextStyle(fontSize: 22),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          v['label'],
                          style: AppTextStyles.labelLarge.copyWith(
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 32),

            // ─── Plate number ─────────────────
            Text(
              'Plate Number',
              style: AppTextStyles.headlineSmall,
            ),
            const SizedBox(height: 16),
            GlassCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  TextFormField(
                    controller: _plateController,
                    style: AppTextStyles.bodyLarge.copyWith(
                      letterSpacing: 4,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      hintText: 'e.g. LB 12345',
                      prefixIcon: Icon(
                        Icons.badge_outlined,
                        color: AppColors.textHint,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // ─── Documents info ───────────────
            GlassCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '📄 Documents',
                    style: AppTextStyles.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'The admin will contact you to '
                    'collect your documents:\n'
                    '• National ID / Passport\n'
                    '• Vehicle registration paper\n'
                    '• Driver photo',
                    style: AppTextStyles.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Document upload via app '
                    'coming soon.',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ─── Status message ───────────────
            if (_statusMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _statusMessage!.startsWith('✅')
                      ? AppColors.success.withValues(alpha: 0.1)
                      : AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _statusMessage!.startsWith('✅')
                        ? AppColors.success
                        : AppColors.error,
                  ),
                ),
                child: Text(
                  _statusMessage!,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: _statusMessage!.startsWith('✅')
                        ? AppColors.success
                        : AppColors.error,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ─── Submit button ────────────────
            AppButton(
              label: 'Submit for Review',
              isLoading: _isLoading,
              onPressed: _submit,
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
