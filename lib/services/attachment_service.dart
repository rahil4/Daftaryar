import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../db/database_helper.dart';
import '../models/attachment.dart';
import '../utils/formatters.dart';

/// مدیریت پیوست عکس/رسید به سند - عکس انتخابی از دوربین یا گالری در پوشه
/// دائمی خودِ برنامه کپی می‌شود (نه فقط ارجاع به مسیر موقت انتخاب‌گر) تا با
/// پاک شدن کش سیستم یا حذف فایل اصلی از گالری از بین نرود.
class AttachmentService {
  final _db = DatabaseHelper.instance;
  final _picker = ImagePicker();

  Future<Directory> _attachmentsDir() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docsDir.path, 'attachments'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// انتخاب عکس (دوربین یا گالری)، کپی به پوشه دائمی، و ثبت در دیتابیس.
  /// اگر کاربر انتخاب/عکس‌برداری را لغو کند، null برمی‌گرداند - نه Exception.
  Future<AttachmentModel?> addAttachment({required int entryId, required ImageSource source}) async {
    final picked = await _picker.pickImage(source: source, imageQuality: 85);
    if (picked == null) return null;

    final dir = await _attachmentsDir();
    final ext = p.extension(picked.path).isNotEmpty ? p.extension(picked.path) : '.jpg';
    final destPath = p.join(dir.path, '${DateTime.now().microsecondsSinceEpoch}$ext');
    await File(picked.path).copy(destPath);

    final attachment = AttachmentModel(
      entryId: entryId,
      filePath: destPath,
      createdAt: todayJalaliString(),
    );
    final id = await _db.insertAttachment(attachment);
    return AttachmentModel(
        id: id, entryId: entryId, filePath: destPath, createdAt: attachment.createdAt);
  }

  Future<List<AttachmentModel>> getAttachments(int entryId) => _db.getAttachments(entryId);

  /// حذف کامل: هم ردیف دیتابیس و هم فایل واقعی روی دیسک. اگر فایل از قبل
  /// (مثلاً با دخالت دستی کاربر در فایل‌سیستم) موجود نباشد، خطا نمی‌دهد -
  /// حذف ردیف دیتابیس مهم‌تر از موفقیت حذف فایل است.
  Future<void> deleteAttachment(AttachmentModel attachment) async {
    await _db.deleteAttachment(attachment.id!);
    try {
      final file = File(attachment.filePath);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // حذف فایل بهترین‌تلاش است؛ شکست آن نباید عملیات حذف پیوست را متوقف کند.
    }
  }
}
