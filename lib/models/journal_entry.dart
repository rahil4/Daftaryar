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
  final int? clientId; // برچسب شخص، مستقل از پروژه (مثلاً برای فروشنده بدون پروژه)

  JournalLineModel({
    this.id,
    this.entryId,
    required this.accountId,
    this.debit = 0,
    this.credit = 0,
    this.description,
    this.projectId,
    this.clientId,
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
      'clientId': clientId,
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
      clientId: map['clientId'] as int?,
    );
  }
}

class JournalEntryModel {
  final int? id;
  final String date; // شمسی yyyy/mm/dd
  final String? description;
  final String createdAt;
  final List<JournalLineModel> lines;

  JournalEntryModel({
    this.id,
    required this.date,
    this.description,
    required this.createdAt,
    required this.lines,
  });

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
    );
  }
}
