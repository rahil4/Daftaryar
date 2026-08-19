const String kSmsDraftPending = 'pending';
const String kSmsDraftConfirmed = 'confirmed';
const String kSmsDraftDismissed = 'dismissed';

class SmsDraftModel {
  final int? id;
  final String rawBody;
  final String? sender;
  final double amount;
  final String type; // 'دریافت' یا 'پرداخت'
  final String date; // شمسی yyyy/mm/dd
  final String status;
  final String createdAt;

  SmsDraftModel({
    this.id,
    required this.rawBody,
    this.sender,
    required this.amount,
    required this.type,
    required this.date,
    this.status = kSmsDraftPending,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'rawBody': rawBody,
      'sender': sender,
      'amount': amount,
      'type': type,
      'date': date,
      'status': status,
      'createdAt': createdAt,
    };
  }

  factory SmsDraftModel.fromMap(Map<String, dynamic> map) {
    return SmsDraftModel(
      id: map['id'] as int?,
      rawBody: map['rawBody'] as String,
      sender: map['sender'] as String?,
      amount: (map['amount'] as num).toDouble(),
      type: map['type'] as String,
      date: map['date'] as String,
      status: map['status'] as String,
      createdAt: map['createdAt'] as String,
    );
  }
}
