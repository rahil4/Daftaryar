/// یک عکس/رسید ضمیمه‌شده به یک سند حسابداری - فقط داده نمایشی/مرجع، هیچ
/// اثری روی محاسبات مالی ندارد.
class AttachmentModel {
  final int? id;
  final int entryId;
  final String filePath; // مسیر محلی فایل، داخل پوشه دائمی برنامه
  final String createdAt;

  AttachmentModel({
    this.id,
    required this.entryId,
    required this.filePath,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'entryId': entryId,
      'filePath': filePath,
      'createdAt': createdAt,
    };
  }

  factory AttachmentModel.fromMap(Map<String, dynamic> map) {
    return AttachmentModel(
      id: map['id'] as int?,
      entryId: map['entryId'] as int,
      filePath: map['filePath'] as String,
      createdAt: map['createdAt'] as String,
    );
  }
}
