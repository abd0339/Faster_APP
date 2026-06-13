import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_input.dart';

class MerchantOffersScreen extends StatefulWidget {
  const MerchantOffersScreen({super.key});

  @override
  State<MerchantOffersScreen> createState() => _MerchantOffersScreenState();
}

class _MerchantOffersScreenState extends State<MerchantOffersScreen>
    with SingleTickerProviderStateMixin {
  List<dynamic> _offers = [];
  List<dynamic> _categories = [];
  List<dynamic> _allItems = [];
  bool _isLoading = true;
  final Set<int> _uploadingIds = {};
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ─── Load offers + categories + items in parallel ──
  Future<void> _loadAll() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        ApiService.instance.get(ApiConstants.offers),
        ApiService.instance.get(ApiConstants.categories),
        ApiService.instance.get(ApiConstants.items),
      ]);
      if (!mounted) return;
      setState(() {
        final od = results[0].data;
        _offers = od is List ? od : (od as Map?)?['content'] as List? ?? [];

        final cd = results[1].data;
        _categories = cd is List ? cd : (cd as Map?)?['content'] as List? ?? [];

        final id = results[2].data;
        _allItems = id is List ? id : (id as Map?)?['content'] as List? ?? [];
      });
    } catch (e) {
      if (!mounted) return;
      _showError(ApiService.getErrorMessage(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── TOGGLE ───────────────────────────────────────
  Future<void> _toggleOffer(int id) async {
    try {
      await ApiService.instance.patch('${ApiConstants.offers}/$id/toggle');
      await _loadAll();
    } catch (e) {
      if (mounted) _showError(ApiService.getErrorMessage(e));
    }
  }

  // ─── DELETE ───────────────────────────────────────
  Future<void> _deleteOffer(int id, String title) async {
    final ok = await _confirmDelete(title);
    if (!ok) return;
    try {
      await ApiService.instance.delete('${ApiConstants.offers}/$id');
      await _loadAll();
      if (mounted) _showSuccess('Offer deleted.');
    } catch (e) {
      if (mounted) _showError(ApiService.getErrorMessage(e));
    }
  }

  // ─── CREATE ───────────────────────────────────────
  Future<void> _createOffer(Map<String, dynamic> body) async {
    try {
      await ApiService.instance.post(ApiConstants.offers, data: body);
      await _loadAll();
      if (mounted) _showSuccess('Offer created!');
    } catch (e) {
      if (mounted) _showError(ApiService.getErrorMessage(e));
    }
  }

  // ─── UPDATE ───────────────────────────────────────
  Future<void> _updateOffer(int id, Map<String, dynamic> body) async {
    try {
      await ApiService.instance.put('${ApiConstants.offers}/$id', data: body);
      await _loadAll();
      if (mounted) _showSuccess('Offer updated!');
    } catch (e) {
      if (mounted) _showError(ApiService.getErrorMessage(e));
    }
  }

  // ─── IMAGE UPLOAD ─────────────────────────────────
  Future<void> _pickAndUploadImage(int offerId) async {
    if (kIsWeb) {
      await _doUpload(offerId, ImageSource.gallery);
      return;
    }
    final src = await _showImageSourceSheet();
    if (src == null) return;
    await _doUpload(offerId, src);
  }

  Future<void> _doUpload(int offerId, ImageSource src) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: src,
        maxWidth: 1200,
        maxHeight: 600,
        imageQuality: 85,
      );
      if (picked == null) return;
      if (!mounted) return;
      setState(() => _uploadingIds.add(offerId));
      final bytes = await picked.readAsBytes();
      final name = picked.name.isNotEmpty ? picked.name : 'offer.jpg';
      await ApiService.instance.uploadImageBytes(
        '${ApiConstants.offers}/$offerId/image',
        bytes,
        name,
        'image',
      );
      await _loadAll();
      if (mounted) _showSuccess('Banner uploaded!');
    } catch (e) {
      if (mounted) _showError(ApiService.getErrorMessage(e));
    } finally {
      if (mounted) setState(() => _uploadingIds.remove(offerId));
    }
  }

  Future<ImageSource?> _showImageSourceSheet() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _srcTile(ctx, ImageSource.camera, Icons.camera_alt_rounded,
                  AppColors.primary, 'Take Photo'),
              const SizedBox(height: 12),
              _srcTile(ctx, ImageSource.gallery, Icons.photo_library_rounded,
                  AppColors.accent, 'Choose from Gallery'),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  alignment: Alignment.center,
                  child: Text('Cancel',
                      style: AppTextStyles.labelLarge
                          .copyWith(color: AppColors.textHint)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _srcTile(BuildContext ctx, ImageSource src, IconData icon, Color color,
      String label) {
    return GestureDetector(
      onTap: () => Navigator.pop(ctx, src),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.glassWhite,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Text(label, style: AppTextStyles.headlineSmall),
          ],
        ),
      ),
    );
  }

  // ─── BUILD ────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final live = _offers.where((o) => o['isActive'] == true).toList();
    return SafeArea(
      child: Stack(
        children: [
          Column(
            children: [
              _buildHeader(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.glassWhite,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    indicator: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    labelColor: AppColors.background,
                    unselectedLabelColor: AppColors.textHint,
                    labelStyle: AppTextStyles.labelLarge,
                    dividerColor: Colors.transparent,
                    tabs: [
                      Tab(text: 'Live (${live.length})'),
                      Tab(text: 'All (${_offers.length})'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _isLoading
                    ? const Center(
                        child:
                            CircularProgressIndicator(color: AppColors.primary))
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildList(live),
                          _buildList(_offers),
                        ],
                      ),
              ),
            ],
          ),
          Positioned(
            bottom: 24,
            right: 24,
            child: FloatingActionButton.extended(
              heroTag: 'offer_fab',
              onPressed: () => _showOfferSheet(),
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.background,
              icon: const Icon(Icons.add_rounded),
              label: Text('New Offer',
                  style: AppTextStyles.labelLarge
                      .copyWith(color: AppColors.background)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
      child: Row(
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Offers', style: AppTextStyles.displayMedium),
            Text('Promotions & campaigns', style: AppTextStyles.bodyMedium),
          ]),
          const Spacer(),
          GestureDetector(
            onTap: _loadAll,
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

  Widget _buildList(List<dynamic> offers) {
    if (offers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('No offers yet', style: AppTextStyles.headlineMedium),
            const SizedBox(height: 8),
            Text('Tap + New Offer to create one',
                style: AppTextStyles.bodyMedium),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadAll,
      color: AppColors.primary,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 100),
        itemCount: offers.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _buildCard(offers[i] as Map<String, dynamic>),
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> offer) {
    final isActive = offer['isActive'] as bool? ?? false;
    final offerId = offer['id'] as int;
    final imageUrl = offer['imageUrl'] as String?;
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;
    final isUploading = _uploadingIds.contains(offerId);
    final discount = offer['discountPercent'];
    final offerType = offer['offerType'] as String? ?? 'PERCENTAGE';

    // Scope labels
    final cats = (offer['appliedToCategories'] as List?) ?? [];
    final items = (offer['appliedToItems'] as List?) ?? [];
    String scopeLabel = 'Entire store';
    if (cats.isNotEmpty && items.isEmpty) {
      scopeLabel = cats.map((c) => c['name']).join(', ');
    } else if (items.isNotEmpty) {
      scopeLabel =
          '${items.length} specific item${items.length > 1 ? 's' : ''}';
    }

    return GlassCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── Banner ────────────────────────────
          GestureDetector(
            onTap: () => _pickAndUploadImage(offerId),
            child: ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
              child: SizedBox(
                width: double.infinity,
                height: hasImage ? 160 : 60,
                child: isUploading
                    ? Container(
                        color: AppColors.glassWhite,
                        child: const Center(
                          child: CircularProgressIndicator(
                              color: AppColors.primary, strokeWidth: 2),
                        ))
                    : hasImage
                        ? Stack(fit: StackFit.expand, children: [
                            Image.network(
                              '${ApiConstants.baseUrl}$imageUrl',
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: AppColors.glassWhite,
                                child: const Center(
                                  child: Icon(
                                    Icons.broken_image_outlined,
                                    color: AppColors.textHint,
                                    size: 32,
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 8,
                              right: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppColors.background
                                      .withValues(alpha: 0.8),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.edit_rounded,
                                        color: AppColors.primary, size: 13),
                                    const SizedBox(width: 4),
                                    Text('Change banner',
                                        style: AppTextStyles.caption.copyWith(
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.w600,
                                        )),
                                  ],
                                ),
                              ),
                            ),
                          ])
                        : Container(
                            color: AppColors.glassWhite,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.add_photo_alternate_outlined,
                                    color: AppColors.primary, size: 18),
                                const SizedBox(width: 6),
                                Text('Add banner (optional)',
                                    style: AppTextStyles.bodyMedium
                                        .copyWith(color: AppColors.primary)),
                              ],
                            ),
                          ),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ─── Title + discount ───────────
                Row(children: [
                  Expanded(
                    child: Text(offer['title'] ?? '',
                        style: AppTextStyles.headlineMedium.copyWith(
                          color: isActive
                              ? AppColors.textPrimary
                              : AppColors.textHint,
                        )),
                  ),
                  if (discount != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: AppColors.accent.withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        offerType == 'PERCENTAGE'
                            ? '$discount% OFF'
                            : '\$$discount OFF',
                        style: AppTextStyles.labelLarge
                            .copyWith(color: AppColors.accent),
                      ),
                    ),
                ]),

                if (offer['description'] != null &&
                    (offer['description'] as String).isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(offer['description'],
                      style: AppTextStyles.bodyMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ],

                const SizedBox(height: 8),

                // ─── Scope label ────────────────
                Row(children: [
                  const Icon(Icons.tag_rounded,
                      size: 13, color: AppColors.primary),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(scopeLabel,
                        style: AppTextStyles.caption
                            .copyWith(color: AppColors.primary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                ]),

                const SizedBox(height: 4),

                // ─── Dates + usage ──────────────
                Row(children: [
                  const Icon(Icons.calendar_today_outlined,
                      size: 13, color: AppColors.textHint),
                  const SizedBox(width: 4),
                  Text(
                    _formatDates(offer['startDate'], offer['endDate']),
                    style: AppTextStyles.caption,
                  ),
                  if (offer['usageLimit'] != null) ...[
                    const SizedBox(width: 12),
                    const Icon(Icons.people_outline,
                        size: 13, color: AppColors.textHint),
                    const SizedBox(width: 4),
                    Text(
                      '${offer['usageCount'] ?? 0}/${offer['usageLimit']} used',
                      style: AppTextStyles.caption,
                    ),
                  ],
                ]),

                const SizedBox(height: 12),
                const Divider(color: AppColors.glassBorder, height: 1),
                const SizedBox(height: 12),

                // ─── Actions ────────────────────
                Row(children: [
                  GestureDetector(
                    onTap: () {
                      if (!kIsWeb) HapticFeedback.lightImpact();
                      _toggleOffer(offerId);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 44,
                      height: 26,
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: isActive
                            ? AppColors.accent.withValues(alpha: 0.8)
                            : AppColors.glassWhite,
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(
                          color: isActive
                              ? AppColors.accent
                              : AppColors.glassBorder,
                        ),
                      ),
                      child: AnimatedAlign(
                        duration: const Duration(milliseconds: 200),
                        alignment: isActive
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: isActive
                                ? AppColors.background
                                : AppColors.textHint,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isActive ? 'Live' : 'Paused',
                    style: AppTextStyles.caption.copyWith(
                      color: isActive ? AppColors.accent : AppColors.textHint,
                    ),
                  ),
                  const Spacer(),
                  _actionBtn(Icons.edit_outlined, AppColors.primary, 'Edit',
                      () => _showOfferSheet(existing: offer)),
                  const SizedBox(width: 8),
                  _actionBtn(
                      Icons.delete_outline_rounded,
                      AppColors.error,
                      'Delete',
                      () => _deleteOffer(offerId, offer['title'] as String)),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionBtn(
      IconData icon, Color color, String tip, VoidCallback onTap) {
    return Tooltip(
      message: tip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
      ),
    );
  }

  String _formatDates(dynamic s, dynamic e) {
    String fmt(dynamic d) {
      if (d == null) return '?';
      final str = d.toString();
      return str.length >= 10 ? str.substring(0, 10) : str;
    }

    if (s == null && e == null) return 'No date set';
    return '${fmt(s)} → ${fmt(e)}';
  }

  // ─── OFFER SHEET ──────────────────────────────────
  void _showOfferSheet({Map<String, dynamic>? existing}) {
    final isEdit = existing != null;
    final titleCtrl = TextEditingController(text: existing?['title'] ?? '');
    final descCtrl =
        TextEditingController(text: existing?['description'] ?? '');
    final discountCtrl = TextEditingController(
        text: existing?['discountPercent']?.toString() ?? '');
    final usageLimitCtrl =
        TextEditingController(text: existing?['usageLimit']?.toString() ?? '');
    final formKey = GlobalKey<FormState>();

    String selectedType = existing?['offerType'] as String? ?? 'PERCENTAGE';
    DateTime? startDate = _parseDate(existing?['startDate']);
    DateTime? endDate = _parseDate(existing?['endDate']);

    // ─── Scope selection ──────────────────────────────
    // scopeMode: 'all' | 'categories' | 'items'
    String scopeMode = 'all';
    Set<int> selectedCatIds = {};
    Set<int> selectedItemIds = {};

    // Pre-fill scope from existing offer
    if (existing != null) {
      final cats = (existing['appliedToCategories'] as List?) ?? [];
      final items = (existing['appliedToItems'] as List?) ?? [];
      if (items.isNotEmpty) {
        scopeMode = 'items';
        selectedItemIds = items.map<int>((i) => i['id'] as int).toSet();
      } else if (cats.isNotEmpty) {
        scopeMode = 'categories';
        selectedCatIds = cats.map<int>((c) => c['id'] as int).toSet();
      }
    }

    final typeOptions = [
      {'value': 'PERCENTAGE', 'label': '% Off', 'icon': '🏷️'},
      {'value': 'FIXED_AMOUNT', 'label': '\$ Off', 'icon': '💰'},
      {'value': 'FREE_DELIVERY', 'label': 'Free Delivery', 'icon': '🛵'},
      {'value': 'BUY_X_GET_Y', 'label': 'Buy X Get Y', 'icon': '🎁'},
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => DraggableScrollableSheet(
          initialChildSize: 0.92,
          minChildSize: 0.5,
          maxChildSize: 0.98,
          expand: false,
          builder: (_, scrollCtrl) => Column(
            children: [
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.glassBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(children: [
                  Text(isEdit ? 'Edit Offer' : 'New Offer',
                      style: AppTextStyles.headlineLarge),
                ]),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollCtrl,
                  padding: EdgeInsets.only(
                    left: 24,
                    right: 24,
                    bottom: MediaQuery.of(ctx).viewInsets.bottom + 32,
                  ),
                  child: Form(
                    key: formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ─── Title ──────────────────
                        AppInput(
                          controller: titleCtrl,
                          hint: 'e.g. Weekend Special',
                          label: 'Title',
                          prefixIcon: Icons.local_offer_outlined,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Title is required';
                            }
                            if (v.trim().length < 3) {
                              return 'Min 3 characters';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        // ─── Description ────────────
                        AppInput(
                          controller: descCtrl,
                          hint: 'Short description (optional)',
                          label: 'Description',
                          prefixIcon: Icons.description_outlined,
                          maxLines: 2,
                        ),
                        const SizedBox(height: 20),

                        // ─── Offer type ─────────────
                        Text('Offer Type', style: AppTextStyles.headlineSmall),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: typeOptions.map((t) {
                            final val = t['value'] as String;
                            final sel = selectedType == val;
                            return GestureDetector(
                              onTap: () => setSheet(() => selectedType = val),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: sel
                                      ? AppColors.primary
                                          .withValues(alpha: 0.15)
                                      : AppColors.glassWhite,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: sel
                                        ? AppColors.primary
                                        : AppColors.glassBorder,
                                    width: sel ? 2 : 1,
                                  ),
                                ),
                                child: Text(
                                  '${t['icon']} ${t['label']}',
                                  style: AppTextStyles.labelLarge.copyWith(
                                    color: sel
                                        ? AppColors.primary
                                        : AppColors.textHint,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 20),

                        // ─── Discount amount ─────────
                        if (selectedType == 'PERCENTAGE' ||
                            selectedType == 'FIXED_AMOUNT') ...[
                          AppInput(
                            controller: discountCtrl,
                            hint: selectedType == 'PERCENTAGE'
                                ? 'e.g. 20 for 20%'
                                : 'e.g. 5 for \$5 off',
                            label: selectedType == 'PERCENTAGE'
                                ? 'Discount %'
                                : 'Discount \$',
                            prefixIcon: Icons.percent_rounded,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Required';
                              }
                              final p = double.tryParse(v);
                              if (p == null || p <= 0) {
                                return 'Invalid amount';
                              }
                              if (selectedType == 'PERCENTAGE' && p > 100) {
                                return 'Max 100%';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                        ],

                        // ─── Usage limit ─────────────
                        AppInput(
                          controller: usageLimitCtrl,
                          hint: 'Leave empty for unlimited',
                          label: 'Usage Limit (optional)',
                          prefixIcon: Icons.people_outline,
                          keyboardType: TextInputType.number,
                        ),
                        const SizedBox(height: 20),

                        // ─── Date range ──────────────
                        Text('Offer Period',
                            style: AppTextStyles.headlineSmall),
                        const SizedBox(height: 10),
                        Row(children: [
                          Expanded(
                            child: _dateTile(
                              label: 'Start',
                              date: startDate,
                              onTap: () async {
                                final d = await _pickDate(ctx, startDate);
                                if (d != null) {
                                  setSheet(() => startDate = d);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _dateTile(
                              label: 'End',
                              date: endDate,
                              onTap: () async {
                                final d = await _pickDate(ctx, endDate,
                                    first: startDate);
                                if (d != null) {
                                  setSheet(() => endDate = d);
                                }
                              },
                            ),
                          ),
                        ]),
                        const SizedBox(height: 24),

                        // ─────────────────────────────
                        // SCOPE SECTION
                        // ─────────────────────────────
                        Row(children: [
                          Text('Applies To',
                              style: AppTextStyles.headlineSmall),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text('Who gets this offer?',
                                style: AppTextStyles.caption
                                    .copyWith(color: AppColors.primary)),
                          ),
                        ]),
                        const SizedBox(height: 12),

                        // ─── Scope mode picker ───────
                        Row(children: [
                          _scopeChip('all', 'Entire Store', scopeMode, (v) {
                            setSheet(() {
                              scopeMode = v;
                              selectedCatIds.clear();
                              selectedItemIds.clear();
                            });
                          }),
                          const SizedBox(width: 8),
                          _scopeChip('categories', 'By Category', scopeMode,
                              (v) {
                            setSheet(() {
                              scopeMode = v;
                              selectedItemIds.clear();
                            });
                          }),
                          const SizedBox(width: 8),
                          _scopeChip('items', 'Specific Items', scopeMode, (v) {
                            setSheet(() {
                              scopeMode = v;
                              selectedCatIds.clear();
                            });
                          }),
                        ]),
                        const SizedBox(height: 16),

                        // ─── Category selector ───────
                        if (scopeMode == 'categories' &&
                            _categories.isNotEmpty) ...[
                          Text('Select Categories',
                              style: AppTextStyles.caption
                                  .copyWith(color: AppColors.textHint)),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _categories.map((cat) {
                              final catId = cat['id'] as int;
                              final isSelected = selectedCatIds.contains(catId);
                              return GestureDetector(
                                onTap: () => setSheet(() {
                                  if (isSelected) {
                                    selectedCatIds.remove(catId);
                                  } else {
                                    selectedCatIds.add(catId);
                                  }
                                }),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? AppColors.primary
                                            .withValues(alpha: 0.15)
                                        : AppColors.glassWhite,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: isSelected
                                          ? AppColors.primary
                                          : AppColors.glassBorder,
                                      width: isSelected ? 2 : 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (isSelected)
                                        const Icon(Icons.check_rounded,
                                            color: AppColors.primary, size: 14),
                                      if (isSelected) const SizedBox(width: 4),
                                      Text(
                                        '${cat['icon'] ?? ''} ${cat['name']}',
                                        style:
                                            AppTextStyles.bodyMedium.copyWith(
                                          color: isSelected
                                              ? AppColors.primary
                                              : AppColors.textPrimary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 20),
                        ],

                        // ─── Item selector ───────────
                        if (scopeMode == 'items' && _allItems.isNotEmpty) ...[
                          Text('Select Items',
                              style: AppTextStyles.caption
                                  .copyWith(color: AppColors.textHint)),
                          const SizedBox(height: 8),
                          ..._categories.map((cat) {
                            final catId = cat['id'] as int;
                            final catItems = _allItems
                                .where((i) =>
                                    (i as Map<String, dynamic>)['category']
                                        ?['id'] ==
                                    catId)
                                .toList();
                            if (catItems.isEmpty) {
                              return const SizedBox.shrink();
                            }
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Category header
                                Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '${cat['icon'] ?? ''} ${cat['name']}'
                                        .toUpperCase(),
                                    style: AppTextStyles.caption.copyWith(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ),
                                // Items in this category
                                ...catItems.map((item) {
                                  final itemMap = item as Map<String, dynamic>;
                                  final itemId = itemMap['id'] as int;
                                  final isSel =
                                      selectedItemIds.contains(itemId);
                                  return GestureDetector(
                                    onTap: () => setSheet(() {
                                      if (isSel) {
                                        selectedItemIds.remove(itemId);
                                      } else {
                                        selectedItemIds.add(itemId);
                                      }
                                    }),
                                    child: Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: isSel
                                            ? AppColors.primary
                                                .withValues(alpha: 0.1)
                                            : AppColors.glassWhite,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: isSel
                                              ? AppColors.primary
                                              : AppColors.glassBorder,
                                          width: isSel ? 2 : 1,
                                        ),
                                      ),
                                      child: Row(children: [
                                        AnimatedContainer(
                                          duration:
                                              const Duration(milliseconds: 150),
                                          width: 20,
                                          height: 20,
                                          decoration: BoxDecoration(
                                            color: isSel
                                                ? AppColors.primary
                                                : Colors.transparent,
                                            border: Border.all(
                                              color: isSel
                                                  ? AppColors.primary
                                                  : AppColors.glassBorder,
                                              width: 2,
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: isSel
                                              ? const Icon(Icons.check_rounded,
                                                  color: Colors.white, size: 13)
                                              : null,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            itemMap['name'] ?? '',
                                            style: AppTextStyles.bodyMedium,
                                          ),
                                        ),
                                        Text(
                                          '\$${itemMap['price']}',
                                          style: AppTextStyles.caption.copyWith(
                                              color: AppColors.primary),
                                        ),
                                      ]),
                                    ),
                                  );
                                }),
                                const SizedBox(height: 8),
                              ],
                            );
                          }),
                          const SizedBox(height: 12),
                        ],

                        // ─── Save button ─────────────
                        AppButton(
                          label: isEdit ? 'Save Changes' : 'Create Offer',
                          icon:
                              isEdit ? Icons.save_outlined : Icons.add_rounded,
                          onPressed: () async {
                            if (!formKey.currentState!.validate()) return;
                            Navigator.pop(ctx);

                            final body = <String, dynamic>{
                              'title': titleCtrl.text.trim(),
                              'description': descCtrl.text.trim(),
                              'offerType': selectedType,
                              if (discountCtrl.text.isNotEmpty)
                                'discountPercent':
                                    double.tryParse(discountCtrl.text.trim()),
                              if (usageLimitCtrl.text.isNotEmpty)
                                'usageLimit':
                                    int.tryParse(usageLimitCtrl.text.trim()),
                              if (startDate != null)
                                'startDate': startDate!
                                    .toIso8601String()
                                    .split('.')
                                    .first,
                              if (endDate != null)
                                'endDate':
                                    endDate!.toIso8601String().split('.').first,
                              // Scope
                              'categoryIds': scopeMode == 'categories'
                                  ? selectedCatIds.toList()
                                  : [],
                              'itemIds': scopeMode == 'items'
                                  ? selectedItemIds.toList()
                                  : [],
                            };

                            if (isEdit) {
                              await _updateOffer(existing!['id'] as int, body);
                            } else {
                              await _createOffer(body);
                            }
                          },
                        ),

                        if (isEdit) ...[
                          const SizedBox(height: 12),
                          AppButton(
                            label: 'Delete Offer',
                            icon: Icons.delete_outline_rounded,
                            color: AppColors.error,
                            onPressed: () async {
                              Navigator.pop(ctx);
                              await _deleteOffer(existing!['id'] as int,
                                  existing['title'] as String);
                            },
                          ),
                        ],
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _scopeChip(
      String value, String label, String current, ValueChanged<String> onTap) {
    final sel = current == value;
    return GestureDetector(
      onTap: () => onTap(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: sel
              ? AppColors.accent.withValues(alpha: 0.15)
              : AppColors.glassWhite,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: sel ? AppColors.accent : AppColors.glassBorder,
            width: sel ? 2 : 1,
          ),
        ),
        child: Text(
          label,
          style: AppTextStyles.caption.copyWith(
            color: sel ? AppColors.accent : AppColors.textHint,
            fontWeight: sel ? FontWeight.w700 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _dateTile({
    required String label,
    required DateTime? date,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.glassWhite,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: date != null
                ? AppColors.primary.withValues(alpha: 0.5)
                : AppColors.glassBorder,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style:
                    AppTextStyles.caption.copyWith(color: AppColors.textHint)),
            const SizedBox(height: 4),
            Text(
              date != null
                  ? '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}'
                  : 'Tap to set',
              style: AppTextStyles.bodyMedium.copyWith(
                color:
                    date != null ? AppColors.textPrimary : AppColors.textHint,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<DateTime?> _pickDate(BuildContext ctx, DateTime? initial,
      {DateTime? first}) {
    final firstDate = first ?? DateTime.now().subtract(const Duration(days: 1));

    // CRITICAL: initialDate must not be before firstDate
    DateTime safeInitial = initial ?? DateTime.now();
    if (safeInitial.isBefore(firstDate)) {
      safeInitial = firstDate;
    }

    return showDatePicker(
      context: ctx,
      initialDate: safeInitial,
      firstDate: firstDate,
      lastDate: DateTime.now().add(const Duration(days: 730)),
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
  }

  DateTime? _parseDate(dynamic d) {
    if (d == null) return null;
    try {
      return DateTime.parse(d.toString());
    } catch (_) {
      return null;
    }
  }

  Future<bool> _confirmDelete(String title) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.surface,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title:
                Text('Delete "$title"?', style: AppTextStyles.headlineMedium),
            content:
                Text('This cannot be undone.', style: AppTextStyles.bodyMedium),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Cancel',
                    style: AppTextStyles.labelLarge
                        .copyWith(color: AppColors.textHint)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('Delete',
                    style: AppTextStyles.labelLarge
                        .copyWith(color: AppColors.error)),
              ),
            ],
          ),
        ) ??
        false;
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
