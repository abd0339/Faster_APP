class OrderModel {
  final int id;
  final String trackingCode;
  final String status;
  final String orderType;
  final double totalPrice;
  final double deliveryFee;
  final double commissionAmount;
  final double grandTotal;
  final String? pickupAddress;
  final String? deliveryAddress;
  final double? pickupLat;
  final double? pickupLng;
  final double? deliveryLat;
  final double? deliveryLng;
  final String? offlineCustomerPhone;
  final String? offlineCustomerLandmark;
  final String? customerNotes;
  final String? disputeReason;
  final String? createdAt;
  final String? updatedAt;
  final String? acceptedAt;
  final String? deliveredAt;
  final Map<String, dynamic>? driver;

  const OrderModel({
    required this.id,
    required this.trackingCode,
    required this.status,
    required this.orderType,
    required this.totalPrice,
    required this.deliveryFee,
    required this.commissionAmount,
    required this.grandTotal,
    this.pickupAddress,
    this.deliveryAddress,
    this.pickupLat,
    this.pickupLng,
    this.deliveryLat,
    this.deliveryLng,
    this.offlineCustomerPhone,
    this.offlineCustomerLandmark,
    this.customerNotes,
    this.disputeReason,
    this.createdAt,
    this.updatedAt,
    this.acceptedAt,
    this.deliveredAt,
    this.driver,
  });

  factory OrderModel.fromJson(
      Map<String, dynamic> json) {
    return OrderModel(
      id: json['id'] ?? 0,
      trackingCode: json['trackingCode'] ?? '',
      status: json['status'] ?? 'PENDING',
      orderType: json['orderType'] ?? 'LOGISTICS',
      totalPrice:
          (json['totalPrice'] ?? 0).toDouble(),
      deliveryFee:
          (json['deliveryFee'] ?? 0).toDouble(),
      commissionAmount:
          (json['commissionAmount'] ?? 0).toDouble(),
      grandTotal:
          (json['grandTotal'] ?? 0).toDouble(),
      pickupAddress: json['pickupAddress'],
      deliveryAddress: json['deliveryAddress'],
      pickupLat: json['pickupLat']?.toDouble(),
      pickupLng: json['pickupLng']?.toDouble(),
      deliveryLat: json['deliveryLat']?.toDouble(),
      deliveryLng: json['deliveryLng']?.toDouble(),
      offlineCustomerPhone:
          json['offlineCustomerPhone'],
      offlineCustomerLandmark:
          json['offlineCustomerLandmark'],
      customerNotes: json['customerNotes'],
      disputeReason: json['disputeReason'],
      createdAt: json['createdAt'],
      updatedAt: json['updatedAt'],
      acceptedAt: json['acceptedAt'],
      deliveredAt: json['deliveredAt'],
      driver: json['driver'],
    );
  }

  bool get isPending   => status == 'PENDING';
  bool get isAccepted  => status == 'ACCEPTED';
  bool get isPickedUp  => status == 'PICKED_UP';
  bool get isDelivered => status == 'DELIVERED';
  bool get isDisputed  => status == 'DISPUTED';
  bool get isO2O       => offlineCustomerPhone != null;
}