class UserModel {
  final int id;
  final String fullName;
  final String email;
  final String phone;
  final String role;
  final bool isActive;
  final bool isBlocked;
  final bool isEmailVerified;
  final double debtAmount;
  final String? driverMode;
  final bool isOnline;

  const UserModel({
    required this.id,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.role,
    required this.isActive,
    required this.isBlocked,
    required this.isEmailVerified,
    required this.debtAmount,
    this.driverMode,
    required this.isOnline,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] ?? 0,
      fullName: json['fullName'] ?? '',
      email: json['email'] ?? '',
      phone: json['phone'] ?? '',
      role: json['role'] ?? '',
      isActive: json['isActive'] ?? true,
      isBlocked: json['isBlocked'] ?? false,
      isEmailVerified: json['isEmailVerified'] ?? false,
      debtAmount: (json['debtAmount'] ?? 0).toDouble(),
      driverMode: json['driverMode'],
      isOnline: json['isOnline'] ?? false,
    );
  }

  bool get isMerchant => role == 'MERCHANT';
  bool get isDriver => role == 'DRIVER';
  bool get isCustomer => role == 'CUSTOMER';
  bool get isAdmin => role == 'ADMIN';
}
