import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:dio/dio.dart' as dio;
import 'package:image_picker/image_picker.dart';
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

// FIX: this screen now actually uploads driver documents
// (profile photo, national ID, license front/back) to the
// backend's private storage — previously it only showed
// decorative text rows and told the driver the admin would
// "contact you on WhatsApp to collect your documents",
// which was never true; the backend has supported real
// uploads for a while but nothing in this screen called it.
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
  // 0=vehicle, 1=plate, 2=documents, 3=location, 4=waiting
  int _currentStep = 0;
  String _selectedVehicle = 'MOTO';
  String _selectedMode = 'PACKAGE';
  final _plateCtrl = TextEditingController();

  // Location
  double? _lat;
  double? _lng;
  String _locationText = '';
  bool _isDetectingLocation = false;

  // ─── Document upload state ────────────────────────
  // Bytes picked THIS session (shown as a live preview)
  final Map<String, Uint8List> _docPreviews = {};
  // Which docs are confirmed uploaded — either from a
  // previous session (loaded via /api/driver/status) or
  // just now in this session
  final Map<String, bool> _docUploaded = {
    'PROFILE_PHOTO': false,
    'NATIONAL_ID': false,
    'LICENSE_FRONT': false,
    'LICENSE_BACK': false,
  };
  // Which doc is actively uploading right now (disables its row)
  String? _uploadingDocType;

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

  // Document types shown, in order — label + required flag
  static const _docTypes = [
    {'type': 'PROFILE_PHOTO', 'label': 'Your Photo', 'required': true},
    {'type': 'NATIONAL_ID', 'label': 'National ID / Passport', 'required': true},
    {'type': 'LICENSE_FRONT', 'label': "Driver's License (front)", 'required': false},
    {'type': 'LICENSE_BACK', 'label': "Driver's License (back)", 'required': false},
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
    super.dispose();
  }

  // ─── Check if already submitted / which docs exist ─
  Future<void> _checkExistingStatus() async {
    try {
      final res = await ApiService.instance.get(ApiConstants.driverStatus);
      final data = res.data as Map<String, dynamic>?;
      final verStatus = data?['verificationStatus'] as String?;

      if (!mounted) return;
      setState(() {
        _docUploaded['PROFILE_PHOTO'] = data?['hasProfilePhoto'] == true;
        _docUploaded['NATIONAL_ID'] = data?['hasNationalId'] == true;
        _docUploaded['LICENSE_FRONT'] = data?['hasLicenseFront'] == true;
        _docUploaded['LICENSE_BACK'] = data?['hasLicenseBack'] == true;
      });

      if (verStatus == 'SUBMITTED' ||
          verStatus == 'APPROVED' ||
          verStatus == 'REJECTED') {
        if (!mounted) return;
        setState(() {
          _submittedStatus = verStatus;
          _currentStep = 4;
        });
      }
    } catch (_) {}
  }

  // ─── Pick + upload one document ───────────────────
  Future<void> _pickAndUploadDoc(String docType, ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() {
        _docPreviews[docType] = bytes;
        _uploadingDocType = docType;
      });

      final filename =
          picked.name.isNotEmpty ? picked.name : '$docType.jpg';

      await ApiService.instance.uploadImageBytes(
        ApiConstants.driverDocumentUpload(docType),
        bytes,
        filename,
        'file',
      );

      if (!mounted) return;
      setState(() {
        _docUploaded[docType] = true;
        _uploadingDocType = null;
      });
      if (!kIsWeb) HapticFeedback.lightImpact();
    } catch (e) {
      if (mounted) {
        setState(() => _uploadingDocType = null);
        _showError(ApiService.getErrorMessage(e));
      }
    }
  }

  // ─── Show camera/gallery choice for a doc ─────────
  void _showDocPickerSheet(String docType) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded,
                  color: AppColors.primary),
              title: Text('Take a photo', style: AppTextStyles.bodyMedium),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndUploadDoc(docType, ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded,
                  color: AppColors.primary),
              title: Text('Choose from gallery',
                  style: AppTextStyles.bodyMedium),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndUploadDoc(docType, ImageSource.gallery);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
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
    // Mirror the backend's requirement so the driver gets
    // instant feedback instead of a failed round trip —
    // the backend still enforces this regardless.
    if (_docUploaded['PROFILE_PHOTO'] != true ||
        _docUploaded['NATIONAL_ID'] != true) {
      _showError('Please upload your photo and national ID first');
      setState(() => _currentStep = 2);
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
        _currentStep = 4;
      });

      _animCtrl.reset();
      _animCtrl.forward();
    } catch (e) {
      if (mounted) {
        setState(() => _errorMsg = ApiService.getErrorMessage(e));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ─── GO TO NEXT STEP ──────────────────────────────
  void _nextStep() {
    if (_currentStep < 4) {
      if (!kIsWeb) HapticFeedback.selectionClick();
      _animCtrl.reset();
      setState(() => _currentStep++);
      _animCtrl.forward();
      // Auto-detect location on the location step
      if (_currentStep == 3 && !kIsWeb) {
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
            if (_currentStep < 4) _buildProgressBar(),
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
                  _currentStep == 4
                      ? _submittedStatus == 'APPROVED'
                          ? 'Account Approved!'
                          : _submittedStatus == 'REJECTED'
                              ? 'Application Rejected'
                              : 'Under Review'
                      : 'Step ${_currentStep + 1} of 4',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: _currentStep == 4 && _submittedStatus == 'APPROVED'
                        ? AppColors.accent
                        : AppColors.textHint,
                  ),
                ),
              ],
            ),
          ),
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
    const steps = ['Vehicle', 'Plate', 'Docs', 'Location'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: Row(
        children: List.generate(4, (i) {
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
                if (i < 3) const SizedBox(width: 8),
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
        return _buildDocumentsStep();
      case 3:
        return _buildLocationStep();
      case 4:
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
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              const Icon(Icons.info_outline_rounded,
                  color: AppColors.primary, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Next you'll upload your photo and ID "
                  'directly in the app — no need to send '
                  'anything separately.',
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.primary),
                ),
              ),
            ]),
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

  // ─── STEP 3: DOCUMENTS (NEW — real upload) ────────
  Widget _buildDocumentsStep() {
    final requiredDone = _docUploaded['PROFILE_PHOTO'] == true &&
        _docUploaded['NATIONAL_ID'] == true;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Text('Upload Your Documents', style: AppTextStyles.displayMedium),
          const SizedBox(height: 8),
          Text(
            'Photo and National ID are required. '
            "Driver's license is optional for now.",
            style: AppTextStyles.bodyMedium,
          ),
          const SizedBox(height: 24),
          ..._docTypes.map((doc) => _docUploadRow(
                docType: doc['type'] as String,
                label: doc['label'] as String,
                required: doc['required'] as bool,
              )),
          const SizedBox(height: 32),
          AppButton(
            label: 'Continue',
            icon: Icons.arrow_forward_rounded,
            onPressed: requiredDone ? _nextStep : null,
          ),
          if (!requiredDone) ...[
            const SizedBox(height: 10),
            Text(
              'Upload your photo and National ID to continue.',
              style: AppTextStyles.caption
                  .copyWith(color: AppColors.textHint),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _docUploadRow({
    required String docType,
    required String label,
    required bool required,
  }) {
    final uploaded = _docUploaded[docType] == true;
    final preview = _docPreviews[docType];
    final isUploading = _uploadingDocType == docType;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GestureDetector(
        onTap: isUploading ? null : () => _showDocPickerSheet(docType),
        child: GlassCard(
          padding: const EdgeInsets.all(14),
          borderColor: uploaded ? AppColors.accent.withValues(alpha: 0.4) : null,
          child: Row(
            children: [
              // Thumbnail or placeholder icon
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 56,
                  height: 56,
                  color: AppColors.glassWhite,
                  child: isUploading
                      ? const Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppColors.primary),
                          ),
                        )
                      : preview != null
                          ? Image.memory(preview, fit: BoxFit.cover)
                          : Icon(
                              uploaded
                                  ? Icons.check_circle_rounded
                                  : Icons.add_a_photo_outlined,
                              color: uploaded
                                  ? AppColors.accent
                                  : AppColors.textHint,
                            ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(label, style: AppTextStyles.labelLarge),
                        if (required) ...[
                          const SizedBox(width: 4),
                          Text('*',
                              style: AppTextStyles.labelLarge
                                  .copyWith(color: AppColors.error)),
                        ],
                      ],
                    ),
                    Text(
                      uploaded
                          ? 'Uploaded'
                          : required
                              ? 'Required'
                              : 'Optional',
                      style: AppTextStyles.caption.copyWith(
                        color: uploaded
                            ? AppColors.accent
                            : AppColors.textHint,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                uploaded ? Icons.refresh_rounded : Icons.chevron_right_rounded,
                color: AppColors.textHint,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── STEP 4: LOCATION ─────────────────────────────
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
          AppInput(
            controller: TextEditingController(text: _locationText),
            hint: 'Or type your area (e.g. Tripoli, Mina)',
            label: 'Your Area',
            prefixIcon: Icons.place_outlined,
            onChanged: (v) => setState(() => _locationText = v),
          ),
          const SizedBox(height: 32),
          AppButton(
            label: 'Submit for Review',
            icon: Icons.send_rounded,
            isLoading: _isSubmitting,
            color: AppColors.accent,
            textColor: AppColors.background,
            onPressed: _submitVerification,
          ),
        ],
      ),
    );
  }

  // ─── STEP 5: WAITING / STATUS ─────────────────────
  Widget _buildWaitingStep() {
    final isApproved = _submittedStatus == 'APPROVED';
    final isRejected = _submittedStatus == 'REJECTED';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
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
                          'Please contact support for more information.'
                      : 'Your application and documents are under '
                          "review. We'll notify you as soon as an "
                          'admin has reviewed them.',
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