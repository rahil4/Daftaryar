// انواع رویداد تغییر مبلغ پروژه:
// ADDITION/REDUCTION/ADJUSTMENT: پیش از Finalization - فقط تاریخچه، بدون Journal
// FINAL_ADJUSTMENT: پس از Finalization - اصلاح مبلغ نهایی، با Journal اصلاحی
// DISCOUNT: پس از Finalization - تخفیف مستقل، با Journal تخفیف
const String kPriceEventAddition = 'ADDITION';
const String kPriceEventReduction = 'REDUCTION';
const String kPriceEventAdjustment = 'ADJUSTMENT';
const String kPriceEventFinalAdjustment = 'FINAL_ADJUSTMENT';
const String kPriceEventDiscount = 'DISCOUNT';

class ProjectPriceEventModel {
  final int? id;
  final int projectId;
  final String type;
  final double amount; // مقدار علامت‌دار: مثبت=افزایش مبلغ/درآمد، منفی=کاهش
  final String? reason;
  final String date; // شمسی yyyy/mm/dd
  final String createdAt;

  ProjectPriceEventModel({
    this.id,
    required this.projectId,
    required this.type,
    required this.amount,
    this.reason,
    required this.date,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'projectId': projectId,
      'type': type,
      'amount': amount,
      'reason': reason,
      'date': date,
      'createdAt': createdAt,
    };
  }

  factory ProjectPriceEventModel.fromMap(Map<String, dynamic> map) {
    return ProjectPriceEventModel(
      id: map['id'] as int?,
      projectId: map['projectId'] as int,
      type: map['type'] as String,
      amount: (map['amount'] as num).toDouble(),
      reason: map['reason'] as String?,
      date: map['date'] as String,
      createdAt: map['createdAt'] as String,
    );
  }
}
