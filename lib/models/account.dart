const String kAccountAsset = 'دارایی';
const String kAccountLiability = 'بدهی';
const String kAccountEquity = 'حقوق صاحبان سرمایه';
const String kAccountIncome = 'درآمد';
const String kAccountExpense = 'هزینه';

const List<String> kAccountTypes = [
  kAccountAsset,
  kAccountLiability,
  kAccountEquity,
  kAccountIncome,
  kAccountExpense,
];

/// آیا مانده طبیعی این نوع حساب بدهکار است؟ (دارایی و هزینه بدهکار، بقیه بستانکار)
bool isDebitNormal(String type) => type == kAccountAsset || type == kAccountExpense;

class AccountModel {
  final int? id;
  final String? code;
  final String name;
  final String type;
  final int? parentId;
  final bool isSystem;
  final String createdAt;

  AccountModel({
    this.id,
    this.code,
    required this.name,
    required this.type,
    this.parentId,
    this.isSystem = false,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'code': code,
      'name': name,
      'type': type,
      'parentId': parentId,
      'isSystem': isSystem ? 1 : 0,
      'createdAt': createdAt,
    };
  }

  factory AccountModel.fromMap(Map<String, dynamic> map) {
    return AccountModel(
      id: map['id'] as int?,
      code: map['code'] as String?,
      name: map['name'] as String,
      type: map['type'] as String,
      parentId: map['parentId'] as int?,
      isSystem: (map['isSystem'] as int) == 1,
      createdAt: map['createdAt'] as String,
    );
  }

  AccountModel copyWith({
    int? id,
    String? code,
    String? name,
    String? type,
    int? parentId,
    bool clearParent = false,
    bool? isSystem,
    String? createdAt,
  }) {
    return AccountModel(
      id: id ?? this.id,
      code: code ?? this.code,
      name: name ?? this.name,
      type: type ?? this.type,
      parentId: clearParent ? null : (parentId ?? this.parentId),
      isSystem: isSystem ?? this.isSystem,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
