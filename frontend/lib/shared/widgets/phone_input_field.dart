import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';

/// A country dial code.
class CountryCode {
  final String name;
  final String flag;
  final String dial;
  final int maxDigits;

  const CountryCode(this.name, this.flag, this.dial, this.maxDigits);
}

/// PhoneInputField
/// ────────────────────────────────────────────────────
/// Replaces free-text phone entry across the app.
///
/// The problem it solves: users typed things like `70123456`
/// (no country code) or `0096170123456`. The backend's
/// normalizePhone() would turn those into `+70123456`, and
/// Twilio rejected them with error 21211 ("not a valid phone
/// number") — a paid API call wasted and an OTP that never
/// arrived, with no obvious reason for the user.
///
/// Here the dial code is CHOSEN, never typed, and the national
/// part is digits-only with a per-country length cap. What
/// [onChanged] emits is always clean E.164 (`+96170123456`).
///
/// A leading zero in the national part is stripped automatically
/// — Lebanese users habitually write `03 123456`, and `+9610…`
/// is not a valid number.
class PhoneInputField extends StatefulWidget {
  final String label;
  final String? initialDial;
  final String? initialNumber;

  /// Emits the full E.164 number, e.g. `+96170123456`.
  /// Emits an empty string while the input is incomplete.
  final void Function(String e164) onChanged;

  const PhoneInputField({
    super.key,
    required this.label,
    required this.onChanged,
    this.initialDial,
    this.initialNumber,
  });

  @override
  State<PhoneInputField> createState() => _PhoneInputFieldState();
}

class _PhoneInputFieldState extends State<PhoneInputField> {
  // Lebanon first — it's the launch market and will be the
  // overwhelming majority of users. The rest cover the Lebanese
  // diaspora and neighbouring countries, which is where the
  // occasional non-local number actually comes from.
  static const List<CountryCode> _countries = [
    CountryCode('Lebanon', '🇱🇧', '+961', 8),
    CountryCode('Syria', '🇸🇾', '+963', 9),
    CountryCode('Jordan', '🇯🇴', '+962', 9),
    CountryCode('Iraq', '🇮🇶', '+964', 10),
    CountryCode('Saudi Arabia', '🇸🇦', '+966', 9),
    CountryCode('UAE', '🇦🇪', '+971', 9),
    CountryCode('Kuwait', '🇰🇼', '+965', 8),
    CountryCode('Qatar', '🇶🇦', '+974', 8),
    CountryCode('Egypt', '🇪🇬', '+20', 10),
    CountryCode('Turkey', '🇹🇷', '+90', 10),
    CountryCode('France', '🇫🇷', '+33', 9),
    CountryCode('Germany', '🇩🇪', '+49', 11),
    CountryCode('Sweden', '🇸🇪', '+46', 9),
    CountryCode('United Kingdom', '🇬🇧', '+44', 10),
    CountryCode('United States', '🇺🇸', '+1', 10),
    CountryCode('Canada', '🇨🇦', '+1', 10),
    CountryCode('Australia', '🇦🇺', '+61', 9),
    CountryCode('Brazil', '🇧🇷', '+55', 11),
  ];

  late CountryCode _selected;
  late TextEditingController _numberCtrl;

  @override
  void initState() {
    super.initState();
    _selected = _countries.firstWhere(
      (c) => c.dial == widget.initialDial,
      orElse: () => _countries.first,
    );
    _numberCtrl = TextEditingController(text: widget.initialNumber ?? '');
  }

  @override
  void dispose() {
    _numberCtrl.dispose();
    super.dispose();
  }

  void _emit() {
    var national = _numberCtrl.text.trim();
    // Users habitually write the national trunk prefix ("03 123456").
    // It must not appear in E.164.
    while (national.startsWith('0')) {
      national = national.substring(1);
    }
    widget.onChanged(national.isEmpty ? '' : '${_selected.dial}$national');
  }

  void _pickCountry() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: _countries.length,
          itemBuilder: (ctx, i) {
            final c = _countries[i];
            final isSelected = c.name == _selected.name;
            return ListTile(
              leading: Text(c.flag, style: const TextStyle(fontSize: 22)),
              title: Text(c.name, style: AppTextStyles.bodyMedium),
              trailing: Text(
                c.dial,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: isSelected ? AppColors.primary : AppColors.textHint,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal,
                ),
              ),
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _selected = c);
                _emit();
              },
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: AppTextStyles.caption),
        const SizedBox(height: 6),
        Row(
          children: [
            // ─── Country selector ───────────────────
            GestureDetector(
              onTap: _pickCountry,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
                decoration: BoxDecoration(
                  color: AppColors.glassWhite,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.glassBorder),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(_selected.flag, style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 6),
                  Text(_selected.dial,
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: AppColors.textPrimary)),
                  const Icon(Icons.arrow_drop_down_rounded,
                      color: AppColors.textHint, size: 20),
                ]),
              ),
            ),
            const SizedBox(width: 10),

            // ─── National number ────────────────────
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.glassWhite,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.glassBorder),
                ),
                child: TextField(
                  controller: _numberCtrl,
                  keyboardType: TextInputType.phone,
                  onChanged: (_) => _emit(),
                  // Digits only, capped at the country's length.
                  // Removes the whole class of malformed-number
                  // failures at the source.
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(_selected.maxDigits + 1),
                  ],
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: '70 123 456',
                    hintStyle: AppTextStyles.bodyMedium
                        .copyWith(color: AppColors.textHint),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 15),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
