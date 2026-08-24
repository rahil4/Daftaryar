class JournalLineModel {
  final int? id;
  final int? entryId;
  final int accountId;
  final double debit;
  final double credit;
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
      debit: (map['debit'] as num).toDouble(),
      credit: (map['credit'] as num).toDouble(),
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

  double get totalDebit => lines.fold(0, (s, l) => s + l.debit);
  double get totalCredit => lines.fold(0, (s, l) => s + l.credit);
  bool get isBalanced => (totalDebit - totalCredit).abs() < 0.01 && totalDebit > 0;

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
