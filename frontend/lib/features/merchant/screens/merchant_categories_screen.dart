import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_input.dart';

// ─── Emoji data organized by section ──────────────────
const _emojiSections = [
  {
    'label': 'Food & Drinks',
    'emojis': [
      '🍕',
      '🍔',
      '🌮',
      '🌯',
      '🥙',
      '🧆',
      '🥚',
      '🍳',
      '🥞',
      '🧇',
      '🥓',
      '🥩',
      '🍗',
      '🍖',
      '🌭',
      '🍟',
      '🧀',
      '🥪',
      '🥗',
      '🍜',
      '🍝',
      '🍲',
      '🍛',
      '🍣',
      '🍱',
      '🥟',
      '🦪',
      '🍤',
      '🍙',
      '🍚',
      '🍘',
      '🍥',
      '🥮',
      '🍢',
      '🍡',
      '🍧',
      '🍨',
      '🍦',
      '🥧',
      '🧁',
      '🍰',
      '🎂',
      '🍮',
      '🍭',
      '🍬',
      '🍫',
      '🍿',
      '🍩',
      '🍪',
      '🌰',
      '🥜',
      '🍯',
    ],
  },
  {
    'label': 'Fruits & Veggies',
    'emojis': [
      '🍎',
      '🍊',
      '🍋',
      '🍇',
      '🍓',
      '🍈',
      '🍒',
      '🍑',
      '🥭',
      '🍍',
      '🥥',
      '🥝',
      '🍅',
      '🍆',
      '🥑',
      '🥦',
      '🥬',
      '🥒',
      '🌽',
      '🌶️',
      '🥕',
      '🧅',
      '🧄',
      '🥔',
      '🍠',
      '🥐',
      '🍞',
      '🥖',
      '🥨',
      '🧀',
    ],
  },
  {
    'label': 'Beverages',
    'emojis': [
      '☕',
      '🍵',
      '🧃',
      '🥤',
      '🧋',
      '🍶',
      '🍺',
      '🍻',
      '🥂',
      '🍷',
      '🥃',
      '🍸',
      '🍹',
      '🧉',
      '🍾',
      '🧊',
      '💧',
      '🫖',
    ],
  },
  {
    'label': 'Other',
    'emojis': [
      '🛒',
      '📦',
      '🎁',
      '⭐',
      '🔥',
      '💎',
      '🏆',
      '🎯',
      '💰',
      '🛵',
      '🚗',
      '✈️',
      '🏠',
      '🏪',
      '🎪',
      '🎉',
      '❤️',
      '💚',
      '💛',
      '🧡',
      '💜',
      '🖤',
      '🤍',
      '🌟',
    ],
  },
];

class MerchantCategoriesScreen extends StatefulWidget {
  const MerchantCategoriesScreen({super.key});

  @override
  State<MerchantCategoriesScreen> createState() =>
      _MerchantCategoriesScreenState();
}

class _MerchantCategoriesScreenState extends State<MerchantCategoriesScreen> {
  List<dynamic> _categories = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  // ─── LOAD ─────────────────────────────────────────
  Future<void> _loadCategories() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final res = await ApiService.instance.get(ApiConstants.categories);
      if (!mounted) return;
      final data = res.data;
      setState(() => _categories =
          data is List ? data : (data as Map?)?['content'] as List? ?? []);
    } catch (e) {
      if (!mounted) return;
      _showError(ApiService.getErrorMessage(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── CREATE ───────────────────────────────────────
  Future<void> _createCategory(String name, String icon) async {
    try {
      await ApiService.instance.post(
        ApiConstants.categories,
        data: {'name': name, 'icon': icon},
      );
      await _loadCategories();
      if (mounted) _showSuccess('Category "$name" created!');
    } catch (e) {
      if (mounted) _showError(ApiService.getErrorMessage(e));
    }
  }

  // ─── UPDATE ───────────────────────────────────────
  Future<void> _updateCategory(
      int id, String name, String icon, bool isActive) async {
    try {
      await ApiService.instance.put(
        '${ApiConstants.categories}/$id',
        data: {'name': name, 'icon': icon, 'isActive': isActive},
      );
      await _loadCategories();
      if (mounted) _showSuccess('Category updated!');
    } catch (e) {
      if (mounted) _showError(ApiService.getErrorMessage(e));
    }
  }

  // ─── DELETE ───────────────────────────────────────
  Future<void> _deleteCategory(int id, String name) async {
    final confirmed = await _showDeleteConfirm(name);
    if (!confirmed) return;
    try {
      await ApiService.instance.delete('${ApiConstants.categories}/$id');
      await _loadCategories();
      if (mounted) _showSuccess('Category deleted.');
    } catch (e) {
      if (mounted) _showError(ApiService.getErrorMessage(e));
    }
  }

  // ─── TOGGLE ACTIVE ────────────────────────────────
  Future<void> _toggleCategory(Map<String, dynamic> cat) async {
    try {
      await ApiService.instance.put(
        '${ApiConstants.categories}/${cat['id']}',
        data: {
          'name': cat['name'],
          'icon': cat['icon'] ?? '',
          'isActive': !(cat['isActive'] as bool? ?? true),
        },
      );
      await _loadCategories();
    } catch (e) {
      if (mounted) _showError(ApiService.getErrorMessage(e));
    }
  }

  // ─── BUILD ────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                        ),
                      )
                    : _categories.isEmpty
                        ? _buildEmptyState()
                        : _buildCategoryList(),
              ),
            ],
          ),

          // ─── FAB ──────────────────────────────────
          Positioned(
            bottom: 24,
            right: 24,
            child: FloatingActionButton.extended(
              heroTag: 'cat_fab',
              onPressed: () => _showCategorySheet(),
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.background,
              icon: const Icon(Icons.add_rounded),
              label: Text(
                'Add Category',
                style: AppTextStyles.labelLarge
                    .copyWith(color: AppColors.background),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── HEADER ───────────────────────────────────────
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('My Menu', style: AppTextStyles.displayMedium),
              Text(
                '${_categories.length} categories',
                style: AppTextStyles.bodyMedium,
              ),
            ],
          ),
          const Spacer(),
          GestureDetector(
            onTap: _loadCategories,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.glassWhite,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: const Icon(
                Icons.refresh_rounded,
                color: AppColors.textPrimary,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── CATEGORY LIST ────────────────────────────────
  Widget _buildCategoryList() {
    return RefreshIndicator(
      onRefresh: _loadCategories,
      color: AppColors.primary,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 100),
        itemCount: _categories.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final cat = _categories[index] as Map<String, dynamic>;
          return _buildCategoryCard(cat);
        },
      ),
    );
  }

  // ─── CATEGORY CARD ────────────────────────────────
  Widget _buildCategoryCard(Map<String, dynamic> cat) {
    final isActive = cat['isActive'] as bool? ?? true;
    final icon = cat['icon'] as String?;

    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          // ─── Emoji icon ────────────────────
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isActive
                  ? AppColors.primary.withValues(alpha: 0.1)
                  : AppColors.glassWhite,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(
                (icon != null && icon.isNotEmpty) ? icon : '📦',
                style: const TextStyle(fontSize: 22),
              ),
            ),
          ),
          const SizedBox(width: 14),

          // ─── Name & status ─────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cat['name'] ?? '',
                  style: AppTextStyles.headlineMedium.copyWith(
                    color:
                        isActive ? AppColors.textPrimary : AppColors.textHint,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isActive ? 'Visible to customers' : 'Hidden',
                  style: AppTextStyles.caption.copyWith(
                    color: isActive ? AppColors.accent : AppColors.textHint,
                  ),
                ),
              ],
            ),
          ),

          // ─── Toggle ────────────────────────
          GestureDetector(
            onTap: () {
              if (!kIsWeb) HapticFeedback.lightImpact();
              _toggleCategory(cat);
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
                  color: isActive ? AppColors.accent : AppColors.glassBorder,
                ),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 200),
                alignment:
                    isActive ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: isActive ? AppColors.background : AppColors.textHint,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(width: 8),

          // ─── Edit ──────────────────────────
          GestureDetector(
            onTap: () => _showCategorySheet(existing: cat),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.edit_outlined,
                color: AppColors.primary,
                size: 18,
              ),
            ),
          ),

          const SizedBox(width: 8),

          // ─── Delete ────────────────────────
          GestureDetector(
            onTap: () =>
                _deleteCategory(cat['id'] as int, cat['name'] as String),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.delete_outline_rounded,
                color: AppColors.error,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── EMPTY STATE ──────────────────────────────────
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🗂️', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 16),
          Text('No categories yet', style: AppTextStyles.headlineMedium),
          const SizedBox(height: 8),
          Text(
            'Tap the button below\nto add your first category',
            style: AppTextStyles.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          AppButton(
            label: 'Add First Category',
            isFullWidth: false,
            icon: Icons.add_rounded,
            onPressed: () => _showCategorySheet(),
          ),
        ],
      ),
    );
  }

  // ─── BOTTOM SHEET with emoji picker ───────────────
  void _showCategorySheet({Map<String, dynamic>? existing}) {
    final nameController = TextEditingController(text: existing?['name'] ?? '');
    final formKey = GlobalKey<FormState>();
    final isEdit = existing != null;
    String selectedEmoji = existing?['icon'] ?? '';

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, scrollController) => Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Column(
              children: [
                // ─── Handle ─────────────────────────
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

                // ─── Title row ──────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      Text(
                        isEdit ? 'Edit Category' : 'New Category',
                        style: AppTextStyles.headlineLarge,
                      ),
                      const Spacer(),
                      // Live preview of selected emoji
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: selectedEmoji.isNotEmpty
                              ? AppColors.primary.withValues(alpha: 0.1)
                              : AppColors.glassWhite,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selectedEmoji.isNotEmpty
                                ? AppColors.primary.withValues(alpha: 0.4)
                                : AppColors.glassBorder,
                            width: selectedEmoji.isNotEmpty ? 2 : 1,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            selectedEmoji.isNotEmpty ? selectedEmoji : '?',
                            style: TextStyle(
                              fontSize: 24,
                              color: selectedEmoji.isEmpty
                                  ? AppColors.textHint
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // ─── Scrollable content ─────────────
                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Form(
                      key: formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ─── Name field ─────────────
                          AppInput(
                            controller: nameController,
                            hint: 'e.g. Burgers, Drinks, Desserts',
                            label: 'Category Name',
                            prefixIcon: Icons.label_outline,
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Name is required';
                              }
                              if (v.trim().length < 2) {
                                return 'Min 2 characters';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 24),

                          // ─── Emoji picker label ─────
                          Row(
                            children: [
                              Text(
                                'Pick an Icon',
                                style: AppTextStyles.headlineSmall,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '(optional)',
                                style: AppTextStyles.bodyMedium,
                              ),
                              const Spacer(),
                              if (selectedEmoji.isNotEmpty)
                                GestureDetector(
                                  onTap: () =>
                                      setSheetState(() => selectedEmoji = ''),
                                  child: Text(
                                    'Clear',
                                    style: AppTextStyles.bodyMedium.copyWith(
                                      color: AppColors.error,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // ─── Emoji sections ─────────
                          ..._emojiSections.map((section) {
                            final label = section['label'] as String;
                            final emojis = section['emojis'] as List<dynamic>;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Section label
                                Container(
                                  margin:
                                      const EdgeInsets.only(bottom: 10, top: 4),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    label.toUpperCase(),
                                    style: AppTextStyles.caption.copyWith(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                ),
                                // Emoji grid
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: emojis.map((e) {
                                    final emoji = e as String;
                                    final isSelected = selectedEmoji == emoji;
                                    return GestureDetector(
                                      onTap: () {
                                        if (!kIsWeb) {
                                          HapticFeedback.selectionClick();
                                        }
                                        setSheetState(
                                            () => selectedEmoji = emoji);
                                      },
                                      child: AnimatedContainer(
                                        duration:
                                            const Duration(milliseconds: 150),
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? AppColors.primary
                                                  .withValues(alpha: 0.15)
                                              : AppColors.glassWhite,
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          border: Border.all(
                                            color: isSelected
                                                ? AppColors.primary
                                                : AppColors.glassBorder,
                                            width: isSelected ? 2 : 1,
                                          ),
                                        ),
                                        child: Center(
                                          child: Text(
                                            emoji,
                                            style: TextStyle(
                                              fontSize: isSelected ? 22 : 20,
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                                const SizedBox(height: 20),
                              ],
                            );
                          }),

                          // ─── Save button ────────────
                          AppButton(
                            label: isEdit ? 'Save Changes' : 'Create Category',
                            icon: isEdit
                                ? Icons.save_outlined
                                : Icons.add_rounded,
                            onPressed: () async {
                              if (!formKey.currentState!.validate()) return;
                              Navigator.pop(ctx);
                              if (isEdit) {
                                await _updateCategory(
                                  existing!['id'] as int,
                                  nameController.text.trim(),
                                  selectedEmoji,
                                  existing['isActive'] as bool? ?? true,
                                );
                              } else {
                                await _createCategory(
                                  nameController.text.trim(),
                                  selectedEmoji,
                                );
                              }
                            },
                          ),

                          if (isEdit) ...[
                            const SizedBox(height: 12),
                            AppButton(
                              label: 'Delete Category',
                              icon: Icons.delete_outline_rounded,
                              color: AppColors.error,
                              onPressed: () async {
                                Navigator.pop(ctx);
                                await _deleteCategory(
                                  existing!['id'] as int,
                                  existing['name'] as String,
                                );
                              },
                            ),
                          ],
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(
              'Delete "$name"?',
              style: AppTextStyles.headlineMedium,
            ),
            content: Text(
              'This cannot be undone.',
              style: AppTextStyles.bodyMedium,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(
                  'Cancel',
                  style: AppTextStyles.labelLarge
                      .copyWith(color: AppColors.textHint),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(
                  'Delete',
                  style:
                      AppTextStyles.labelLarge.copyWith(color: AppColors.error),
                ),
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
