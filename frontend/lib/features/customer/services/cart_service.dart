import '../models/cart_item.dart';

class CartService {
  CartService._();
  static final CartService instance = CartService._();

  final List<CartItem> _items = [];
  int? _merchantId;
  String? _merchantName;

  List<CartItem> get items => List.unmodifiable(_items);
  int? get merchantId => _merchantId;
  String? get merchantName => _merchantName;
  bool get isEmpty => _items.isEmpty;
  int get totalItems => _items.fold(0, (sum, i) => sum + i.quantity);

  double get subtotal => _items.fold(0.0, (sum, i) => sum + i.subtotal);

  // ─── Add item ─────────────────────────────────────
  // Returns false if from different merchant (conflict)
  bool addItem(CartItem item, int merchantId, String merchantName) {
    // Different merchant — would need to clear cart first
    if (_merchantId != null && _merchantId != merchantId) {
      return false;
    }

    _merchantId = merchantId;
    _merchantName = merchantName;

    final existing = _items.indexWhere((i) => i.itemId == item.itemId);

    if (existing >= 0) {
      _items[existing] =
          _items[existing].copyWith(quantity: _items[existing].quantity + 1);
    } else {
      _items.add(item);
    }
    return true;
  }

  // ─── Remove item ──────────────────────────────────
  void removeItem(int itemId) {
    _items.removeWhere((i) => i.itemId == itemId);
    if (_items.isEmpty) clear();
  }

  // ─── Update quantity ──────────────────────────────
  void updateQuantity(int itemId, int quantity) {
    if (quantity <= 0) {
      removeItem(itemId);
      return;
    }
    final idx = _items.indexWhere((i) => i.itemId == itemId);
    if (idx >= 0) {
      _items[idx] = _items[idx].copyWith(quantity: quantity);
    }
  }

  // ─── Clear cart ───────────────────────────────────
  void clear() {
    _items.clear();
    _merchantId = null;
    _merchantName = null;
  }
}
