/// طرف حساب: هر شخص یا سازمانی که دفتر از نظر مالی یا عملیاتی با او رابطه دارد.
/// Customer فقط یکی از نقش‌های ممکن این موجودیت است، نه معادل آن.
class CounterpartyModel {
  final int? id;
  final String name;
  final String? phone;
  final String? address;
  final String? nationalId;
  final String? notes;
  final bool isActive;
  final String createdAt; // شمسی yyyy/mm/dd
  final String updatedAt; // شمسی yyyy/mm/dd

  /// نام نقش‌های فعلی این طرف حساب - جداگانه از جدول اتصال بارگذاری می‌شود،
  /// بخشی از ساختار خام جدول counterparties نیست.
  final List<String> roles;

  CounterpartyModel({
    this.id,
    required this.name,
    this.phone,
    this.address,
    this.nationalId,
    this.notes,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
    this.roles = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'address': address,
      'nationalId': nationalId,
      'notes': notes,
      'isActive': isActive ? 1 : 0,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  factory CounterpartyModel.fromMap(Map<String, dynamic> map, {List<String>? roles}) {
    return CounterpartyModel(
      id: map['id'] as int?,
      name: map['name'] as String,
      phone: map['phone'] as String?,
      address: map['address'] as String?,
      nationalId: map['nationalId'] as String?,
      notes: map['notes'] as String?,
      isActive: (map['isActive'] as int? ?? 1) == 1,
      createdAt: map['createdAt'] as String,
      updatedAt: (map['updatedAt'] as String?) ?? (map['createdAt'] as String),
      roles: roles ?? const [],
    );
  }

  CounterpartyModel copyWith({
    int? id,
    String? name,
    String? phone,
    String? address,
    String? nationalId,
    String? notes,
    bool? isActive,
    String? createdAt,
    String? updatedAt,
    List<String>? roles,
  }) {
    return CounterpartyModel(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      nationalId: nationalId ?? this.nationalId,
      notes: notes ?? this.notes,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      roles: roles ?? this.roles,
    );
  }
}

/// نقش‌های پیش‌فرض طرف حساب — به‌عنوان ردیف در جدول counterparty_roles ذخیره
/// می‌شوند (نه ثابت کد)، تا افزودن نقش جدید در آینده نیازی به تغییر ساختار نداشته باشد.
const List<String> kDefaultCounterpartyRoles = [
  'مشتری',
  'پیمانکار',
  'صاحب ملک',
  'مدیر ساختمان',
  'تأمین‌کننده',
  'سایر',
];

const String kRoleCustomer = 'مشتری';

class CounterpartyRoleModel {
  final int? id;
  final String name;

  CounterpartyRoleModel({this.id, required this.name});

  Map<String, dynamic> toMap() => {'id': id, 'name': name};

  factory CounterpartyRoleModel.fromMap(Map<String, dynamic> map) {
    return CounterpartyRoleModel(id: map['id'] as int?, name: map['name'] as String);
  }
}
