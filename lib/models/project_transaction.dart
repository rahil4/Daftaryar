const String kTxReceipt = 'دریافت';
const String kTxPayment = 'پرداخت';

const List<String> kTxCategories = [
  'پیش‌پرداخت',
  'قسط میان‌کار',
  'تسویه نهایی',
  'هزینه نقشه‌برداری میدانی',
  'هزینه اداری/ثبتی',
  'حق‌الزحمه همکار',
  'سایر',
];

class ProjectTransactionModel {
  final int? id;
  final int projectId;
  final String type; // دریافت یا پرداخت
  final double amount;
  final String date; // شمسی yyyy/mm/dd
  final String category;
  final String? description;

  ProjectTransactionModel({
    this.id,
    required this.projectId,
    required this.type,
    required this.amount,
    required this.date,
    required this.category,
    this.description,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'projectId': projectId,
      'type': type,
      'amount': amount,
      'date': date,
      'category': category,
      'description': description,
    };
  }

  factory ProjectTransactionModel.fromMap(Map<String, dynamic> map) {
    return ProjectTransactionModel(
      id: map['id'] as int?,
      projectId: map['projectId'] as int,
      type: map['type'] as String,
      amount: (map['amount'] as num).toDouble(),
      date: map['date'] as String,
      category: map['category'] as String,
      description: map['description'] as String?,
    );
  }
}
