import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/widgets/glass_card.dart';
import 'customer_store_menu_screen.dart';

class CustomerStoresScreen extends StatefulWidget {
  const CustomerStoresScreen({super.key});

  @override
  State<CustomerStoresScreen> createState() =>
      _CustomerStoresScreenState();
}

class _CustomerStoresScreenState
    extends State<CustomerStoresScreen> {
  List<dynamic> _merchants = [];
  bool _isLoading = true;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      // Public endpoint — no auth needed
      final res = await ApiService.instance
          .get('/api/admin/merchants');
      if (!mounted) return;
      final d = res.data;
      setState(() =>
          _merchants = d is List ? d : []);
    } catch (e) {
      if (!mounted) return;
      _showError(ApiService.getErrorMessage(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<dynamic> get _filtered {
    if (_search.isEmpty) return _merchants;
    return _merchants.where((m) {
      final name = (m['fullName'] as String? ?? '')
          .toLowerCase();
      return name.contains(_search.toLowerCase());
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ─── Search bar ──────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(
              24, 16, 24, 12),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.glassWhite,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: AppColors.glassBorder),
            ),
            child: TextField(
              onChanged: (v) =>
                  setState(() => _search = v),
              style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search stores...',
                hintStyle: AppTextStyles.bodyMedium,
                prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: AppColors.textHint,
                    size: 20),
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(
                        vertical: 14),
              ),
            ),
          ),
        ),

        Expanded(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(
                      color: AppColors.primary))
              : _filtered.isEmpty
                  ? Center(
                      child: Text(
                        _search.isEmpty
                            ? 'No stores available yet'
                            : 'No stores match "$_search"',
                        style: AppTextStyles.bodyMedium,
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      color: AppColors.primary,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(
                            24, 0, 24, 100),
                        itemCount: _filtered.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 12),
                        itemBuilder: (_, i) =>
                            _merchantCard(
                                _filtered[i]
                                    as Map<String, dynamic>),
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _merchantCard(Map<String, dynamic> merchant) {
    final id = merchant['id'] as int;
    final name =
        merchant['fullName'] as String? ?? 'Store';
    final isBlocked =
        merchant['isBlocked'] as bool? ?? false;

    if (isBlocked) return const SizedBox.shrink();

    return GlassCard(
      padding: const EdgeInsets.all(16),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CustomerStoreMenuScreen(
            merchantId: id,
            merchantName: name,
          ),
        ),
      ),
      child: Row(children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Center(
            child: Icon(Icons.store_rounded,
                color: AppColors.primary, size: 28),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: AppTextStyles.headlineSmall),
              const SizedBox(height: 4),
              Row(children: [
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.accent,
                  ),
                ),
                Text('Open now',
                    style: AppTextStyles.caption.copyWith(
                        color: AppColors.accent)),
              ]),
            ],
          ),
        ),
        const Icon(Icons.chevron_right_rounded,
            color: AppColors.textHint),
      ]),
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg),
            backgroundColor: AppColors.error));
  }
}