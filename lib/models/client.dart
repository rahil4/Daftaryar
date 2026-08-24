const String kRelationEmployer = 'کارفرما';
const String kRelationVendor = 'فروشنده / تأمین‌کننده';
const String kRelationContractor = 'همکار / پیمانکار';
const String kRelationOther = 'سایر';

const List<String> kRelationTypes = [
  kRelationEmployer,
  kRelationVendor,
  kRelationContractor,
  kRelationOther,
];

class ClientModel {
  final int? id;
  final String name;
  final String? phone;
  final String? nationalId;
  final String? address;
  final String? notes;
  final String relationType; // نوع رابطه: کارفرما، فروشنده، همکار، سایر
  final String createdAt; // تاریخ شمسی رشته‌ای yyyy/mm/dd

  ClientModel({
    this.id,
    required this.name,
    this.phone,
    this.nationalId,
    this.address,
    this.notes,
    this.relationType = kRelationEmployer,
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
      'relationType': relationType,
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
      relationType: (map['relationType'] as String?) ?? kRelationEmployer,
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
    String? relationType,
    String? createdAt,
  }) {
    return ClientModel(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      nationalId: nationalId ?? this.nationalId,
      address: address ?? this.address,
      notes: notes ?? this.notes,
      relationType: relationType ?? this.relationType,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
