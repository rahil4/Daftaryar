import 'package:sqflite/sqflite.dart';

import '../db/database_helper.dart';
import '../models/journal_entry.dart';
import '../models/project.dart';
import '../models/project_price_event.dart';
import '../utils/formatters.dart';

/// لایه گردش‌کار مالی پروژه (Finalization/Discount/Adjustment/Receipt).
///
/// این سرویس استخراج‌شده از `DatabaseHelper` است (بدون هیچ تغییر رفتاری،
/// Schema یا فرمول مالی - صرفاً جابه‌جایی کد طبق قرارداد STABILITY.md).
/// هدف: جداکردن منطق *گردش‌کار* (نهایی‌سازی، تخفیف، اصلاح مبلغ نهایی،
/// دریافت/برگشت/ویرایش/تبدیل رسید) از لایه CRUD/Schema خام دیتابیس.
///
/// همه مانده‌ها و حساب‌های کنترلی همچنان فقط از طریق متدهای عمومی موجود
/// `DatabaseHelper` خوانده می‌شوند - نه فرمول موازی - تا اصل «یک منبع
/// حقیقت» که بقیه پروژه رعایت می‌کند، اینجا هم نقض نشود.
///
/// `DatabaseHelper` متدهای عمومی قدیمی (finalizeProject و ...) را هنوز
/// دارد، اما هرکدام فقط یک خط delegate به همین کلاس هستند - تا هیچ‌کدام
/// از تست‌ها یا صفحات UI موجود (که مستقیماً `DatabaseHelper.instance.xxx`
/// را صدا می‌زنند) نیاز به تغییر نداشته باشند.
class ProjectWorkflowService {
  final DatabaseHelper _db;
  ProjectWorkflowService(this._db);

  /// ساخت سطرهای بستانکار برای اعمال مبلغی به AR یک پروژه مشخص، با محافظت
  /// در برابر Overpayment: اگر مبلغ از مانده فعلی AR همان پروژه بیشتر باشد
  /// (مثلاً چون پیش‌دریافت یا دریافت مستقیم بیشتر از طلب واقعی بوده)، فقط
  /// به‌اندازه مانده به AR اعمال می‌شود و مازاد به‌جای منفی‌کردن AR، به حساب
  /// «بستانکاری مشتری (مازاد دریافتی)» می‌رود - ماهیت این مازاد را کاربر
  /// بعداً به‌صورت صریح مشخص می‌کند، سیستم آن را حدس نمی‌زند.
  Future<List<JournalLineModel>> _creditArWithOverflowGuard({
    required int projectId,
    required int counterpartyId,
    required int arAccountId,
    required double amount,
    DatabaseExecutor? executor,
  }) async {
    final currentAr = await _db.projectReceivableBalance(projectId, executor);
    final toAr = amount <= currentAr ? amount : currentAr;
    final excess = amount - toAr;
    final lines = <JournalLineModel>[];
    if (toAr > 0) {
      lines.add(JournalLineModel(
          accountId: arAccountId,
          credit: toAr.round(),
          projectId: projectId,
          counterpartyId: counterpartyId));
    }
    if (excess > 0) {
      final creditAccount = await _db.getCustomerCreditAccount(executor);
      if (creditAccount == null) {
        throw Exception('حساب «بستانکاری مشتری» برای ثبت مازاد دریافتی یافت نشد.');
      }
      lines.add(JournalLineModel(
          accountId: creditAccount.id!,
          credit: excess.round(),
          projectId: projectId,
          counterpartyId: counterpartyId));
    }
    return lines;
  }

  /// نهایی‌سازی پروژه (Finalization): مبلغ نهایی ثبت می‌شود (هرگز overwrite
  /// نمی‌شود)، درآمد پروژه شناسایی می‌شود، و مانده پیش‌دریافت موجود این پروژه
  /// به‌طور خودکار به حساب دریافتنی منتقل می‌شود.
  /// نهایی‌سازی پروژه - کاملاً Atomic از طریق یک Transaction واقعی دیتابیس
  /// (نه الگوی جبرانیِ قبلی که با delete دستی rollback می‌کرد). اگر هر
  /// مرحله (اعتبارسنجی سند دوم، یا حتی بروزرسانی نهایی پروژه) شکست بخورد،
  /// SQLite کل تراکنش را rollback می‌کند و هیچ سند یا تغییری باقی نمی‌ماند.
  Future<void> finalizeProject({
    required int projectId,
    required double finalAmount,
    required String date,
    String? note,
  }) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      final project = await _db.getProject(projectId, txn);
      if (project == null) throw Exception('پروژه یافت نشد.');
      if (project.isFinalized) {
        // Idempotency: نهایی‌سازی تکراری هرگز نباید سند دوم بسازد
        throw Exception('این پروژه قبلاً نهایی شده است.');
      }
      if (project.status == kProjectStatusCancelled) {
        // تکمیل همان Invariant که در updateProject تعریف شده: یک پروژه
        // نمی‌تواند هم‌زمان لغوشده و نهایی‌شده باشد؛ این ترکیب حالت باید
        // از هر دو مسیر (ویرایش عمومی و Workflow نهایی‌سازی) مسدود شود.
        throw Exception('پروژه لغوشده قابل نهایی‌سازی نیست.');
      }
      final arAccount = await _db.getReceivableAccount(txn);
      final revenueAccount = await _db.getProjectRevenueAccount(txn);
      final advanceAccount = await _db.getCustomerAdvanceAccount(txn);
      if (arAccount == null || revenueAccount == null || advanceAccount == null) {
        throw Exception('حساب‌های کنترلی موردنیاز (دریافتنی/درآمد پروژه/پیش‌دریافت) یافت نشدند.');
      }

      final revenueEntry = JournalEntryModel(
        date: date,
        description: 'نهایی‌سازی پروژه «${project.title}» - شناسایی درآمد',
        createdAt: todayJalaliString(),
        source: kJournalSourceSystem,
        lines: [
          JournalLineModel(
              accountId: arAccount.id!,
              debit: finalAmount.round(),
              projectId: projectId,
              counterpartyId: project.counterpartyId),
          JournalLineModel(
              accountId: revenueAccount.id!,
              credit: finalAmount.round(),
              projectId: projectId,
              counterpartyId: project.counterpartyId),
        ],
      );
      await _db.validateJournalEntry(revenueEntry, txn);
      await _db.writeJournalEntryRaw(txn, revenueEntry);

      // انتقال مانده پیش‌دریافت موجود همین پروژه به حساب دریافتنی - با
      // محافظت Overpayment: اگر پیش‌دریافت از مبلغ نهایی بیشتر باشد، مازاد
      // به AR منفی تبدیل نمی‌شود، بلکه به «بستانکاری مشتری» می‌رود. مانده
      // پیش‌دریافت از همین Transaction خوانده می‌شود، نه اتصال مستقل.
      final advanceBalance = await _db.projectAdvanceBalance(projectId, txn);
      if (advanceBalance > 0) {
        final creditLines = await _creditArWithOverflowGuard(
          projectId: projectId,
          counterpartyId: project.counterpartyId,
          arAccountId: arAccount.id!,
          amount: advanceBalance,
          executor: txn,
        );
        final advanceEntry = JournalEntryModel(
          date: date,
          description: 'انتقال پیش‌دریافت به حساب دریافتنی - پروژه «${project.title}»',
          createdAt: todayJalaliString(),
          source: kJournalSourceSystem,
          lines: [
            JournalLineModel(
                accountId: advanceAccount.id!,
                debit: advanceBalance.round(),
                projectId: projectId,
                counterpartyId: project.counterpartyId),
            ...creditLines,
          ],
        );
        await _db.validateJournalEntry(advanceEntry, txn);
        await _db.writeJournalEntryRaw(txn, advanceEntry);
      }

      final updatedProject = project.copyWith(
        finalAmount: finalAmount,
        finalizedDate: date,
        finalizedNote: note,
        status: kProjectStatusFinalized,
      );
      await txn.update('projects', updatedProject.toMap(), where: 'id = ?', whereArgs: [projectId]);
    });
  }

  /// ثبت تخفیف نهایی - فقط پس از Finalization مجاز است. تخفیف مبلغ نهایی
  /// اصلی را overwrite نمی‌کند؛ به‌صورت رویداد مستقل ذخیره و Journal می‌شود.
  Future<void> recordProjectDiscount({
    required int projectId,
    required double amount,
    String? reason,
    required String date,
  }) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      final project = await _db.getProject(projectId, txn);
      if (project == null || !project.isFinalized) {
        throw Exception('تخفیف فقط پس از نهایی‌سازی پروژه قابل ثبت است.');
      }
      final arAccount = await _db.getReceivableAccount(txn);
      final discountAccount = await _db.getServiceDiscountAccount(txn);
      if (arAccount == null || discountAccount == null) {
        throw Exception('حساب‌های کنترلی موردنیاز یافت نشدند.');
      }
      // تخفیف یک تصمیم عمدی کاربر است (نه دریافت پول از بیرون که باید جایی
      // پارک شود)؛ پس اگر از مانده طلب بیشتر باشد، به‌جای مسیر دادن به یک
      // حساب دیگر، به‌صراحت رد می‌شود تا کاربر عدد را اصلاح کند.
      final currentAr = await _db.projectReceivableBalance(projectId, txn);
      if (amount > currentAr) {
        throw Exception(
            'مبلغ تخفیف (${formatMoney(amount)}) از مانده طلب فعلی این پروژه (${formatMoney(currentAr)}) بیشتر است.');
      }
      final entry = JournalEntryModel(
        date: date,
        description: reason?.isNotEmpty == true ? 'تخفیف: $reason' : 'تخفیف نهایی پروژه',
        createdAt: todayJalaliString(),
        source: kJournalSourceSystem,
        lines: [
          JournalLineModel(
              accountId: discountAccount.id!,
              debit: amount.round(),
              projectId: projectId,
              counterpartyId: project.counterpartyId),
          JournalLineModel(
              accountId: arAccount.id!,
              credit: amount.round(),
              projectId: projectId,
              counterpartyId: project.counterpartyId),
        ],
      );
      await _db.validateJournalEntry(entry, txn);
      await _db.writeJournalEntryRaw(txn, entry);
      await _db.addProjectPriceEvent(
        projectId: projectId,
        type: kPriceEventDiscount,
        amount: -amount,
        reason: reason,
        date: date,
        executor: txn,
      );
    });
  }

  /// اصلاح مبلغ نهایی پس از Finalization (مثبت یا منفی) - Finalization قبلی
  /// را overwrite نمی‌کند، یک رویداد و یک سند اصلاحی مستقل ایجاد می‌کند.
  Future<void> recordFinalAdjustment({
    required int projectId,
    required double amount, // علامت‌دار: مثبت=افزایش درآمد، منفی=کاهش
    String? reason,
    required String date,
  }) async {
    if (amount == 0) return;
    final db = await _db.database;
    await db.transaction((txn) async {
      final project = await _db.getProject(projectId, txn);
      if (project == null || !project.isFinalized) {
        throw Exception('اصلاح مبلغ نهایی فقط پس از نهایی‌سازی پروژه ممکن است.');
      }
      final arAccount = await _db.getReceivableAccount(txn);
      final revenueAccount = await _db.getProjectRevenueAccount(txn);
      if (arAccount == null || revenueAccount == null) {
        throw Exception('حساب‌های کنترلی موردنیاز یافت نشدند.');
      }
      final magnitude = amount.abs().round();
      // اصلاح کاهشی، AR را بستانکار (کاهش) می‌دهد؛ اگر از مانده فعلی بیشتر
      // باشد، به‌جای منفی‌کردن AR، به‌صراحت رد می‌شود.
      if (amount < 0) {
        final currentAr = await _db.projectReceivableBalance(projectId, txn);
        if (magnitude > currentAr) {
          throw Exception(
              'مقدار کاهش (${formatMoney(magnitude)}) از مانده طلب فعلی این پروژه (${formatMoney(currentAr)}) بیشتر است.');
        }
      }
      final entry = JournalEntryModel(
        date: date,
        description: reason?.isNotEmpty == true ? 'اصلاح مبلغ نهایی: $reason' : 'اصلاح مبلغ نهایی پروژه',
        createdAt: todayJalaliString(),
        source: kJournalSourceSystem,
        lines: amount > 0
            ? [
                JournalLineModel(
                    accountId: arAccount.id!,
                    debit: magnitude,
                    projectId: projectId,
                    counterpartyId: project.counterpartyId),
                JournalLineModel(
                    accountId: revenueAccount.id!,
                    credit: magnitude,
                    projectId: projectId,
                    counterpartyId: project.counterpartyId),
              ]
            : [
                JournalLineModel(
                    accountId: revenueAccount.id!,
                    debit: magnitude,
                    projectId: projectId,
                    counterpartyId: project.counterpartyId),
                JournalLineModel(
                    accountId: arAccount.id!,
                    credit: magnitude,
                    projectId: projectId,
                    counterpartyId: project.counterpartyId),
              ],
      );
      await _db.validateJournalEntry(entry, txn);
      await _db.writeJournalEntryRaw(txn, entry);
      await _db.addProjectPriceEvent(
        projectId: projectId,
        type: kPriceEventFinalAdjustment,
        amount: amount,
        reason: reason,
        date: date,
        executor: txn,
      );
    });
  }

  /// دریافت وجه برای یک پروژه مشخص - مقصد بستانکار به‌صورت هوشمند تعیین
  /// می‌شود: پیش از Finalization همیشه «پیش‌دریافت مشتری» (هرگز درآمد)،
  /// پس از آن «حساب‌های دریافتنی» (تسویه طلب، نه درآمد جدید).
  Future<void> receiveProjectPayment({
    required int projectId,
    required int cashAccountId,
    required double amount,
    required String date,
    String? description,
  }) async {
    final project = await _db.getProject(projectId);
    if (project == null) throw Exception('پروژه یافت نشد.');
    final targetAccount = project.isFinalized
        ? await _db.getReceivableAccount()
        : await _db.getCustomerAdvanceAccount();
    if (targetAccount == null) {
      throw Exception('حساب کنترلی موردنیاز یافت نشد.');
    }

    // پیش از Finalization، پیش‌دریافت باز و بدون سقف است (چون برآورد قطعی
    // نیست)؛ پس از Finalization، دریافت مازاد بر مانده طلب باید به‌جای
    // منفی‌کردن AR، به «بستانکاری مشتری» برود.
    final creditLines = project.isFinalized
        ? await _creditArWithOverflowGuard(
            projectId: projectId,
            counterpartyId: project.counterpartyId,
            arAccountId: targetAccount.id!,
            amount: amount,
          )
        : [
            JournalLineModel(
                accountId: targetAccount.id!,
                credit: amount.round(),
                projectId: projectId,
                counterpartyId: project.counterpartyId),
          ];

    await _db.insertJournalEntry(JournalEntryModel(
      date: date,
      description: description?.isNotEmpty == true
          ? description!
          : (project.isFinalized ? 'دریافت طلب پروژه' : 'پیش‌دریافت پروژه'),
      createdAt: todayJalaliString(),
      source: kJournalSourceSystem,
      lines: [
        JournalLineModel(
            accountId: cashAccountId,
            debit: amount.round(),
            projectId: projectId,
            counterpartyId: project.counterpartyId),
        ...creditLines,
      ],
    ));
  }

  /// اصلاح یک سند «دریافت وجه پروژه» اشتباه (مثلاً چیزی که در واقع باید
  /// هزینه ثبت می‌شد ولی به‌اشتباه از مسیر دریافت وجه رفت). چون این سند
  /// سیستمی (source=system) است و برای حفظ یکپارچگی حساب‌ها قابل حذف
  /// فیزیکی نیست (رجوع به JournalEntryModel.isDeletable)، این متد به‌جای
  /// حذف، یک سند برگشتِ دقیقاً معکوس (بدهکار↔بستانکار هر سطر عوض می‌شود)
  /// ثبت می‌کند - سند اصلی دست‌نخورده در تاریخچه باقی می‌ماند و اثرش روی
  /// مانده‌ها توسط همین سند برگشت خنثی می‌شود.
  ///
  /// عمداً فقط روی سندهایی مجاز است که ساختاراً «دریافت وجه پروژه»اند (حداقل
  /// یک سطر بدهکار به حساب نقد/بانک) - نه بر مبنای متن توضیح (که کاربر
  /// می‌تواند تغییرش داده باشد). سایر اسناد سیستمی (نهایی‌سازی/تخفیف/اصلاح
  /// مبلغ نهایی) عمداً رد می‌شوند: برگشت آن‌ها فیلدهای وضعیت پروژه را هم
  /// می‌طلبد (finalAmount/isFinalized) که این متد تضمینش نمی‌کند.
  Future<int> reverseProjectReceipt(int originalEntryId, {String? date}) async {
    final original = await _db.getJournalEntry(originalEntryId);
    if (original == null) throw Exception('سند یافت نشد.');
    if (!original.isSystemGenerated) {
      throw Exception('این سند دستی است و می‌توانید مستقیماً از صفحه سند حذفش کنید.');
    }

    final accounts = await _db.getAccounts();
    final accountsById = {for (final a in accounts) a.id!: a};
    final hasCashDebitLine =
        original.lines.any((l) => l.debit > 0 && _db.isCashOrBankById(l.accountId, accountsById));
    if (!hasCashDebitLine) {
      throw Exception('این سند «دریافت وجه پروژه» نیست؛ فقط این نوع سند قابل اصلاح خودکار است.');
    }

    final projectId = original.lines
        .firstWhere((l) => l.projectId != null, orElse: () => original.lines.first)
        .projectId;
    final marker = '(سند اصلی #$originalEntryId)';

    if (projectId != null) {
      final existing = await _db.getJournalEntries(projectId: projectId);
      if (existing.any((e) => e.description?.contains(marker) == true)) {
        throw Exception('این سند قبلاً اصلاح شده است.');
      }

      // اگر از زمان ثبت این دریافت، وضعیت پروژه طوری تغییر کرده که برگرداندنش
      // مانده حساب مقصد (پیش‌دریافت/بستانکاری مشتری) را منفی می‌کند (مثلاً
      // پروژه از آن زمان نهایی و پیش‌دریافتش به‌طور کامل به دریافتنی منتقل
      // شده)، اصلاح خودکار متوقف می‌شود - این وضعیتی است که یک سند برگشت
      // ساده نمی‌تواند درستش کند. توجه: مقصد «دریافتنی» عمداً بررسی نمی‌شود،
      // چون برگشتش فقط طلب را افزایش (بدهکار) می‌کند که هیچ کف صفری ندارد.
      final advanceAccount = await _db.getCustomerAdvanceAccount();
      final creditAccount = await _db.getCustomerCreditAccount();
      for (final l in original.lines) {
        if (l.credit <= 0) continue;
        double? currentBalance;
        if (advanceAccount != null && l.accountId == advanceAccount.id) {
          currentBalance = await _db.projectAdvanceBalance(projectId);
        } else if (creditAccount != null && l.accountId == creditAccount.id) {
          currentBalance = await _db.projectCustomerCreditBalance(projectId);
        }
        if (currentBalance != null && currentBalance < l.credit) {
          throw Exception(
              'وضعیت این پروژه از زمان ثبت این دریافت تغییر کرده (برای مثال پروژه نهایی و پیش‌دریافتش مصرف شده) و دیگر قابل اصلاح خودکار نیست. برای رفع، یک سند دستی اصلاحی ثبت کنید.');
        }
      }
    }

    final reversalLines = original.lines
        .map((l) => JournalLineModel(
              accountId: l.accountId,
              debit: l.credit,
              credit: l.debit,
              projectId: l.projectId,
              counterpartyId: l.counterpartyId,
              description: l.description,
            ))
        .toList();

    return _db.insertJournalEntry(JournalEntryModel(
      date: date ?? todayJalaliString(),
      description: 'اصلاح: برگشت سند دریافت اشتباه $marker',
      createdAt: todayJalaliString(),
      source: kJournalSourceSystem,
      lines: reversalLines,
    ));
  }

  /// ویرایش مستقیم یک سند «دریافت وجه پروژه» موجود (مبلغ/حساب نقد یا
  /// بانک/تاریخ/توضیح) - بدون ساختن سند جدید یا برگشت؛ خودِ همان سند در
  /// جای خودش اصلاح می‌شود (طبق درخواست صریح کاربر که reverseProjectReceipt
  /// را برای اصلاح یک عدد/حساب ساده اشتباه، دو-سندی و ناکافی دانست).
  ///
  /// فقط روی سندهایی مجاز است که ساختاراً «دریافت وجه پروژه»ی ساده‌اند:
  /// دقیقاً دو سطر (بدهکار نقد/بانک + بستانکار یک حساب کنترلی واحد -
  /// دریافتنی یا پیش‌دریافت). سندهایی که به‌دلیل Overpayment بین چند حساب
  /// تقسیم شده‌اند (بیش از دو سطر) از این مسیر رد می‌شوند - پیچیدگی تقسیم
  /// را نمی‌توان با یک فرم ساده ویرایش کرد؛ برای آن‌ها reverseProjectReceipt
  /// باقی می‌ماند. حساب کنترلی مقصد (دریافتنی/پیش‌دریافت) و پروژه/طرف‌حساب
  /// عمداً قابل تغییر نیستند - این‌ها با وضعیت Finalize بودن پروژه در زمان
  /// ثبت اصلی تعیین شده‌اند، نه یک انتخاب آزاد فرم ویرایش.
  Future<void> updateProjectReceipt({
    required int entryId,
    required int cashAccountId,
    required double amount,
    required String date,
    String? description,
  }) async {
    if (amount <= 0) throw Exception('مبلغ باید بزرگ‌تر از صفر باشد.');
    final original = await _db.getJournalEntry(entryId);
    if (original == null) throw Exception('سند یافت نشد.');
    if (!original.isSystemGenerated) {
      throw Exception('این سند دستی است؛ می‌توانید مستقیماً از صفحه سند حذف و دوباره ثبتش کنید.');
    }
    final accounts = await _db.getAccounts();
    final accountsById = {for (final a in accounts) a.id!: a};
    final cashLines =
        original.lines.where((l) => l.debit > 0 && _db.isCashOrBankById(l.accountId, accountsById)).toList();
    if (cashLines.isEmpty) {
      throw Exception('این سند «دریافت وجه پروژه» نیست؛ فقط این نوع سند قابل ویرایش مستقیم است.');
    }
    if (original.lines.length != 2) {
      throw Exception(
          'این سند به‌دلیل ساختار خاص (تقسیم‌شده بین چند حساب، معمولاً بابت مازاد دریافتی) قابل ویرایش مستقیم نیست؛ از «اصلاح دریافت اشتباه» استفاده کنید.');
    }
    final creditLine = original.lines.firstWhere((l) => l.credit > 0);

    // اگر حساب مقصد این دریافت پیش‌دریافت یا بستانکاری مشتری باشد و از
    // زمان ثبت این دریافت وضعیت پروژه طوری تغییر کرده که موجودی فعلی آن
    // حساب کمتر از سهم همین سند است (مثلاً پروژه از آن‌موقع نهایی و کل
    // پیش‌دریافتش به دریافتنی منتقل شده)، ویرایش متوقف می‌شود - همان
    // محافظتی که در reverseProjectReceipt هم هست. توجه: مقصد «دریافتنی»
    // عمداً بررسی نمی‌شود چون validateJournalEntry پایین‌تر خودش کاهش/
    // افزایش AR را با Overpayment Guard می‌سنجد.
    if (creditLine.projectId != null) {
      final advanceAccount = await _db.getCustomerAdvanceAccount();
      final creditAccount = await _db.getCustomerCreditAccount();
      double? currentBalance;
      if (advanceAccount != null && creditLine.accountId == advanceAccount.id) {
        currentBalance = await _db.projectAdvanceBalance(creditLine.projectId!);
      } else if (creditAccount != null && creditLine.accountId == creditAccount.id) {
        currentBalance = await _db.projectCustomerCreditBalance(creditLine.projectId!);
      }
      if (currentBalance != null && currentBalance < creditLine.credit) {
        throw Exception(
            'وضعیت این پروژه از زمان ثبت این دریافت تغییر کرده (برای مثال پروژه نهایی و پیش‌دریافتش مصرف شده) و دیگر قابل ویرایش مستقیم نیست. برای رفع، یک سند دستی اصلاحی ثبت کنید.');
      }
    }

    final db = await _db.database;
    await db.transaction((txn) async {
      // ابتدا سطرهای قبلی حذف می‌شوند تا بررسی مانده‌ها (Overpayment Guard
      // در validateJournalEntry) نسبت به وضعیتِ «بدون این سند» انجام شود،
      // نه با احتساب دوباره اثر خودِ همین سند پیش از ویرایش.
      await txn.delete('journal_lines', where: 'entryId = ?', whereArgs: [entryId]);
      final newEntry = JournalEntryModel(
        id: entryId,
        date: date,
        description: description,
        createdAt: original.createdAt,
        source: kJournalSourceSystem,
        lines: [
          JournalLineModel(
              accountId: cashAccountId,
              debit: amount.round(),
              projectId: cashLines.first.projectId,
              counterpartyId: cashLines.first.counterpartyId),
          JournalLineModel(
              accountId: creditLine.accountId,
              credit: amount.round(),
              projectId: creditLine.projectId,
              counterpartyId: creditLine.counterpartyId),
        ],
      );
      await _db.validateJournalEntry(newEntry, txn);
      await txn.update('journal_entries', {'date': date, 'description': description},
          where: 'id = ?', whereArgs: [entryId]);
      for (final line in newEntry.lines) {
        final map = line.toMap()
          ..remove('id')
          ..['entryId'] = entryId;
        await txn.insert('journal_lines', map);
      }
    });
  }

  /// تبدیل یک سند «دریافت وجه پروژه» که در واقع باید هزینه ثبت می‌شد
  /// (اشتباه در نوع/ماهیت سند، نه فقط مبلغ) به یک سند هزینه واقعی - همان
  /// سند، در جای خودش، از ریخت دریافت (بدهکار نقد/بستانکار دریافتنی یا
  /// پیش‌دریافت) به ریخت هزینه (بدهکار هزینه/بستانکار نقد) تغییر می‌کند.
  ///
  /// برخلاف updateProjectReceipt (که فقط مبلغ/حساب را در همان ریخت دریافت
  /// اصلاح می‌کند)، این متد source سند را هم از system به manual تغییر
  /// می‌دهد: از این پس این سند واقعاً یک هزینه دستی معمولی است - همان‌قدر
  /// قابل حذف/ویرایش که هر سند دستی دیگر (رجوع به
  /// JournalEntryModel.isDeletable)، بدون نیاز به هیچ مکانیزم اختصاصی
  /// دیگری برایش.
  Future<void> convertReceiptToExpense({
    required int entryId,
    required int expenseAccountId,
    required int cashAccountId,
    required double amount,
    required String date,
    String? description,
  }) async {
    if (amount <= 0) throw Exception('مبلغ باید بزرگ‌تر از صفر باشد.');
    final original = await _db.getJournalEntry(entryId);
    if (original == null) throw Exception('سند یافت نشد.');
    if (!original.isSystemGenerated) {
      throw Exception('این سند دستی است و همین حالا هم قابل حذف/اصلاح مستقیم است.');
    }
    final accounts = await _db.getAccounts();
    final accountsById = {for (final a in accounts) a.id!: a};
    final cashLines =
        original.lines.where((l) => l.debit > 0 && _db.isCashOrBankById(l.accountId, accountsById)).toList();
    if (cashLines.isEmpty) {
      throw Exception('این سند «دریافت وجه پروژه» نیست؛ فقط این نوع سند قابل تبدیل به هزینه است.');
    }
    if (original.lines.length != 2) {
      throw Exception(
          'این سند به‌دلیل ساختار خاص (تقسیم‌شده بین چند حساب، معمولاً بابت مازاد دریافتی) قابل تبدیل مستقیم نیست؛ از «اصلاح دریافت اشتباه» استفاده کنید.');
    }
    final creditLine = original.lines.firstWhere((l) => l.credit > 0);

    // همان محافظت updateProjectReceipt: اگر از زمان ثبت این دریافت،
    // وضعیت پروژه طوری تغییر کرده که حذف اثر آن روی پیش‌دریافت/بستانکاری
    // مشتری منفی می‌شود، تبدیل خودکار متوقف می‌شود.
    if (creditLine.projectId != null) {
      final advanceAccount = await _db.getCustomerAdvanceAccount();
      final creditAccount = await _db.getCustomerCreditAccount();
      double? currentBalance;
      if (advanceAccount != null && creditLine.accountId == advanceAccount.id) {
        currentBalance = await _db.projectAdvanceBalance(creditLine.projectId!);
      } else if (creditAccount != null && creditLine.accountId == creditAccount.id) {
        currentBalance = await _db.projectCustomerCreditBalance(creditLine.projectId!);
      }
      if (currentBalance != null && currentBalance < creditLine.credit) {
        throw Exception(
            'وضعیت این پروژه از زمان ثبت این دریافت تغییر کرده (برای مثال پروژه نهایی و پیش‌دریافتش مصرف شده) و دیگر قابل تبدیل خودکار نیست. برای رفع، یک سند دستی اصلاحی ثبت کنید.');
      }
    }

    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.delete('journal_lines', where: 'entryId = ?', whereArgs: [entryId]);
      final newEntry = JournalEntryModel(
        id: entryId,
        date: date,
        description: description,
        createdAt: original.createdAt,
        source: kJournalSourceManual,
        lines: [
          JournalLineModel(
              accountId: expenseAccountId,
              debit: amount.round(),
              projectId: cashLines.first.projectId,
              counterpartyId: cashLines.first.counterpartyId),
          JournalLineModel(
              accountId: cashAccountId,
              credit: amount.round(),
              projectId: cashLines.first.projectId,
              counterpartyId: cashLines.first.counterpartyId),
        ],
      );
      await _db.validateJournalEntry(newEntry, txn);
      await txn.update(
          'journal_entries',
          {'date': date, 'description': description, 'source': kJournalSourceManual},
          where: 'id = ?',
          whereArgs: [entryId]);
      for (final line in newEntry.lines) {
        final map = line.toMap()
          ..remove('id')
          ..['entryId'] = entryId;
        await txn.insert('journal_lines', map);
      }
    });
  }

  /// اصلاح یک سند «تخفیف» اشتباه با ثبت یک سند برگشتِ دقیقاً معکوس -
  /// مشابه reverseProjectReceipt، اما برای تخفیف. برخلاف دریافت وجه،
  /// اینجا امکان «ویرایش مستقیم» ارائه نمی‌شود: هر تخفیف علاوه بر سند
  /// حسابداری، یک ردیف در project_price_events هم دارد که هیچ کلید خارجی
  /// به سند مرتبطش ندارد (ستون entryId روی آن جدول وجود ندارد)؛ افزودن
  /// چنین ستونی یک ALTER TABLE است و طبق قرارداد پایداری (STABILITY.md)
  /// نیازمند توقف و گفت‌وگوی جداست، نه یک رفع باگ ساده. برای همین، اصلاح
  /// اینجا هم به روش برگشت (Append-Only) انجام می‌شود: هم یک سند برگشت
  /// حسابداری و هم یک رویداد قیمتِ خنثی‌کننده (علامت مخالف) اضافه می‌شود -
  /// نیازی به یافتن/ویرایش ردیف قیمت اصلی نیست، فقط جمعش خنثی می‌شود.
  Future<int> reverseProjectDiscount(int entryId) async {
    final original = await _db.getJournalEntry(entryId);
    if (original == null) throw Exception('سند یافت نشد.');
    if (!original.isSystemGenerated) {
      throw Exception('این سند دستی است؛ می‌توانید مستقیماً از صفحه سند حذفش کنید.');
    }
    final discountAccount = await _db.getServiceDiscountAccount();
    final discountLine = discountAccount == null
        ? null
        : original.lines.where((l) => l.accountId == discountAccount.id && l.debit > 0).firstOrNull;
    if (discountLine == null) {
      throw Exception('این سند «تخفیف» نیست؛ فقط این نوع سند با این عملیات قابل اصلاح است.');
    }

    final projectId = discountLine.projectId;
    final marker = '(سند اصلی #$entryId)';
    if (projectId != null) {
      final existing = await _db.getJournalEntries(projectId: projectId);
      if (existing.any((e) => e.description?.contains(marker) == true)) {
        throw Exception('این سند قبلاً اصلاح شده است.');
      }
    }

    final reversalLines = original.lines
        .map((l) => JournalLineModel(
              accountId: l.accountId,
              debit: l.credit,
              credit: l.debit,
              projectId: l.projectId,
              counterpartyId: l.counterpartyId,
              description: l.description,
            ))
        .toList();
    // سند برگشت و رویداد قیمتِ خنثی‌کننده در یک تراکنش: یا هر دو ثبت
    // می‌شوند یا هیچ‌کدام - وگرنه دفتر برگشت می‌خورد ولی «تخفیف کل» پروژه
    // مقدار قبلی را نشان می‌دهد.
    final db = await _db.database;
    return db.transaction((txn) async {
      final newEntryId = await _db.insertJournalEntry(
          JournalEntryModel(
            date: todayJalaliString(),
            description: 'اصلاح: برگشت سند تخفیف اشتباه $marker',
            createdAt: todayJalaliString(),
            source: kJournalSourceSystem,
            lines: reversalLines,
          ),
          txn);
      if (projectId != null) {
        // رویداد اصلی با amount منفی ثبت شده بود (recordProjectDiscount)؛
        // رویداد خنثی‌کننده با همان مقدار ولی مثبت، جمع را دقیقاً به حالت
        // قبل برمی‌گرداند.
        await _db.addProjectPriceEvent(
          projectId: projectId,
          type: kPriceEventDiscount,
          amount: discountLine.debit.toDouble(),
          reason: 'برگشت تخفیف اشتباه $marker',
          date: todayJalaliString(),
          executor: txn,
        );
      }
      return newEntryId;
    });
  }

  /// اصلاح یک سند «اصلاح مبلغ نهایی» اشتباه با ثبت یک سند برگشتِ دقیقاً
  /// معکوس - رجوع به توضیح reverseProjectDiscount برای این‌که چرا اینجا
  /// هم فقط برگشت (نه ویرایش مستقیم) ارائه می‌شود.
  ///
  /// تشخیص این سند صرفاً بر مبنای متن توضیح کافی نیست (چون سند «نهایی‌سازی
  /// - شناسایی درآمد» هم دقیقاً همان دو حساب - دریافتنی/درآمد - را لمس
  /// می‌کند)؛ پس هر دو شرط با هم لازم است: (۱) توضیح دقیقاً با پیشوند
  /// ثابت و غیرقابل‌تغییر توسط کاربر «اصلاح مبلغ نهایی» شروع شود (برخلاف
  /// توضیح آزاد سند دریافت وجه، اینجا کاربر فقط می‌تواند یک «دلیل» بعد از
  /// این پیشوند اضافه کند، نه کل توضیح را جایگزین کند) و (۲) سند هیچ سطر
  /// نقد/بانکی نداشته باشد (تا یک دریافت وجه با توضیح دستکاری‌شده مشابه،
  /// اشتباهاً به‌عنوان اصلاح مبلغ نهایی شناسایی نشود).
  Future<int> reverseFinalAdjustment(int entryId) async {
    final original = await _db.getJournalEntry(entryId);
    if (original == null) throw Exception('سند یافت نشد.');
    if (!original.isSystemGenerated) {
      throw Exception('این سند دستی است؛ می‌توانید مستقیماً از صفحه سند حذفش کنید.');
    }
    if (original.description == null || !original.description!.startsWith('اصلاح مبلغ نهایی')) {
      throw Exception('این سند «اصلاح مبلغ نهایی» نیست؛ فقط این نوع سند با این عملیات قابل اصلاح است.');
    }
    final accounts = await _db.getAccounts();
    final accountsById = {for (final a in accounts) a.id!: a};
    if (original.lines.any((l) => _db.isCashOrBankById(l.accountId, accountsById))) {
      throw Exception('این سند «اصلاح مبلغ نهایی» نیست؛ فقط این نوع سند با این عملیات قابل اصلاح است.');
    }
    final arAccount = await _db.getReceivableAccount();
    final arLine = arAccount == null
        ? null
        : original.lines.where((l) => l.accountId == arAccount.id).firstOrNull;
    if (arLine == null) {
      throw Exception('این سند «اصلاح مبلغ نهایی» نیست؛ فقط این نوع سند با این عملیات قابل اصلاح است.');
    }
    final signedAmount = arLine.debit > 0 ? arLine.debit.toDouble() : -arLine.credit.toDouble();

    final projectId = arLine.projectId;
    final marker = '(سند اصلی #$entryId)';
    if (projectId != null) {
      final existing = await _db.getJournalEntries(projectId: projectId);
      if (existing.any((e) => e.description?.contains(marker) == true)) {
        throw Exception('این سند قبلاً اصلاح شده است.');
      }
    }

    final reversalLines = original.lines
        .map((l) => JournalLineModel(
              accountId: l.accountId,
              debit: l.credit,
              credit: l.debit,
              projectId: l.projectId,
              counterpartyId: l.counterpartyId,
              description: l.description,
            ))
        .toList();
    // مثل reverseProjectDiscount: سند برگشت و رویداد قیمتِ خنثی‌کننده در یک
    // تراکنش ثبت می‌شوند.
    final db = await _db.database;
    return db.transaction((txn) async {
      final newEntryId = await _db.insertJournalEntry(
          JournalEntryModel(
            date: todayJalaliString(),
            description: 'اصلاح: برگشت سند اصلاح مبلغ نهایی اشتباه $marker',
            createdAt: todayJalaliString(),
            source: kJournalSourceSystem,
            lines: reversalLines,
          ),
          txn);
      if (projectId != null) {
        await _db.addProjectPriceEvent(
          projectId: projectId,
          type: kPriceEventFinalAdjustment,
          amount: -signedAmount,
          reason: 'برگشت اصلاح مبلغ نهایی اشتباه $marker',
          date: todayJalaliString(),
          executor: txn,
        );
      }
      return newEntryId;
    });
  }

  /// ویرایش مستقیم مبلغ/تاریخ/دلیل یک سند «تخفیف» موجود - بدون ساختن سند
  /// جدید؛ خودِ همان سند در جای خودش اصلاح می‌شود (طبق درخواست صریح کاربر
  /// که برگشت Append-Only را برای «ویرایش» کافی ندانست، حتی برای تخفیف/
  /// اصلاح مبلغ نهایی، نه فقط دریافت وجه).
  ///
  /// چون project_price_events هیچ کلید خارجی به سند مرتبطش ندارد (رجوع
  /// به توضیح reverseProjectDiscount)، ردیف رویداد قیمتِ اصلی دست‌نخورده
  /// می‌ماند - فقط یک رویداد «دلتا» (تفاوت مبلغ جدید و قدیم) اضافه می‌شود تا
  /// جمع کل («تخفیف کل») درست بماند، بدون نیاز به یافتن/ویرایش آن ردیف.
  /// این رویداد دلتا در «تاریخچه تغییرات مبلغ» به‌عنوان یک ردیف اصلاحی
  /// جداگانه دیده می‌شود (نه ادغام‌شده با ردیف اصلی)، اما خودِ سند حسابداری
  /// (که هدف اصلی این ویرایش است) واقعاً و فقط در یک نسخه، با عدد درست،
  /// در «اسناد این پروژه» دیده می‌شود.
  Future<void> updateProjectDiscount({
    required int entryId,
    required double amount,
    required String date,
    String? reason,
  }) async {
    if (amount <= 0) throw Exception('مبلغ تخفیف باید بزرگ‌تر از صفر باشد.');
    final original = await _db.getJournalEntry(entryId);
    if (original == null) throw Exception('سند یافت نشد.');
    if (!original.isSystemGenerated) {
      throw Exception('این سند دستی است؛ می‌توانید مستقیماً از صفحه سند حذف و دوباره ثبتش کنید.');
    }
    final discountAccount = await _db.getServiceDiscountAccount();
    if (discountAccount == null) throw Exception('حساب کنترلی «تخفیف» یافت نشد.');
    final discountLines =
        original.lines.where((l) => l.accountId == discountAccount.id && l.debit > 0).toList();
    if (discountLines.isEmpty) {
      throw Exception('این سند «تخفیف» نیست؛ فقط این نوع سند قابل ویرایش مستقیم است.');
    }
    final arAccount = await _db.getReceivableAccount();
    if (arAccount == null) throw Exception('حساب کنترلی «دریافتنی» یافت نشد.');
    final discountLine = discountLines.first;
    final oldAmount = discountLine.debit.toDouble();
    final projectId = discountLine.projectId;
    final counterpartyId = discountLine.counterpartyId;

    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.delete('journal_lines', where: 'entryId = ?', whereArgs: [entryId]);
      final newDescription = reason?.isNotEmpty == true ? 'تخفیف: $reason' : 'تخفیف نهایی پروژه';
      final newEntry = JournalEntryModel(
        id: entryId,
        date: date,
        description: newDescription,
        createdAt: original.createdAt,
        source: kJournalSourceSystem,
        lines: [
          JournalLineModel(
              accountId: discountAccount.id!,
              debit: amount.round(),
              projectId: projectId,
              counterpartyId: counterpartyId),
          JournalLineModel(
              accountId: arAccount.id!,
              credit: amount.round(),
              projectId: projectId,
              counterpartyId: counterpartyId),
        ],
      );
      await _db.validateJournalEntry(newEntry, txn);
      await txn.update('journal_entries', {'date': date, 'description': newDescription},
          where: 'id = ?', whereArgs: [entryId]);
      for (final line in newEntry.lines) {
        final map = line.toMap()
          ..remove('id')
          ..['entryId'] = entryId;
        await txn.insert('journal_lines', map);
      }
      if (projectId != null && amount != oldAmount) {
        await _db.addProjectPriceEvent(
          projectId: projectId,
          type: kPriceEventDiscount,
          amount: oldAmount - amount,
          reason: 'اصلاح مبلغ تخفیف (سند #$entryId)',
          date: date,
          executor: txn,
        );
      }
    });
  }

  /// ویرایش مستقیم مبلغ/تاریخ/دلیل یک سند «اصلاح مبلغ نهایی» موجود -
  /// بدون ساختن سند جدید؛ رجوع به توضیح updateProjectDiscount برای دلیل
  /// رویداد قیمتِ «دلتا». تشخیص این سند دقیقاً همان دو شرط
  /// reverseFinalAdjustment را دارد (پیشوند ثابت توضیح + نبود سطر نقد/بانک).
  Future<void> updateFinalAdjustment({
    required int entryId,
    required double amount, // علامت‌دار: مثبت=افزایش درآمد، منفی=کاهش
    required String date,
    String? reason,
  }) async {
    if (amount == 0) throw Exception('مقدار اصلاح نمی‌تواند صفر باشد.');
    final original = await _db.getJournalEntry(entryId);
    if (original == null) throw Exception('سند یافت نشد.');
    if (!original.isSystemGenerated) {
      throw Exception('این سند دستی است؛ می‌توانید مستقیماً از صفحه سند حذف و دوباره ثبتش کنید.');
    }
    if (original.description == null || !original.description!.startsWith('اصلاح مبلغ نهایی')) {
      throw Exception('این سند «اصلاح مبلغ نهایی» نیست؛ فقط این نوع سند قابل ویرایش مستقیم است.');
    }
    final accounts = await _db.getAccounts();
    final accountsById = {for (final a in accounts) a.id!: a};
    if (original.lines.any((l) => _db.isCashOrBankById(l.accountId, accountsById))) {
      throw Exception('این سند «اصلاح مبلغ نهایی» نیست؛ فقط این نوع سند قابل ویرایش مستقیم است.');
    }
    final arAccount = await _db.getReceivableAccount();
    final revenueAccount = await _db.getProjectRevenueAccount();
    if (arAccount == null || revenueAccount == null) {
      throw Exception('حساب‌های کنترلی موردنیاز یافت نشدند.');
    }
    final arLine = original.lines.where((l) => l.accountId == arAccount.id).firstOrNull;
    if (arLine == null) {
      throw Exception('این سند «اصلاح مبلغ نهایی» نیست؛ فقط این نوع سند قابل ویرایش مستقیم است.');
    }
    final oldSignedAmount = arLine.debit > 0 ? arLine.debit.toDouble() : -arLine.credit.toDouble();
    final projectId = arLine.projectId;
    final counterpartyId = arLine.counterpartyId;
    final magnitude = amount.abs().round();

    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.delete('journal_lines', where: 'entryId = ?', whereArgs: [entryId]);
      final newDescription =
          reason?.isNotEmpty == true ? 'اصلاح مبلغ نهایی: $reason' : 'اصلاح مبلغ نهایی پروژه';
      final newEntry = JournalEntryModel(
        id: entryId,
        date: date,
        description: newDescription,
        createdAt: original.createdAt,
        source: kJournalSourceSystem,
        lines: amount > 0
            ? [
                JournalLineModel(
                    accountId: arAccount.id!,
                    debit: magnitude,
                    projectId: projectId,
                    counterpartyId: counterpartyId),
                JournalLineModel(
                    accountId: revenueAccount.id!,
                    credit: magnitude,
                    projectId: projectId,
                    counterpartyId: counterpartyId),
              ]
            : [
                JournalLineModel(
                    accountId: revenueAccount.id!,
                    debit: magnitude,
                    projectId: projectId,
                    counterpartyId: counterpartyId),
                JournalLineModel(
                    accountId: arAccount.id!,
                    credit: magnitude,
                    projectId: projectId,
                    counterpartyId: counterpartyId),
              ],
      );
      await _db.validateJournalEntry(newEntry, txn);
      await txn.update('journal_entries', {'date': date, 'description': newDescription},
          where: 'id = ?', whereArgs: [entryId]);
      for (final line in newEntry.lines) {
        final map = line.toMap()
          ..remove('id')
          ..['entryId'] = entryId;
        await txn.insert('journal_lines', map);
      }
      if (projectId != null && amount != oldSignedAmount) {
        await _db.addProjectPriceEvent(
          projectId: projectId,
          type: kPriceEventFinalAdjustment,
          amount: amount - oldSignedAmount,
          reason: 'اصلاح مقدار اصلاح مبلغ نهایی (سند #$entryId)',
          date: date,
          executor: txn,
        );
      }
    });
  }
}
