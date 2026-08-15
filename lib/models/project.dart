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

class ProjectModel {
  final int? id;
  final String title;
  final int clientId;
  final String projectType;
  final String status;
  final String startDate; // شمسی yyyy/mm/dd
  final double agreedAmount;
  final String? description;
  final String createdAt;

  ProjectModel({
    this.id,
    required this.title,
    required this.clientId,
    required this.projectType,
    required this.status,
    required this.startDate,
    required this.agreedAmount,
    this.description,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'clientId': clientId,
      'projectType': projectType,
      'status': status,
      'startDate': startDate,
      'agreedAmount': agreedAmount,
      'description': description,
      'createdAt': createdAt,
    };
  }

  factory ProjectModel.fromMap(Map<String, dynamic> map) {
    return ProjectModel(
      id: map['id'] as int?,
      title: map['title'] as String,
      clientId: map['clientId'] as int,
      projectType: map['projectType'] as String,
      status: map['status'] as String,
      startDate: map['startDate'] as String,
      agreedAmount: (map['agreedAmount'] as num).toDouble(),
      description: map['description'] as String?,
      createdAt: map['createdAt'] as String,
    );
  }

  ProjectModel copyWith({
    int? id,
    String? title,
    int? clientId,
    String? projectType,
    String? status,
    String? startDate,
    double? agreedAmount,
    String? description,
    String? createdAt,
  }) {
    return ProjectModel(
      id: id ?? this.id,
      title: title ?? this.title,
      clientId: clientId ?? this.clientId,
      projectType: projectType ?? this.projectType,
      status: status ?? this.status,
      startDate: startDate ?? this.startDate,
      agreedAmount: agreedAmount ?? this.agreedAmount,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
