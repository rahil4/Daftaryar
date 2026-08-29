const List<String> kProjectTypes = [
  'تفکیک',
  'افراز',
  'سند تک‌برگ',
  'نقشه‌برداری UTM',
  'صورت‌مجلس اصلاحی',
  'هیئت حل اختلاف',
  'سایر',
];

const List<String> kProjectStatuses = [
  'در حال انجام',
  'تکمیل شده',
  'متوقف شده',
  'در انتظار مدارک',
];

// وضعیت‌های مالی مستقل از وضعیت عملیاتی بالا - طبق مدل جریان مالی پروژه
const String kProjectStatusFinalized = 'نهایی‌شده';
const String kProjectStatusCancelled = 'لغوشده';

class ProjectModel {
  final int? id;
  final String title;
  final int counterpartyId;
  final String projectType;
  final String status;
  final String startDate; // شمسی yyyy/mm/dd
  final double agreedAmount; // برآورد اولیه (Initial Estimate) - فقط در ایجاد پروژه ثبت می‌شود
  final String? description;
  final String createdAt;

  // فیلدهای Finalization - فقط یک‌بار در زمان نهایی‌سازی ست می‌شوند و پس از
  // آن دیگر overwrite نمی‌شوند؛ اصلاحات بعدی از طریق ProjectPriceEvent
  // (نوع FINAL_ADJUSTMENT) ثبت می‌شوند، نه با تغییر مستقیم این مقدار.
  final double? finalAmount;
  final String? finalizedDate;
  final String? finalizedNote;

  ProjectModel({
    this.id,
    required this.title,
    required this.counterpartyId,
    required this.projectType,
    required this.status,
    required this.startDate,
    required this.agreedAmount,
    this.description,
    required this.createdAt,
    this.finalAmount,
    this.finalizedDate,
    this.finalizedNote,
  });

  bool get isFinalized => finalAmount != null;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'counterpartyId': counterpartyId,
      'projectType': projectType,
      'status': status,
      'startDate': startDate,
      'agreedAmount': agreedAmount,
      'description': description,
      'createdAt': createdAt,
      'finalAmount': finalAmount,
      'finalizedDate': finalizedDate,
      'finalizedNote': finalizedNote,
    };
  }

  factory ProjectModel.fromMap(Map<String, dynamic> map) {
    return ProjectModel(
      id: map['id'] as int?,
      title: map['title'] as String,
      counterpartyId: map['counterpartyId'] as int,
      projectType: map['projectType'] as String,
      status: map['status'] as String,
      startDate: map['startDate'] as String,
      agreedAmount: (map['agreedAmount'] as num).toDouble(),
      description: map['description'] as String?,
      createdAt: map['createdAt'] as String,
      finalAmount: (map['finalAmount'] as num?)?.toDouble(),
      finalizedDate: map['finalizedDate'] as String?,
      finalizedNote: map['finalizedNote'] as String?,
    );
  }

  ProjectModel copyWith({
    int? id,
    String? title,
    int? counterpartyId,
    String? projectType,
    String? status,
    String? startDate,
    double? agreedAmount,
    String? description,
    String? createdAt,
    double? finalAmount,
    String? finalizedDate,
    String? finalizedNote,
  }) {
    return ProjectModel(
      id: id ?? this.id,
      title: title ?? this.title,
      counterpartyId: counterpartyId ?? this.counterpartyId,
      projectType: projectType ?? this.projectType,
      status: status ?? this.status,
      startDate: startDate ?? this.startDate,
      agreedAmount: agreedAmount ?? this.agreedAmount,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      finalAmount: finalAmount ?? this.finalAmount,
      finalizedDate: finalizedDate ?? this.finalizedDate,
      finalizedNote: finalizedNote ?? this.finalizedNote,
    );
  }
}
