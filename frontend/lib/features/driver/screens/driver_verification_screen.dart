import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:dio/dio.dart' as dio;
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/location_service.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_input.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';
import '../../../core/constants/api_constants.dart';
import 'driver_dashboard_screen.dart';

class DriverVerificationScreen extends StatefulWidget {
  const DriverVerificationScreen({super.key});

  @override
  State<DriverVerificationScreen> createState() =>
      _DriverVerificationScreenState();
}

class _DriverVerificationScreenState extends State<DriverVerificationScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  // Form state
  int _currentStep = 0; // 0=vehicle, 1=plate, 2=location, 3=waiting
  String _selectedVehicle = 'MOTO';
  String _selectedMode = 'PACKAGE';
  final _plateCtrl = TextEditingController();
  final _nameCtrl = TextEditingController(); // driver name for WhatsApp

  // Location
  double? _lat;
  double? _lng;
  String _locationText = '';
  bool _isDetectingLocation = false;

  // Submission
  bool _isSubmitting = false;
  String? _submittedStatus; // null | 'SUBMITTED' | 'APPROVED' | 'REJECTED'
  String? _errorMsg;

  static const _vehicles = [
    {
      'value': 'MOTO',
      'label': 'Motorcycle',
      'icon': '🏍️',
      'desc': 'Best for packages & food'
    },
    {
      'value': 'CAR',
      'label': 'Car',
      'icon': '🚗',
      'desc': 'Packages, rides & people'
    },
    {
      'value': 'TOKTOK',
      'label': 'Toktok',
      'icon': '🛺',
      'desc': 'Short rides & packages'
    },
    {
      'value': 'VAN',
      'label': 'Van',
      'icon': '🚐',
      'desc': 'Large packages & groups'
    },
  ];

  static const _modes = [
    {
      'value': 'PACKAGE',
      'label': 'Package Delivery',
      'icon': '📦',
      'desc': 'Deliver food & goods'
    },
    {
      'value': 'PEOPLE',
      'label': 'People Transport',
      'icon': '👥',
      'desc': 'Drive passengers'
    },
    {
      'value': 'HYBRID',
      'label': 'Both',
      'icon': '⚡',
      'desc': 'Packages & passengers'
    },
  ];

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut),
    );
    _animCtrl.forward();
    _checkExistingStatus();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _plateCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  // ─── Check if already submitted ───────────────────
  Future<void> _checkExistingStatus() async {
    try {
      final res = await ApiService.instance.get(ApiConstants.driverStatus);
      final data = res.data as Map<String, dynamic>?;
      final verStatus = data?['verificationStatus'] as String?;
      if (verStatus == 'SUBMITTED' ||
          verStatus == 'APPROVED' ||
          verStatus == 'REJECTED') {
        if (!mounted) return;
        setState(() {
          _submittedStatus = verStatus;
          _currentStep = 3;
        });
      }
    } catch (_) {}
  }

  // ─── Detect location ──────────────────────────────
  Future<void> _detectLocation() async {
    if (!mounted) return;
    setState(() => _isDetectingLocation = true);
    try {
      final position = await LocationService.instance.getCurrentPosition();
      if (position == null || !mounted) return;

      setState(() {
        _lat = position.latitude;
        _lng = position.longitude;
      });

      try {
        final geoRes = await dio.Dio().get(
          'https://nominatim.openstreetmap.org/reverse',
          queryParameters: {
            'format': 'json',
            'lat': position.latitude.toString(),
            'lon': position.longitude.toString(),
          },
          options: dio.Options(
            headers: {
              'Accept-Language': 'en',
              'User-Agent': 'FasterApp/1.0',
            },
            receiveTimeout: const Duration(seconds: 5),
          ),
        );
        final addr = geoRes.data?['display_name'];
        if (addr != null && mounted) {
          setState(() => _locationText = addr.toString());
        }
      } catch (_) {
        if (mounted) {
          setState(
              () => _locationText = '${position.latitude.toStringAsFixed(4)}, '
                  '${position.longitude.toStringAsFixed(4)}');
        }
      }
    } catch (_) {
      if (mounted) _showError('Location unavailable. Type manually.');
    } finally {
      if (mounted) setState(() => _isDetectingLocation = false);
    }
  }

  // ─── Submit verification ──────────────────────────
  Future<void> _submitVerification() async {
    if (_plateCtrl.text.trim().isEmpty) {
      _showError('Please enter your plate number');
      return;
    }
    if (!mounted) return;
    setState(() {
      _isSubmitting = true;
      _errorMsg = null;
    });

    try {
      await ApiService.instance.post(
        '/api/driver/profile',
        data: {
          'vehicleType': _selectedVehicle,
          'vehiclePlate': _plateCtrl.text.trim().toUpperCase(),
          'driverMode': _selectedMode,
          'currentLat': _lat,
          'currentLng': _lng,
          'currentLocation': _locationText,
        },
      );

      if (!mounted) return;
      setState(() {
        _submittedStatus = 'SUBMITTED';
        _currentStep = 3;
      });

      // Animate to waiting screen
      _animCtrl.reset();
      _animCtrl.forward();

      // Send WhatsApp notification to admin
      // Admin number from env — using placeholder here
      // In production: read from backend config endpoint
      _notifyAdminWhatsApp();
    } catch (e) {
      if (mounted) {
        setState(() => _errorMsg = ApiService.getErrorMessage(e));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ─── WhatsApp notification to admin ───────────────
  void _notifyAdminWhatsApp() {
    // This opens WhatsApp with pre-filled message to admin
    // In production: backend sends WhatsApp via Twilio/Meta API
    // For now: open WhatsApp with message (web/mobile)
    // Admin WhatsApp number — update in production
    const adminPhone = '+96170000000'; // ← update this
    final msg = Uri.encodeComponent(
      '🆕 New Driver Verification Request\n'
      '─────────────────────\n'
      '🏍️ Vehicle: $_selectedVehicle\n'
      '🔖 Plate: ${_plateCtrl.text.trim().toUpperCase()}\n'
      '📦 Mode: $_selectedMode\n'
      '📍 Location: $_locationText\n'
      '─────────────────────\n'
      'Please review in the Admin Panel and approve/reject.',
    );

    if (kIsWeb) {
      // Web: open WhatsApp web
      // url_launcher would be used here in production
      debugPrint('WhatsApp URL: https://wa.me/$adminPhone?text=$msg');
    } else {
      // Mobile: open WhatsApp app
      debugPrint('wa.me/$adminPhone?text=$msg');
    }
  }

  // ─── GO TO NEXT STEP ──────────────────────────────
  void _nextStep() {
    if (_currentStep < 3) {
      if (!kIsWeb) HapticFeedback.selectionClick();
      _animCtrl.reset();
      setState(() => _currentStep++);
      _animCtrl.forward();
      // Auto-detect location on step 2
      if (_currentStep == 2 && !kIsWeb) {
        _detectLocation();
      }
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      _animCtrl.reset();
      setState(() => _currentStep--);
      _animCtrl.forward();
    }
  }

  // ─── BUILD ────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            if (_currentStep < 3) _buildProgressBar(),
            Expanded(
              child: FadeTransition(
                opacity: _fadeAnim,
                child: _buildCurrentStep(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── HEADER ───────────────────────────────────────
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: Row(
        children: [
          if (_currentStep > 0 && _submittedStatus == null)
            GestureDetector(
              onTap: _prevStep,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.glassWhite,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.glassBorder),
                ),
                child: const Icon(Icons.arrow_back_rounded,
                    color: AppColors.textPrimary, size: 20),
              ),
            )
          else
            const SizedBox(width: 40),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Driver Verification',
                    style: AppTextStyles.headlineMedium),
                Text(
                  _currentStep == 3
                      ? _submittedStatus == 'APPROVED'
                          ? 'Account Approved!'
                          : _submittedStatus == 'REJECTED'
                              ? 'Application Rejected'
                              : 'Under Review'
                      : 'Step ${_currentStep + 1} of 3',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: _currentStep == 3 && _submittedStatus == 'APPROVED'
                        ? AppColors.accent
                        : AppColors.textHint,
                  ),
                ),
              ],
            ),
          ),
          // Logout
          GestureDetector(
            onTap: () => context.read<AuthBloc>().add(LogoutRequested()),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.glassWhite,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: const Icon(Icons.logout_rounded,
                  color: AppColors.error, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  // ─── PROGRESS BAR ─────────────────────────────────
  Widget _buildProgressBar() {
    const steps = ['Vehicle', 'Plate', 'Location'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: Row(
        children: List.generate(3, (i) {
          final done = i < _currentStep;
          final active = i == _currentStep;
          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        height: 4,
                        decoration: BoxDecoration(
                          color: done || active
                              ? AppColors.primary
                              : AppColors.glassWhite,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        steps[i],
                        style: AppTextStyles.caption.copyWith(
                          color: done || active
                              ? AppColors.primary
                              : AppColors.textHint,
                          fontWeight:
                              active ? FontWeight.w700 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
                if (i < 2) const SizedBox(width: 8),
              ],
            ),
          );
        }),
      ),
    );
  }

  // ─── STEP ROUTER ──────────────────────────────────
  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case 0:
        return _buildVehicleStep();
      case 1:
        return _buildPlateStep();
      case 2:
        return _buildLocationStep();
      case 3:
        return _buildWaitingStep();
      default:
        return _buildVehicleStep();
    }
  }

  // ─── STEP 1: VEHICLE TYPE ─────────────────────────
  Widget _buildVehicleStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Text('What do you drive?', style: AppTextStyles.displayMedium),
          const SizedBox(height: 8),
          Text(
            'Choose your vehicle type to get matched '
            'with the right orders.',
            style: AppTextStyles.bodyMedium,
          ),
          const SizedBox(height: 28),

          // Vehicle cards
          ...(_vehicles.map((v) {
            final isSelected = _selectedVehicle == v['value'];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GestureDetector(
                onTap: () {
                  if (!kIsWeb) HapticFeedback.selectionClick();
                  setState(() => _selectedVehicle = v['value'] as String);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary.withValues(alpha: 0.12)
                        : AppColors.glassWhite,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.glassBorder,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(v['icon'] as String,
                          style: const TextStyle(fontSize: 32)),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(v['label'] as String,
                                style: AppTextStyles.headlineSmall.copyWith(
                                  color: isSelected
                                      ? AppColors.primary
                                      : AppColors.textPrimary,
                                )),
                            Text(v['desc'] as String,
                                style: AppTextStyles.bodyMedium),
                          ],
                        ),
                      ),
                      if (isSelected)
                        const Icon(Icons.check_circle_rounded,
                            color: AppColors.primary, size: 22),
                    ],
                  ),
                ),
              ),
            );
          })),

          const SizedBox(height: 24),

          // Driver mode
          Text('Delivery Mode', style: AppTextStyles.headlineSmall),
          const SizedBox(height: 12),

          ...(_modes.map((m) {
            final isSelected = _selectedMode == m['value'];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GestureDetector(
                onTap: () =>
                    setState(() => _selectedMode = m['value'] as String),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.accent.withValues(alpha: 0.1)
                        : AppColors.glassWhite,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color:
                          isSelected ? AppColors.accent : AppColors.glassBorder,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(m['icon'] as String,
                          style: const TextStyle(fontSize: 24)),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(m['label'] as String,
                                style: AppTextStyles.labelLarge.copyWith(
                                  color: isSelected
                                      ? AppColors.accent
                                      : AppColors.textPrimary,
                                )),
                            Text(m['desc'] as String,
                                style: AppTextStyles.bodyMedium),
                          ],
                        ),
                      ),
                      if (isSelected)
                        const Icon(Icons.check_circle_rounded,
                            color: AppColors.accent, size: 20),
                    ],
                  ),
                ),
              ),
            );
          })),

          const SizedBox(height: 32),

          AppButton(
            label: 'Continue',
            icon: Icons.arrow_forward_rounded,
            onPressed: _nextStep,
          ),
        ],
      ),
    );
  }

  // ─── STEP 2: PLATE NUMBER ─────────────────────────
  Widget _buildPlateStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Text('Vehicle Details', style: AppTextStyles.displayMedium),
          const SizedBox(height: 8),
          Text(
            'Your plate number is used to verify '
            'your vehicle during admin review.',
            style: AppTextStyles.bodyMedium,
          ),
          const SizedBox(height: 32),

          // Selected vehicle preview
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text(
                  _vehicles.firstWhere((v) => v['value'] == _selectedVehicle,
                      orElse: () => _vehicles[0])['icon'] as String,
                  style: const TextStyle(fontSize: 36),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _vehicles.firstWhere(
                          (v) => v['value'] == _selectedVehicle,
                          orElse: () => _vehicles[0])['label'] as String,
                      style: AppTextStyles.headlineSmall,
                    ),
                    Text(
                      'Mode: $_selectedMode',
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: AppColors.accent),
                    ),
                  ],
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _prevStep,
                  child: Text('Change',
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.primary)),
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          Text('Plate Number', style: AppTextStyles.headlineSmall),
          const SizedBox(height: 12),

          // Plate input — large, styled
          Container(
            decoration: BoxDecoration(
              color: AppColors.glassWhite,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _plateCtrl.text.isNotEmpty
                    ? AppColors.primary
                    : AppColors.glassBorder,
              ),
            ),
            padding: const EdgeInsets.all(20),
            child: TextField(
              controller: _plateCtrl,
              onChanged: (_) => setState(() {}),
              style: AppTextStyles.headlineLarge.copyWith(
                letterSpacing: 6,
                color: AppColors.primary,
              ),
              textAlign: TextAlign.center,
              textCapitalization: TextCapitalization.characters,
              keyboardType: TextInputType.text,
              decoration: InputDecoration(
                hintText: 'A 12345',
                hintStyle: AppTextStyles.headlineLarge.copyWith(
                  color: AppColors.textHint.withValues(alpha: 0.5),
                  letterSpacing: 6,
                ),
                border: InputBorder.none,
              ),
            ),
          ),

          const SizedBox(height: 12),
          Text(
            'Enter your plate number exactly as it appears on your vehicle.',
            style: AppTextStyles.caption,
          ),

          const SizedBox(height: 28),

          // Documents info card
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.info_outline_rounded,
                      color: AppColors.warning, size: 18),
                  const SizedBox(width: 8),
                  Text('Documents Required',
                      style: AppTextStyles.headlineSmall
                          .copyWith(color: AppColors.warning)),
                ]),
                const SizedBox(height: 12),
                _docRow('National ID or Passport'),
                _docRow('Vehicle Registration Paper'),
                _docRow('Clear photo of yourself'),
                const SizedBox(height: 8),
                Text(
                  'The admin will contact you on WhatsApp '
                  'to collect your documents after submission.',
                  style:
                      AppTextStyles.caption.copyWith(color: AppColors.primary),
                ),
              ],
            ),
          ),

          if (_errorMsg != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: AppColors.error.withValues(alpha: 0.4)),
              ),
              child: Text(_errorMsg!,
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.error)),
            ),
          ],

          const SizedBox(height: 32),

          AppButton(
            label: 'Continue',
            icon: Icons.arrow_forward_rounded,
            onPressed: _plateCtrl.text.trim().isEmpty ? null : _nextStep,
          ),
        ],
      ),
    );
  }

  Widget _docRow(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          const Icon(Icons.check_rounded, size: 14, color: AppColors.accent),
          const SizedBox(width: 8),
          Text(text, style: AppTextStyles.bodyMedium),
        ],
      ),
    );
  }

  // ─── STEP 3: LOCATION ─────────────────────────────
  Widget _buildLocationStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Text('Your Location', style: AppTextStyles.displayMedium),
          const SizedBox(height: 8),
          Text(
            'We use your current location to match you '
            'with nearby orders when you go online.',
            style: AppTextStyles.bodyMedium,
          ),
          const SizedBox(height: 32),

          // GPS detect button
          GestureDetector(
            onTap: kIsWeb ? null : _detectLocation,
            child: GlassCard(
              padding: const EdgeInsets.all(20),
              borderColor:
                  _lat != null ? AppColors.accent.withValues(alpha: 0.4) : null,
              child: Column(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _lat != null
                          ? AppColors.accent.withValues(alpha: 0.15)
                          : AppColors.primary.withValues(alpha: 0.1),
                      border: Border.all(
                        color: _lat != null
                            ? AppColors.accent
                            : AppColors.primary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: _isDetectingLocation
                        ? const Center(
                            child: CircularProgressIndicator(
                                color: AppColors.primary, strokeWidth: 2))
                        : Icon(
                            _lat != null
                                ? Icons.location_on_rounded
                                : Icons.my_location_rounded,
                            color: _lat != null
                                ? AppColors.accent
                                : AppColors.primary,
                            size: 30,
                          ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _lat != null
                        ? 'Location Detected!'
                        : kIsWeb
                            ? 'GPS not available on web'
                            : 'Tap to detect location',
                    style: AppTextStyles.headlineSmall.copyWith(
                      color:
                          _lat != null ? AppColors.accent : AppColors.primary,
                    ),
                  ),
                  if (_locationText.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      _locationText,
                      style: AppTextStyles.bodyMedium,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Manual location input
          AppInput(
            controller: TextEditingController(text: _locationText),
            hint: 'Or type your area (e.g. Tripoli, Mina)',
            label: 'Your Area',
            prefixIcon: Icons.place_outlined,
            onChanged: (v) => setState(() => _locationText = v),
          ),

          const SizedBox(height: 32),

          // Submit
          AppButton(
            label: 'Submit for Review',
            icon: Icons.send_rounded,
            isLoading: _isSubmitting,
            color: AppColors.accent,
            textColor: AppColors.background,
            onPressed: _submitVerification,
          ),

          const SizedBox(height: 12),

          GlassCard(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const Icon(Icons.chat_rounded,
                    color: Color(0xFF25D366), size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'After submitting, the admin will '
                    'contact you on WhatsApp to complete '
                    'your verification.',
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── STEP 4: WAITING / STATUS ─────────────────────
  Widget _buildWaitingStep() {
    final isApproved = _submittedStatus == 'APPROVED';
    final isRejected = _submittedStatus == 'REJECTED';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Status icon
            AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isApproved
                    ? AppColors.accent.withValues(alpha: 0.15)
                    : isRejected
                        ? AppColors.error.withValues(alpha: 0.15)
                        : AppColors.warning.withValues(alpha: 0.15),
                border: Border.all(
                  color: isApproved
                      ? AppColors.accent
                      : isRejected
                          ? AppColors.error
                          : AppColors.warning,
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: (isApproved
                            ? AppColors.accent
                            : isRejected
                                ? AppColors.error
                                : AppColors.warning)
                        .withValues(alpha: 0.3),
                    blurRadius: 30,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: Center(
                child: Icon(
                  isApproved
                      ? Icons.check_rounded
                      : isRejected
                          ? Icons.close_rounded
                          : Icons.hourglass_top_rounded,
                  size: 48,
                  color: isApproved
                      ? AppColors.accent
                      : isRejected
                          ? AppColors.error
                          : AppColors.warning,
                ),
              ),
            ),

            const SizedBox(height: 32),

            Text(
              isApproved
                  ? '🎉 You\'re Approved!'
                  : isRejected
                      ? 'Application Rejected'
                      : 'Application Submitted!',
              style: AppTextStyles.displayMedium.copyWith(
                color: isApproved
                    ? AppColors.accent
                    : isRejected
                        ? AppColors.error
                        : AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 16),

            Text(
              isApproved
                  ? 'Your account is approved. You can now '
                      'go online and start receiving orders!'
                  : isRejected
                      ? 'Your application was not approved. '
                          'Please contact the admin on WhatsApp '
                          'for more information.'
                      : 'Your application is under review.\n'
                          'The admin will contact you on WhatsApp '
                          'within 24 hours to complete verification.',
              style: AppTextStyles.bodyMedium,
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 32),

            if (isApproved) ...[
              AppButton(
                label: 'Go to Dashboard',
                icon: Icons.dashboard_rounded,
                color: AppColors.accent,
                textColor: AppColors.background,
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const DriverDashboardScreen(),
                    ),
                  );
                },
              ),
            ] else if (isRejected) ...[
              AppButton(
                label: 'Contact Admin on WhatsApp',
                icon: Icons.chat_rounded,
                color: const Color(0xFF25D366),
                textColor: AppColors.background,
                onPressed: () {
                  // Open WhatsApp to admin
                  debugPrint('Opening WhatsApp to admin...');
                },
              ),
              const SizedBox(height: 12),
              AppButton(
                label: 'Resubmit Application',
                icon: Icons.refresh_rounded,
                color: AppColors.primary,
                textColor: AppColors.background,
                onPressed: () {
                  setState(() {
                    _submittedStatus = null;
                    _currentStep = 0;
                    _plateCtrl.clear();
                    _lat = null;
                    _lng = null;
                    _locationText = '';
                  });
                  _animCtrl.reset();
                  _animCtrl.forward();
                },
              ),
            ] else ...[
              // Pending — WhatsApp contact
              GlassCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(children: [
                      const Icon(Icons.chat_rounded,
                          color: Color(0xFF25D366), size: 24),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('WhatsApp Notification Sent',
                                style: AppTextStyles.labelLarge),
                            Text(
                              'Admin has been notified of '
                              'your application.',
                              style: AppTextStyles.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ]),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Check status button
              AppButton(
                label: 'Check Status',
                icon: Icons.refresh_rounded,
                onPressed: _checkExistingStatus,
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─── HELPERS ──────────────────────────────────────
  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: AppColors.error,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }
}

// ─── Keep for import compatibility ────────────────────
// This file replaces driver_profile_screen.dart
// No exports needed — AppRouter imports DriverVerificationScreen
