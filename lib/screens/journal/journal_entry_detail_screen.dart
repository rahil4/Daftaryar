import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../db/database_helper.dart';
import '../../models/account.dart';
import '../../models/attachment.dart';
import '../../models/journal_entry.dart';
import '../../services/attachment_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';

class JournalEntryDetailScreen extends StatefulWidget {
  final int entryId;
  const JournalEntryDetailScreen({super.key, required this.entryId});

  @override
  State<JournalEntryDetailScreen> createState() => _JournalEntryDetailScreenState();
}

class _JournalEntryDetailScreenState extends State<JournalEntryDetailScreen> {
  final _db = DatabaseHelper.instance;
  final _attachmentService = AttachmentService();
  JournalEntryModel? _entry;
  Map<int, AccountModel> _accounts = {};
  Map<int, String> _projectTitles = {};
  List<AttachmentModel> _attachments = [];
  bool _loading = true;
  bool _addingAttachment = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final entry = await _db.getJournalEntry(widget.entryId);
    final accounts = await _db.getAccounts();
    final projects = await _db.getProjects();
    final attachments = await _attachmentService.getAttachments(widget.entryId);
    setState(() {
      _entry = entry;
      _accounts = {for (final a in accounts) a.id!: a};
      _projectTitles = {for (final p in projects) p.id!: p.title};
      _attachments = attachments;
      _loading = false;
    });
  }

  Future<void> _addAttachment(ImageSource source) async {
    setState(() => _addingAttachment = true);
    try {
      final attachment =
          await _attachmentService.addAttachment(entryId: widget.entryId, source: source);
      if (attachment != null) {
        setState(() => _attachments = [..._attachments, attachment]);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))));
      }
    } finally {
      if (mounted) setState(() => _addingAttachment = false);
    }
  }

  Future<void> _pickAttachmentSource() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('گرفتن عکس با دوربین'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('انتخاب از گالری'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source != null) await _addAttachment(source);
  }

  Future<void> _deleteAttachment(AttachmentModel attachment) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف پیوست'),
        content: const Text('این عکس برای همیشه حذف می‌شود. ادامه می‌دهید؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف', style: TextStyle(color: AppColors.negative))),
        ],
      ),
    );
    if (confirm == true) {
      await _attachmentService.deleteAttachment(attachment);
      setState(() => _attachments = _attachments.where((a) => a.id != attachment.id).toList());
    }
  }

  void _viewAttachment(AttachmentModel attachment) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _AttachmentViewerScreen(filePath: attachment.filePath)),
    );
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف سند'),
        content: const Text('این سند حسابداری برای همیشه حذف می‌شود. ادامه می‌دهید؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف', style: TextStyle(color: AppColors.negative))),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await _db.deleteJournalEntry(widget.entryId);
        if (mounted) Navigator.pop(context, true);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSystemGenerated = _entry?.isSystemGenerated ?? false;
    return Scaffold(
      appBar: AppBar(
        title: Text('سند شماره ${pn(widget.entryId)}'),
        actions: [
          if (!isSystemGenerated)
            IconButton(icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      body: _loading || _entry == null
          ? const Center(child: CircularProgressIndicator())
          : BlueprintGridBackground(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (isSystemGenerated)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.brass.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'این سند توسط یک عملیات مالی سیستم (نهایی‌سازی/تخفیف/اصلاح/دریافت پروژه) ایجاد شده و برای حفظ یکپارچگی حساب‌ها قابل حذف نیست.',
                        style: TextStyle(fontSize: 12, color: AppColors.brass),
                      ),
                    ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('تاریخ: ${formatJalaliLong(_entry!.date)}'),
                          if (_entry!.description != null) ...[
                            const SizedBox(height: 6),
                            Text(_entry!.description!,
                                style: const TextStyle(color: AppColors.textSecondary)),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('سطرها', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  ..._entry!.lines.map((l) {
                    final account = _accounts[l.accountId];
                    final isDebit = l.debit > 0;
                    return Card(
                      child: ListTile(
                        leading: Icon(
                          isDebit ? Icons.arrow_downward : Icons.arrow_upward,
                          color: isDebit ? AppColors.positive : AppColors.negative,
                        ),
                        title: Text(account?.name ?? '—'),
                        subtitle: Text(
                          '${isDebit ? "بدهکار" : "بستانکار"}'
                          '${l.projectId != null && _projectTitles[l.projectId] != null ? ' · پروژه: ${_projectTitles[l.projectId]}' : ''}'
                          '${l.description != null ? '\n${l.description}' : ''}',
                        ),
                        isThreeLine: l.description != null,
                        trailing: Text(
                          formatMoney(isDebit ? l.debit : l.credit),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isDebit ? AppColors.positive : AppColors.negative,
                          ),
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  Card(
                    color: AppColors.surfaceAlt,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('جمع بدهکار / بستانکار'),
                          Text('${formatMoney(_entry!.totalDebit)} / ${formatMoney(_entry!.totalCredit)}'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('پیوست‌ها (عکس/رسید)', style: Theme.of(context).textTheme.titleMedium),
                      TextButton.icon(
                        onPressed: _addingAttachment ? null : _pickAttachmentSource,
                        icon: _addingAttachment
                            ? const SizedBox(
                                width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.add_photo_alternate_outlined, size: 18),
                        label: const Text('افزودن'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_attachments.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('هنوز عکسی ضمیمه نشده.',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _attachments
                          .map((a) => _AttachmentThumbnail(
                                attachment: a,
                                onTap: () => _viewAttachment(a),
                                onDelete: () => _deleteAttachment(a),
                              ))
                          .toList(),
                    ),
                ],
              ),
            ),
    );
  }
}

/// بندانگشتی یک پیوست با دکمه کوچک حذف روی گوشه.
class _AttachmentThumbnail extends StatelessWidget {
  final AttachmentModel attachment;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _AttachmentThumbnail({required this.attachment, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.file(
              File(attachment.filePath),
              width: 84,
              height: 84,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 84,
                height: 84,
                color: AppColors.surfaceAlt,
                child: const Icon(Icons.broken_image_outlined, color: AppColors.textSecondary),
              ),
            ),
          ),
          Positioned(
            top: 2,
            left: 2,
            child: GestureDetector(
              onTap: onDelete,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                child: const Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// نمایش تمام‌صفحه یک پیوست، با امکان بزرگ‌نمایی.
class _AttachmentViewerScreen extends StatelessWidget {
  final String filePath;
  const _AttachmentViewerScreen({required this.filePath});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, iconTheme: const IconThemeData(color: Colors.white)),
      body: Center(
        child: InteractiveViewer(
          child: Image.file(
            File(filePath),
            errorBuilder: (_, __, ___) =>
                const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 64),
          ),
        ),
      ),
    );
  }
}
