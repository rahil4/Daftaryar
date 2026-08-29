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

/// کلیدهای پایدار برای شناسایی حساب‌های کنترلی سیستم - جایگزین جستجوی
/// شکننده بر اساس نام (مرحله ۳.۱، اصلاح ۶)
const String kSystemKeyReceivable = 'accounts_receivable';
const String kSystemKeyPayable = 'accounts_payable';
const String kSystemKeyCash = 'cash';
const String kSystemKeyBank = 'bank';
const String kSystemKeyCustomerAdvance = 'customer_advance';
const String kSystemKeyCustomerCredit = 'customer_credit';
const String kSystemKeyProjectRevenue = 'project_revenue';
const String kSystemKeyProjectOverhead = 'project_overhead';
const String kSystemKeyDirectProjectCost = 'direct_project_cost';
const String kSystemKeyServiceDiscount = 'service_discount';

class AccountModel {
  final int? id;
  final String? code;
  final String name;
  final String type;
  final int? parentId;
  final bool isSystem;
  final String? systemKey; // شناسه پایدار برای حساب‌های کنترلی خاص (AR/AP و...)
  final String createdAt;

  AccountModel({
    this.id,
    this.code,
    required this.name,
    required this.type,
    this.parentId,
    this.isSystem = false,
    this.systemKey,
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
      'systemKey': systemKey,
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
      systemKey: map['systemKey'] as String?,
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
    String? systemKey,
    String? createdAt,
  }) {
    return AccountModel(
      id: id ?? this.id,
      code: code ?? this.code,
      name: name ?? this.name,
      type: type ?? this.type,
      parentId: clearParent ? null : (parentId ?? this.parentId),
      isSystem: isSystem ?? this.isSystem,
      systemKey: systemKey ?? this.systemKey,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
