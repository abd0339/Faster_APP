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

class MerchantItemsScreen extends StatefulWidget {
  final Map<String, dynamic> category;

  const MerchantItemsScreen({
    super.key,
    required this.category,
  });

  @override
  State<MerchantItemsScreen> createState() => _MerchantItemsScreenState();
}

class _MerchantItemsScreenState extends State<MerchantItemsScreen> {
  List<dynamic> _items = [];
  bool _isLoading = true;
  // Track which item is uploading image
  final Set<int> _uploadingImageIds = {};

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  // ─── LOAD ─────────────────────────────────────────
  Future<void> _loadItems() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final res = await ApiService.instance.get(ApiConstants.items);
      if (!mounted) return;
      final data = res.data;
      final all =
          data is List ? data : (data as Map?)?['content'] as List? ?? [];
      final catId = widget.category['id'] as int;
      setState(() => _items = all
          .where((i) => (i as Map<String, dynamic>)['category']?['id'] == catId)
          .toList());
    } catch (e) {
      if (!mounted) return;
      _showError(ApiService.getErrorMessage(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── UPLOAD IMAGE ─────────────────────────────────
  // ─── PICK SOURCE then upload ──────────────────────
  Future<void> _pickAndUploadImage(int itemId) async {
    // On Web: browser has no camera API via image_picker → go straight to gallery
    if (kIsWeb) {
      await _uploadFromSource(itemId, ImageSource.gallery);
      return;
    }

    // On Mobile: show Camera / Gallery choice
    final source = await showModalBottomSheet<ImageSource>(
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
              const SizedBox(height: 20),
              Text('Add Photo', style: AppTextStyles.headlineLarge),
              const SizedBox(height: 20),

              // Camera option
              GestureDetector(
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
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
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.camera_alt_rounded,
                          color: AppColors.primary,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Take a Photo',
                              style: AppTextStyles.headlineSmall),
                          Text('Use your camera',
                              style: AppTextStyles.bodyMedium),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Gallery option
              GestureDetector(
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
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
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.photo_library_rounded,
                          color: AppColors.accent,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Choose from Gallery',
                              style: AppTextStyles.headlineSmall),
                          Text('Pick an existing photo',
                              style: AppTextStyles.bodyMedium),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Cancel
              GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  alignment: Alignment.center,
                  child: Text(
                    'Cancel',
                    style: AppTextStyles.labelLarge
                        .copyWith(color: AppColors.textHint),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (source == null) return;
    await _uploadFromSource(itemId, source);
  }

// ─── ACTUAL UPLOAD after source is chosen ─────────
  Future<void> _uploadFromSource(int itemId, ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (picked == null) return;

      if (!mounted) return;
      setState(() => _uploadingImageIds.add(itemId));

      final bytes = await picked.readAsBytes();
      final filename = picked.name.isNotEmpty ? picked.name : 'item_image.jpg';

      await ApiService.instance.uploadImageBytes(
        ApiConstants.itemImage(itemId),
        bytes,
        filename,
        'image',
      );

      await _loadItems();
      if (mounted) _showSuccess('Image uploaded!');
    } catch (e) {
      if (mounted) _showError(ApiService.getErrorMessage(e));
    } finally {
      if (mounted) {
        setState(() => _uploadingImageIds.remove(itemId));
      }
    }
  }

  // ─── TOGGLE AVAILABLE ─────────────────────────────
  Future<void> _toggleItem(int id) async {
    try {
      await ApiService.instance.patch(ApiConstants.itemToggle(id));
      await _loadItems();
    } catch (e) {
      if (mounted) _showError(ApiService.getErrorMessage(e));
    }
  }

  // ─── SNOOZE ───────────────────────────────────────
  Future<void> _snoozeItem(int id, int hours) async {
    try {
      await ApiService.instance.patch(
        ApiConstants.itemSnooze(id),
        data: {'hours': hours},
      );
      await _loadItems();
      if (mounted) _showSuccess('Item snoozed for ${hours}h');
    } catch (e) {
      if (mounted) _showError(ApiService.getErrorMessage(e));
    }
  }

  // ─── DELETE ───────────────────────────────────────
  Future<void> _deleteItem(int id, String name) async {
    final confirmed = await _showDeleteConfirm(name);
    if (!confirmed) return;
    try {
      await ApiService.instance.delete('${ApiConstants.items}/$id');
      await _loadItems();
      if (mounted) _showSuccess('Item deleted.');
    } catch (e) {
      if (mounted) _showError(ApiService.getErrorMessage(e));
    }
  }

  // ─── CREATE ───────────────────────────────────────
  Future<void> _createItem(Map<String, dynamic> data) async {
    try {
      await ApiService.instance.post(ApiConstants.items, data: data);
      await _loadItems();
      if (mounted) _showSuccess('Item created!');
    } catch (e) {
      if (mounted) _showError(ApiService.getErrorMessage(e));
    }
  }

  // ─── UPDATE ───────────────────────────────────────
  Future<void> _updateItem(int id, Map<String, dynamic> data) async {
    try {
      await ApiService.instance.put('${ApiConstants.items}/$id', data: data);
      await _loadItems();
      if (mounted) _showSuccess('Item updated!');
    } catch (e) {
      if (mounted) _showError(ApiService.getErrorMessage(e));
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
            Expanded(
              child: _isLoading
                  ? const Center(
                      child:
                          CircularProgressIndicator(color: AppColors.primary))
                  : _items.isEmpty
                      ? _buildEmptyState()
                      : _buildItemList(),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'item_fab',
        onPressed: () => _showItemSheet(),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.background,
        icon: const Icon(Icons.add_rounded),
        label: Text(
          'Add Item',
          style: AppTextStyles.labelLarge.copyWith(color: AppColors.background),
        ),
      ),
    );
  }

  // ─── HEADER ───────────────────────────────────────
  Widget _buildHeader() {
    final icon = widget.category['icon'] as String? ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
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
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${icon.isNotEmpty ? "$icon " : ""}${widget.category['name']}',
                  style: AppTextStyles.displayMedium,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${_items.length} items',
                  style: AppTextStyles.bodyMedium,
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _loadItems,
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

  // ─── ITEM LIST ────────────────────────────────────
  Widget _buildItemList() {
    return RefreshIndicator(
      onRefresh: _loadItems,
      color: AppColors.primary,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 100),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) =>
            _buildItemCard(_items[i] as Map<String, dynamic>),
      ),
    );
  }

  // ─── ITEM CARD ────────────────────────────────────
  Widget _buildItemCard(Map<String, dynamic> item) {
    final isAvailable = item['isAvailable'] as bool? ?? true;
    final isSnoozed = item['isSnoozed'] as bool? ?? false;
    final stock = item['stockQuantity'] as int? ?? -1;
    final price = item['price'];
    final imageUrl = item['imageUrl'] as String?;
    final itemId = item['id'] as int;
    final isUploadingImage = _uploadingImageIds.contains(itemId);

    Color statusColor = AppColors.accent;
    String statusLabel = 'Available';
    if (isSnoozed) {
      statusColor = AppColors.warning;
      statusLabel = 'Snoozed';
    } else if (!isAvailable) {
      statusColor = AppColors.error;
      statusLabel = 'Unavailable';
    }

    return GlassCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── Image section ─────────────────────
          _buildImageSection(
            itemId: itemId,
            imageUrl: imageUrl,
            isUploading: isUploadingImage,
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ─── Name + price ───────────────
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item['name'] ?? '',
                        style: AppTextStyles.headlineMedium.copyWith(
                          color: isAvailable && !isSnoozed
                              ? AppColors.textPrimary
                              : AppColors.textHint,
                        ),
                      ),
                    ),
                    Text('\$$price', style: AppTextStyles.price),
                  ],
                ),

                const SizedBox(height: 4),

                // ─── Status + stock ─────────────
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: statusColor.withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        statusLabel,
                        style: AppTextStyles.caption.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      stock == -1 ? 'Unlimited stock' : 'Stock: $stock',
                      style: AppTextStyles.caption,
                    ),
                  ],
                ),

                if (item['description'] != null &&
                    (item['description'] as String).isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    item['description'],
                    style: AppTextStyles.bodyMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],

                const SizedBox(height: 12),
                const Divider(color: AppColors.glassBorder, height: 1),
                const SizedBox(height: 12),

                // ─── Action buttons ─────────────
                Row(
                  children: [
                    _actionBtn(
                      icon: isAvailable
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color:
                          isAvailable ? AppColors.accent : AppColors.textHint,
                      tooltip: isAvailable ? 'Hide' : 'Show',
                      onTap: () {
                        if (!kIsWeb) HapticFeedback.lightImpact();
                        _toggleItem(itemId);
                      },
                    ),
                    const SizedBox(width: 8),
                    _actionBtn(
                      icon: Icons.snooze_rounded,
                      color: isSnoozed ? AppColors.warning : AppColors.textHint,
                      tooltip: 'Snooze',
                      onTap: () => _showSnoozeSheet(item),
                    ),
                    const SizedBox(width: 8),
                    _actionBtn(
                      icon: Icons.edit_outlined,
                      color: AppColors.primary,
                      tooltip: 'Edit',
                      onTap: () => _showItemSheet(existing: item),
                    ),
                    const SizedBox(width: 8),
                    _actionBtn(
                      icon: Icons.delete_outline_rounded,
                      color: AppColors.error,
                      tooltip: 'Delete',
                      onTap: () => _deleteItem(
                        itemId,
                        item['name'] as String,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── IMAGE SECTION ────────────────────────────────
  Widget _buildImageSection({
    required int itemId,
    required String? imageUrl,
    required bool isUploading,
  }) {
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;

    return GestureDetector(
      onTap: () => _pickAndUploadImage(itemId),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: SizedBox(
          width: double.infinity,
          height: hasImage ? 180 : 72,
          child: isUploading
              // ─── Uploading state ───────────────
              ? Container(
                  color: AppColors.glassWhite,
                  child: const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(
                            color: AppColors.primary, strokeWidth: 2),
                        SizedBox(height: 8),
                        Text('Uploading...', style: AppTextStyles.bodyMedium),
                      ],
                    ),
                  ),
                )
              : hasImage
                  // ─── Has image ─────────────────
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          '${ApiConstants.baseUrl}$imageUrl',
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: AppColors.glassWhite,
                            child: const Center(
                              child: Icon(Icons.broken_image_outlined,
                                  color: AppColors.textHint, size: 32),
                            ),
                          ),
                        ),
                        // Edit overlay
                        Positioned(
                          bottom: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color:
                                  AppColors.background.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.edit_rounded,
                                    color: AppColors.primary, size: 14),
                                const SizedBox(width: 4),
                                Text(
                                  'Change photo',
                                  style: AppTextStyles.caption.copyWith(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  // ─── No image ──────────────────
                  : Container(
                      color: AppColors.glassWhite,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.add_photo_alternate_outlined,
                              color: AppColors.primary, size: 22),
                          const SizedBox(width: 8),
                          Text(
                            'Add photo (optional)',
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
        ),
      ),
    );
  }

  // ─── ACTION BUTTON ────────────────────────────────
  Widget _actionBtn({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
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

  // ─── EMPTY STATE ──────────────────────────────────
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('No items yet', style: AppTextStyles.headlineMedium),
          const SizedBox(height: 8),
          Text(
            'Tap the button below\nto add your first item',
            style: AppTextStyles.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          AppButton(
            label: 'Add First Item',
            isFullWidth: false,
            icon: Icons.add_rounded,
            onPressed: () => _showItemSheet(),
          ),
        ],
      ),
    );
  }

  // ─── ITEM SHEET ───────────────────────────────────
  void _showItemSheet({Map<String, dynamic>? existing}) {
    final isEdit = existing != null;
    final nameCtrl = TextEditingController(text: existing?['name'] ?? '');
    final priceCtrl =
        TextEditingController(text: existing?['price']?.toString() ?? '');
    final descCtrl =
        TextEditingController(text: existing?['description'] ?? '');
    final prepCtrl = TextEditingController(
        text: existing?['prepTimeMinutes']?.toString() ?? '15');
    final stockCtrl = TextEditingController(
        text: existing?['stockQuantity']?.toString() ?? '-1');
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                const SizedBox(height: 20),
                Text(isEdit ? 'Edit Item' : 'New Item',
                    style: AppTextStyles.headlineLarge),
                const SizedBox(height: 4),
                Text(
                  'Category: ${widget.category['icon'] ?? ''} ${widget.category['name']}',
                  style: AppTextStyles.bodyMedium,
                ),
                const SizedBox(height: 20),
                AppInput(
                  controller: nameCtrl,
                  hint: 'Item name (e.g. Cheeseburger)',
                  label: 'Name',
                  prefixIcon: Icons.fastfood_outlined,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Name is required';
                    }
                    if (v.trim().length < 2) return 'Min 2 characters';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                AppInput(
                  controller: priceCtrl,
                  hint: '0.00',
                  label: 'Price (\$)',
                  prefixIcon: Icons.attach_money_rounded,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Price is required';
                    }
                    final parsed = double.tryParse(v);
                    if (parsed == null || parsed <= 0) {
                      return 'Enter a valid price';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                AppInput(
                  controller: descCtrl,
                  hint: 'Describe the item (optional)',
                  label: 'Description',
                  prefixIcon: Icons.description_outlined,
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: AppInput(
                        controller: prepCtrl,
                        hint: '15',
                        label: 'Prep (min)',
                        prefixIcon: Icons.timer_outlined,
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AppInput(
                        controller: stockCtrl,
                        hint: '-1',
                        label: 'Stock (-1=∞)',
                        prefixIcon: Icons.inventory_2_outlined,
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Tip: -1 = unlimited stock',
                  style: AppTextStyles.caption,
                ),
                const SizedBox(height: 24),
                AppButton(
                  label: isEdit ? 'Save Changes' : 'Create Item',
                  icon: isEdit ? Icons.save_outlined : Icons.add_rounded,
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;
                    Navigator.pop(ctx);
                    final body = {
                      'name': nameCtrl.text.trim(),
                      'price': double.parse(priceCtrl.text.trim()),
                      'description': descCtrl.text.trim(),
                      'prepTimeMinutes':
                          int.tryParse(prepCtrl.text.trim()) ?? 15,
                      'stockQuantity':
                          int.tryParse(stockCtrl.text.trim()) ?? -1,
                      'categoryId': widget.category['id'],
                    };
                    if (isEdit) {
                      await _updateItem(existing!['id'] as int, body);
                    } else {
                      await _createItem(body);
                    }
                  },
                ),
                if (isEdit) ...[
                  const SizedBox(height: 12),
                  AppButton(
                    label: 'Delete Item',
                    icon: Icons.delete_outline_rounded,
                    color: AppColors.error,
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _deleteItem(
                        existing!['id'] as int,
                        existing['name'] as String,
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── SNOOZE SHEET ─────────────────────────────────
  void _showSnoozeSheet(Map<String, dynamic> item) {
    final isSnoozed = item['isSnoozed'] as bool? ?? false;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            const SizedBox(height: 20),
            Text('Snooze "${item['name']}"',
                style: AppTextStyles.headlineLarge),
            Text('Auto-unsnoozes when time expires',
                style: AppTextStyles.bodyMedium),
            const SizedBox(height: 20),
            ...[1, 2, 4, 8].map((hours) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: AppButton(
                    label: 'Snooze for $hours hour${hours > 1 ? 's' : ''}',
                    icon: Icons.snooze_rounded,
                    color: AppColors.warning,
                    textColor: AppColors.background,
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _snoozeItem(item['id'] as int, hours);
                    },
                  ),
                )),
            if (isSnoozed) ...[
              const SizedBox(height: 4),
              AppButton(
                label: 'Remove Snooze Now',
                icon: Icons.alarm_off_rounded,
                color: AppColors.accent,
                textColor: AppColors.background,
                onPressed: () async {
                  Navigator.pop(ctx);
                  try {
                    await ApiService.instance.patch(
                      '${ApiConstants.items}/${item['id']}/unsnooze',
                    );
                    await _loadItems();
                    if (mounted) _showSuccess('Item available again!');
                  } catch (e) {
                    if (mounted) _showError(ApiService.getErrorMessage(e));
                  }
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─── Delete confirm ───────────────────────────────
  Future<bool> _showDeleteConfirm(String name) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.surface,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text('Delete "$name"?', style: AppTextStyles.headlineMedium),
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

  // ─── Helpers ──────────────────────────────────────
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
