const List<String> kExpenseCategories = [
  'اجاره',
  'حقوق و دستمزد',
  'قبوض و انشعابات',
  'تجهیزات و نرم‌افزار',
  'حمل و نقل',
  'پذیرایی و اداری',
  'سایر',
];

class OfficeExpenseModel {
  final int? id;
  final String title;
  final String category;
  final double amount;
  final String date; // شمسی yyyy/mm/dd
  final String? description;

  OfficeExpenseModel({
    this.id,
    required this.title,
    required this.category,
    required this.amount,
    required this.date,
    this.description,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'category': category,
      'amount': amount,
      'date': date,
      'description': description,
    };
  }

  factory OfficeExpenseModel.fromMap(Map<String, dynamic> map) {
    return OfficeExpenseModel(
      id: map['id'] as int?,
      title: map['title'] as String,
      category: map['category'] as String,
      amount: (map['amount'] as num).toDouble(),
      date: map['date'] as String,
      description: map['description'] as String?,
    );
  }
}
