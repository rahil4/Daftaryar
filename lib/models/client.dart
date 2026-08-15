class ClientModel {
  final int? id;
  final String name;
  final String? phone;
  final String? nationalId;
  final String? address;
  final String? notes;
  final String createdAt; // تاریخ شمسی رشته‌ای yyyy/mm/dd

  ClientModel({
    this.id,
    required this.name,
    this.phone,
    this.nationalId,
    this.address,
    this.notes,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'nationalId': nationalId,
      'address': address,
      'notes': notes,
      'createdAt': createdAt,
    };
  }

  factory ClientModel.fromMap(Map<String, dynamic> map) {
    return ClientModel(
      id: map['id'] as int?,
      name: map['name'] as String,
      phone: map['phone'] as String?,
      nationalId: map['nationalId'] as String?,
      address: map['address'] as String?,
      notes: map['notes'] as String?,
      createdAt: map['createdAt'] as String,
    );
  }

  ClientModel copyWith({
    int? id,
    String? name,
    String? phone,
    String? nationalId,
    String? address,
    String? notes,
    String? createdAt,
  }) {
    return ClientModel(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      nationalId: nationalId ?? this.nationalId,
      address: address ?? this.address,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
