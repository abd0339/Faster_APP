import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/app_button.dart';

class MerchantScheduleScreen extends StatefulWidget {
  const MerchantScheduleScreen({super.key});

  @override
  State<MerchantScheduleScreen> createState() => _MerchantScheduleScreenState();
}

class _MerchantScheduleScreenState extends State<MerchantScheduleScreen> {
  // Day order matching the backend enum
  static const _days = [
    'MONDAY',
    'TUESDAY',
    'WEDNESDAY',
    'THURSDAY',
    'FRIDAY',
    'SATURDAY',
    'SUNDAY',
  ];

  static const _dayLabels = {
    'MONDAY': 'Monday',
    'TUESDAY': 'Tuesday',
    'WEDNESDAY': 'Wednesday',
    'THURSDAY': 'Thursday',
    'FRIDAY': 'Friday',
    'SATURDAY': 'Saturday',
    'SUNDAY': 'Sunday',
  };

  static const _dayShort = {
    'MONDAY': 'MON',
    'TUESDAY': 'TUE',
    'WEDNESDAY': 'WED',
    'THURSDAY': 'THU',
    'FRIDAY': 'FRI',
    'SATURDAY': 'SAT',
    'SUNDAY': 'SUN',
  };

  // Schedule state: day → {isClosed, openTime, closeTime}
  final Map<String, Map<String, dynamic>> _schedule = {};
  bool _isLoading = true;
  bool _isSaving = false;
  Map<String, dynamic>? _storeStatus;

  @override
  void initState() {
    super.initState();
    _initSchedule();
    _loadSchedule();
  }

  // ─── Default schedule (all days 9am–10pm open) ───
  void _initSchedule() {
    for (final day in _days) {
      _schedule[day] = {
        'isClosed': false,
        'openTime': '09:00',
        'closeTime': '22:00',
      };
    }
  }

  // ─── LOAD ─────────────────────────────────────────
  Future<void> _loadSchedule() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        ApiService.instance.get(ApiConstants.schedule),
        ApiService.instance.get('${ApiConstants.schedule}/status'),
      ]);

      if (!mounted) return;

      final data = results[0].data;
      final list =
          data is List ? data : (data as Map?)?['content'] as List? ?? [];

      // Merge API data into schedule map
      for (final entry in list) {
        final day = entry['dayOfWeek'] as String?;
        if (day == null) continue;
        _schedule[day] = {
          'id': entry['id'],
          'isClosed': entry['isClosed'] ?? false,
          'openTime': _formatTime(entry['openTime']),
          'closeTime': _formatTime(entry['closeTime']),
        };
      }

      setState(() {
        _storeStatus = results[1].data as Map<String, dynamic>?;
      });
    } catch (e) {
      if (!mounted) return;
      _showError(ApiService.getErrorMessage(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── SAVE ALL ─────────────────────────────────────
  Future<void> _saveSchedule() async {
    if (!mounted) return;
    setState(() => _isSaving = true);
    try {
      // Build array of day objects — one per day
      final List<Map<String, dynamic>> body = _days.map((day) {
        final s = _schedule[day]!;
        final isClosed = s['isClosed'] as bool;
        return {
          'dayOfWeek': day,
          'isClosed': isClosed,
          // Only send times if the day is open
          if (!isClosed) 'openTime': s['openTime'],
          if (!isClosed) 'closeTime': s['closeTime'],
        };
      }).toList();

      await ApiService.instance.post(
        ApiConstants.scheduleBulk,
        data: body, // send the list directly, not wrapped
      );

      await _loadSchedule();
      if (mounted) _showSuccess('Schedule saved!');
    } catch (e) {
      if (mounted) _showError(ApiService.getErrorMessage(e));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ─── APPLY TO ALL OPEN DAYS ───────────────────────
  void _applyToAll(String openTime, String closeTime) {
    setState(() {
      for (final day in _days) {
        if (!(_schedule[day]!['isClosed'] as bool)) {
          _schedule[day]!['openTime'] = openTime;
          _schedule[day]!['closeTime'] = closeTime;
        }
      }
    });
    if (!kIsWeb) HapticFeedback.selectionClick();
    _showSuccess('Applied to all open days');
  }

  // ─── BUILD ────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isOpen = _storeStatus?['isOpen'] as bool? ?? false;

    return SafeArea(
      child: Column(
        children: [
          _buildHeader(isOpen),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary))
                : _buildBody(),
          ),
        ],
      ),
    );
  }

  // ─── HEADER ───────────────────────────────────────
  Widget _buildHeader(bool isOpen) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Store Hours', style: AppTextStyles.displayMedium),
                Row(children: [
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isOpen ? AppColors.accent : AppColors.error,
                    ),
                  ),
                  Text(
                    isOpen ? 'Currently Open' : 'Currently Closed',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: isOpen ? AppColors.accent : AppColors.error,
                    ),
                  ),
                ]),
              ],
            ),
          ),
          GestureDetector(
            onTap: _loadSchedule,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.glassWhite,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: const Icon(Icons.refresh_rounded,
                  color: AppColors.textPrimary, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  // ─── BODY ─────────────────────────────────────────
  Widget _buildBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 100),
      child: Column(
        children: [
          // ─── Quick apply card ──────────────
          _buildQuickApplyCard(),
          const SizedBox(height: 20),

          // ─── Day rows ─────────────────────
          ..._days.map((day) => _buildDayRow(day)),

          const SizedBox(height: 24),

          // ─── Save button ──────────────────
          AppButton(
            label: 'Save Schedule',
            icon: Icons.save_outlined,
            isLoading: _isSaving,
            onPressed: _saveSchedule,
          ),
        ],
      ),
    );
  }

  // ─── QUICK APPLY CARD ─────────────────────────────
  Widget _buildQuickApplyCard() {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.flash_on_rounded,
                color: AppColors.primary, size: 18),
            const SizedBox(width: 8),
            Text('Quick Apply', style: AppTextStyles.headlineSmall),
          ]),
          const SizedBox(height: 4),
          Text('Apply same hours to all open days',
              style: AppTextStyles.bodyMedium),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: _quickBtn('8am – 10pm', '08:00', '22:00'),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _quickBtn('9am – 11pm', '09:00', '23:00'),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: _quickBtn('10am – 12am', '10:00', '00:00'),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _quickBtn('24/7', '00:00', '23:59'),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _quickBtn(String label, String open, String close) {
    return GestureDetector(
      onTap: () => _applyToAll(open, close),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.glassWhite,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: AppTextStyles.caption.copyWith(
            color: AppColors.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  // ─── DAY ROW ──────────────────────────────────────
  Widget _buildDayRow(String day) {
    final s = _schedule[day]!;
    final isClosed = s['isClosed'] as bool;
    final isWeekend = day == 'SATURDAY' || day == 'SUNDAY';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(children: [
              // ─── Day pill ───────────────
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isClosed
                      ? AppColors.glassWhite
                      : isWeekend
                          ? AppColors.accent.withValues(alpha: 0.1)
                          : AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isClosed
                        ? AppColors.glassBorder
                        : isWeekend
                            ? AppColors.accent.withValues(alpha: 0.3)
                            : AppColors.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: Center(
                  child: Text(
                    _dayShort[day]!,
                    style: AppTextStyles.caption.copyWith(
                      fontWeight: FontWeight.w800,
                      color: isClosed
                          ? AppColors.textHint
                          : isWeekend
                              ? AppColors.accent
                              : AppColors.primary,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 12),

              // ─── Day name ───────────────
              Expanded(
                child: Text(
                  _dayLabels[day]!,
                  style: AppTextStyles.headlineSmall.copyWith(
                    color:
                        isClosed ? AppColors.textHint : AppColors.textPrimary,
                  ),
                ),
              ),

              // ─── Closed toggle ──────────
              Row(children: [
                Text(
                  isClosed ? 'Closed' : 'Open',
                  style: AppTextStyles.caption.copyWith(
                    color: isClosed ? AppColors.error : AppColors.accent,
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    if (!kIsWeb) HapticFeedback.lightImpact();
                    setState(() => s['isClosed'] = !isClosed);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 44,
                    height: 26,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: !isClosed
                          ? AppColors.accent.withValues(alpha: 0.8)
                          : AppColors.glassWhite,
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(
                        color: !isClosed
                            ? AppColors.accent
                            : AppColors.glassBorder,
                      ),
                    ),
                    child: AnimatedAlign(
                      duration: const Duration(milliseconds: 200),
                      alignment: !isClosed
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: !isClosed
                              ? AppColors.background
                              : AppColors.textHint,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ),
              ]),
            ]),

            // ─── Time pickers (only if open) ─
            if (!isClosed) ...[
              const SizedBox(height: 12),
              const Divider(color: AppColors.glassBorder, height: 1),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: _timePicker(
                    label: 'Opens',
                    time: s['openTime'] as String,
                    icon: Icons.wb_sunny_outlined,
                    color: AppColors.accent,
                    onChanged: (t) => setState(() => s['openTime'] = t),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('→',
                      style: AppTextStyles.headlineMedium
                          .copyWith(color: AppColors.textHint)),
                ),
                Expanded(
                  child: _timePicker(
                    label: 'Closes',
                    time: s['closeTime'] as String,
                    icon: Icons.nights_stay_outlined,
                    color: AppColors.primary,
                    onChanged: (t) => setState(() => s['closeTime'] = t),
                  ),
                ),
              ]),
            ],
          ],
        ),
      ),
    );
  }

  // ─── TIME PICKER ──────────────────────────────────
  Widget _timePicker({
    required String label,
    required String time,
    required IconData icon,
    required Color color,
    required ValueChanged<String> onChanged,
  }) {
    return GestureDetector(
      onTap: () async {
        final parsed = _parseTime(time);
        final picked = await showTimePicker(
          context: context,
          initialTime: parsed,
          builder: (ctx, child) => Theme(
            data: ThemeData.dark().copyWith(
              colorScheme: const ColorScheme.dark(
                primary: AppColors.primary,
                surface: AppColors.surface,
              ),
            ),
            child: child!,
          ),
        );
        if (picked != null) {
          onChanged(
            '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}',
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: color, size: 14),
              const SizedBox(width: 4),
              Text(label, style: AppTextStyles.caption.copyWith(color: color)),
            ]),
            const SizedBox(height: 4),
            Text(
              _formatDisplay(time),
              style: AppTextStyles.headlineSmall.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── HELPERS ──────────────────────────────────────
  TimeOfDay _parseTime(String time) {
    final parts = time.split(':');
    if (parts.length < 2) return const TimeOfDay(hour: 9, minute: 0);
    return TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 9,
      minute: int.tryParse(parts[1]) ?? 0,
    );
  }

  String _formatTime(dynamic raw) {
    if (raw == null) return '09:00';
    final s = raw.toString();
    // Backend returns "HH:mm:ss" → take "HH:mm"
    if (s.contains(':')) {
      final parts = s.split(':');
      return '${parts[0].padLeft(2, '0')}:${parts[1].padLeft(2, '0')}';
    }
    return s;
  }

  String _formatDisplay(String time) {
    final parts = time.split(':');
    if (parts.length < 2) return time;
    int hour = int.tryParse(parts[0]) ?? 0;
    final min = parts[1].padLeft(2, '0');
    final period = hour < 12 ? 'AM' : 'PM';
    hour = hour % 12;
    if (hour == 0) hour = 12;
    return '$hour:$min $period';
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: AppColors.success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: AppColors.error,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }
}
