class CartItem {
  final int itemId;
  final String name;
  final double price;
  final String? imageUrl;
  int quantity;
  final String? categoryName;

  CartItem({
    required this.itemId,
    required this.name,
    required this.price,
    this.imageUrl,
    this.quantity = 1,
    this.categoryName,
  });

  double get subtotal => price * quantity;

  CartItem copyWith({int? quantity}) {
    return CartItem(
      itemId: itemId,
      name: name,
      price: price,
      imageUrl: imageUrl,
      quantity: quantity ?? this.quantity,
      categoryName: categoryName,
    );
  }
}
