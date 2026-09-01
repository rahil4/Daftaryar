/// مبالغ به تومان و به‌صورت عدد صحیح ذخیره می‌شوند (نه اعشاری)، چون در این
/// سیستم واحد پول همیشه تومانِ صحیح است؛ این کار هرگونه خطای محاسباتی
/// اعشاری (floating point) را در جمع‌بندی سند حسابداری کاملاً حذف می‌کند.
class JournalLineModel {
  final int? id;
  final int? entryId;
  final int accountId;
  final int debit;
  final int credit;
  final String? description;
  final int? projectId;
  final int? counterpartyId; // برچسب طرف حساب، مستقل از پروژه (مثلاً برای پیمانکار بدون پروژه)

  JournalLineModel({
    this.id,
    this.entryId,
    required this.accountId,
    this.debit = 0,
    this.credit = 0,
    this.description,
    this.projectId,
    this.counterpartyId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'entryId': entryId,
      'accountId': accountId,
      'debit': debit,
      'credit': credit,
      'description': description,
      'projectId': projectId,
      'counterpartyId': counterpartyId,
    };
  }

  factory JournalLineModel.fromMap(Map<String, dynamic> map) {
    return JournalLineModel(
      id: map['id'] as int?,
      entryId: map['entryId'] as int?,
      accountId: map['accountId'] as int,
      debit: (map['debit'] as num).round(),
      credit: (map['credit'] as num).round(),
      description: map['description'] as String?,
      projectId: map['projectId'] as int?,
      counterpartyId: map['counterpartyId'] as int?,
    );
  }
}

const String kJournalSourceSystem = 'system';

/// یک سند دستی/فرم سریع معمولی که کاربر مستقیماً ثبت کرده - تنها مقداری
/// که سند را واقعاً «قابل حذف» می‌کند.
const String kJournalSourceManual = 'manual';

class JournalEntryModel {
  final int? id;
  final String date; // شمسی yyyy/mm/dd
  final String? description;
  final String createdAt;
  final List<JournalLineModel> lines;

  /// منشأ سند: null/هر مقدار دیگر یعنی سند دستی یا فرم سریع معمولی (قابل
  /// حذف)؛ kJournalSourceSystem یعنی توسط یک Workflow مالی ساختاریافته
  /// (Finalization/Discount/Final Adjustment/Project Payment) ساخته شده و
  /// نباید حذف فیزیکی شود.
  final String? source;

  JournalEntryModel({
    this.id,
    required this.date,
    this.description,
    required this.createdAt,
    required this.lines,
    this.source,
  });

  bool get isSystemGenerated => source == kJournalSourceSystem;

  /// آیا این سند واقعاً قابل حذف فیزیکی است؟ طبق تصمیم مرحله Integrity
  /// Closure: فقط source == manual (صریح) قابل حذف است. اگر source برابر
  /// system باشد یا حتی NULL/نامشخص باشد (مثلاً سندهای قدیمی‌تر از افزودن
  /// این ستون که واقعاً می‌توانستند System-generated بوده باشند)، محافظه‌کارانه
  /// غیرقابل‌حذف در نظر گرفته می‌شود - حدس زده نمی‌شود که NULL یعنی «دستی».
  bool get isDeletable => source == kJournalSourceManual;

  int get totalDebit => lines.fold<int>(0, (s, l) => s + l.debit);
  int get totalCredit => lines.fold<int>(0, (s, l) => s + l.credit);

  /// توازن دقیق و بدون تلورانس اعشاری - چون مقادیر عدد صحیح‌اند، جمع دو طرف
  /// یا دقیقاً برابرند یا نیستند
  bool get isBalanced => totalDebit == totalCredit && totalDebit > 0;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': date,
      'description': description,
      'source': source,
      'createdAt': createdAt,
    };
  }

  factory JournalEntryModel.fromMap(Map<String, dynamic> map, {List<JournalLineModel>? lines}) {
    return JournalEntryModel(
      id: map['id'] as int?,
      date: map['date'] as String,
      description: map['description'] as String?,
      createdAt: map['createdAt'] as String,
      lines: lines ?? const [],
      source: map['source'] as String?,
    );
  }
}
