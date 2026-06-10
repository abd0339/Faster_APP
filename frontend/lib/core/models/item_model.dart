class ItemModel {
  final int id;
  final String name;
  final String? description;
  final double price;
  final String? imageUrl;
  final int stockQuantity;
  final bool isAvailable;
  final bool isSnoozed;
  final int prepTimeMinutes;
  final double taxRate;
  final double serviceFee;
  final int displayOrder;
  final Map<String, dynamic>? category;

  const ItemModel({
    required this.id,
    required this.name,
    this.description,
    required this.price,
    this.imageUrl,
    required this.stockQuantity,
    required this.isAvailable,
    required this.isSnoozed,
    required this.prepTimeMinutes,
    required this.taxRate,
    required this.serviceFee,
    required this.displayOrder,
    this.category,
  });

  factory ItemModel.fromJson(Map<String, dynamic> json) {
    return ItemModel(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      description: json['description'],
      price: (json['price'] ?? 0).toDouble(),
      imageUrl: json['imageUrl'],
      stockQuantity: json['stockQuantity'] ?? -1,
      isAvailable: json['isAvailable'] ?? true,
      isSnoozed: json['isSnoozed'] ?? false,
      prepTimeMinutes: json['prepTimeMinutes'] ?? 15,
      taxRate: (json['taxRate'] ?? 0).toDouble(),
      serviceFee: (json['serviceFee'] ?? 0).toDouble(),
      displayOrder: json['displayOrder'] ?? 0,
      category: json['category'],
    );
  }

  // ─── Final price with tax ─────────────────────────
  double get finalPrice {
    final tax = price * taxRate;
    return price + tax + serviceFee;
  }

  bool get hasUnlimitedStock => stockQuantity == -1;
  bool get isInStock => stockQuantity == -1 || stockQuantity > 0;
}
