// تست‌های خالص واحد (بدون نیاز به دیتابیس) برای مدل‌هایی که مستقیماً مسبب
// باگ‌های Data Integrity این مرحله بودند: اگر متد copyWith یک مدل به‌درستی
// همه فیلدها را حفظ نکند، هر فرم Edit که به‌جای copyWith یک نمونه جدید
// می‌سازد، می‌تواند داده مالی حیاتی (مثل finalAmount) را گم کند - دقیقاً
// همان کلاس باگی که در project_form_screen.dart و account_form_screen.dart
// پیدا و اصلاح شد.
import 'package:flutter_test/flutter_test.dart';

import 'package:daftaryar/models/project.dart';
import 'package:daftaryar/models/account.dart';
import 'package:daftaryar/models/journal_entry.dart';

void main() {
  group('مورد ۱ — حفظ فیلدهای Finalization در ProjectModel', () {
    test('copyWith بدون آرگومان، تمام فیلدهای Finalization را حفظ می‌کند', () {
      final finalizedProject = ProjectModel(
        id: 1,
        title: 'پروژه تست',
        counterpartyId: 5,
        projectTypes: [kProjectTypes.first],
        status: kProjectStatusFinalized,
        startDate: '1404/01/01',
        agreedAmount: 80000000,
        createdAt: '1404/01/01',
        finalAmount: 120000000,
        finalizedDate: '1404/02/01',
        finalizedNote: 'یادداشت نهایی‌سازی',
      );

      // شبیه‌سازی «ویرایش فقط عنوان» - دقیقاً سناریوی معیار پذیرش مورد ۱
      final editedProject = finalizedProject.copyWith(title: 'عنوان جدید');

      expect(editedProject.title, 'عنوان جدید');
      expect(editedProject.finalAmount, 120000000,
          reason: 'finalAmount نباید هنگام ویرایش عنوان از بین برود');
      expect(editedProject.finalizedDate, '1404/02/01',
          reason: 'finalizedDate نباید هنگام ویرایش عنوان از بین برود');
      expect(editedProject.finalizedNote, 'یادداشت نهایی‌سازی',
          reason: 'finalizedNote نباید هنگام ویرایش عنوان از بین برود');
      expect(editedProject.status, kProjectStatusFinalized,
          reason: 'وضعیت نهایی‌شده باید حفظ شود');
      expect(editedProject.isFinalized, true);
    });

    test('toMap/fromMap فیلدهای Finalization را به‌درستی رفت‌وبرگشت می‌دهد', () {
      final project = ProjectModel(
        title: 'پروژه', counterpartyId: 1, projectTypes: [kProjectTypes.first],
        status: kProjectStatusFinalized, startDate: '1404/01/01', agreedAmount: 50000000,
        createdAt: '1404/01/01', finalAmount: 60000000, finalizedDate: '1404/03/01',
        finalizedNote: 'یادداشت',
      );
      final restored = ProjectModel.fromMap(project.toMap());
      expect(restored.finalAmount, 60000000);
      expect(restored.finalizedDate, '1404/03/01');
      expect(restored.finalizedNote, 'یادداشت');
      expect(restored.isFinalized, true);
    });

    test('projectTypes: ستون قدیمی projectType فقط برای سازگاری اولین نوع را نگه'
        ' می‌دارد، ولی منبع واقعی خواندن جدول اتصال است (نه این ستون)', () {
      final project = ProjectModel(
        title: 'پروژه چندنوعی',
        counterpartyId: 1,
        projectTypes: const ['تفکیک', 'افراز'],
        status: kProjectStatuses.first,
        startDate: '1404/01/01',
        agreedAmount: 10000000,
        createdAt: '1404/01/01',
      );
      final map = project.toMap();
      expect(map['projectType'], 'تفکیک',
          reason: 'ستون NOT NULL قدیمی باید اولین نوع را بگیرد تا Constraint دیتابیس نشکند');

      // بدون پاس‌دادن صریح projectTypes، لیست خالی است - چون این اطلاعات
      // در ساختار خام جدول projects وجود ندارد و باید جداگانه از جدول
      // اتصال بارگذاری شود (دقیقاً مثل roles در CounterpartyModel).
      final restoredWithout = ProjectModel.fromMap(map);
      expect(restoredWithout.projectTypes, isEmpty);

      final restoredWith = ProjectModel.fromMap(map, projectTypes: const ['تفکیک', 'افراز']);
      expect(restoredWith.projectTypes, ['تفکیک', 'افراز']);
    });

    test('پروژه بدون هیچ نوعی، رشته خالی در ستون سازگاری می‌نویسد (نه خطا)', () {
      final project = ProjectModel(
        title: 'بدون نوع',
        counterpartyId: 1,
        status: kProjectStatuses.first,
        startDate: '1404/01/01',
        agreedAmount: 0,
        createdAt: '1404/01/01',
      );
      expect(project.projectTypes, isEmpty);
      expect(project.toMap()['projectType'], '');
    });
  });

  group('مورد ۳ — حفظ systemKey در AccountModel', () {
    test('یک AccountModel جدید با systemKey صراحتاً پاس‌داده‌شده آن را حفظ می‌کند', () {
      // این دقیقاً همان الگویی است که account_form_screen.dart._save() باید
      // انجام دهد: systemKey از رکورد موجود گرفته و صراحتاً پاس داده شود.
      final existing = AccountModel(
        id: 1, name: 'حساب‌های دریافتنی', type: kAccountAsset,
        isSystem: true, systemKey: kSystemKeyReceivable, createdAt: '1404/01/01',
      );
      final edited = AccountModel(
        id: existing.id,
        name: 'نام جدید حساب', // فقط نام تغییر کرده
        type: existing.type,
        isSystem: existing.isSystem,
        systemKey: existing.systemKey, // باید صراحتاً حفظ شود
        createdAt: existing.createdAt,
      );
      expect(edited.systemKey, kSystemKeyReceivable,
          reason: 'ویرایش نام حساب سیستمی نباید systemKey را از بین ببرد');
      expect(edited.isSystem, true);
    });

    test('toMap/fromMap مقدار systemKey را به‌درستی رفت‌وبرگشت می‌دهد', () {
      final account = AccountModel(
        name: 'حساب', type: kAccountLiability, isSystem: true,
        systemKey: kSystemKeyCustomerAdvance, createdAt: '1404/01/01',
      );
      final restored = AccountModel.fromMap(account.toMap());
      expect(restored.systemKey, kSystemKeyCustomerAdvance);
    });
  });

  group('مورد ۴ — تشخیص سند System-generated', () {
    test('سند با source=system به‌عنوان System-generated شناسایی می‌شود', () {
      final entry = JournalEntryModel(
        date: '1404/01/01',
        createdAt: '1404/01/01',
        source: kJournalSourceSystem,
        lines: const [],
      );
      expect(entry.isSystemGenerated, true);
    });

    test('سند بدون source (دستی/فرم سریع معمولی) System-generated شناخته نمی‌شود', () {
      final entry = JournalEntryModel(
        date: '1404/01/01',
        createdAt: '1404/01/01',
        lines: const [],
      );
      expect(entry.isSystemGenerated, false);
    });

    test('toMap/fromMap مقدار source را به‌درستی رفت‌وبرگشت می‌دهد', () {
      final entry = JournalEntryModel(
        date: '1404/01/01', createdAt: '1404/01/01',
        source: kJournalSourceSystem, lines: const [],
      );
      final restored = JournalEntryModel.fromMap(entry.toMap());
      expect(restored.isSystemGenerated, true);
    });
  });
}
