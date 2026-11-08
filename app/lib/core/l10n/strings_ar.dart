/// User-facing Arabic strings (docs/SPEC.md §0.6). Moves to ARB (flutter gen-l10n) later.
abstract final class StringsAr {
  static const appTitle = 'تصحيح التلاوة';
  static const offlineBanner = 'وضع بدون إنترنت — تحليل مبسط';
  static const noAudioStored = 'لا يتم تسجيل أو حفظ أي صوت';
  static const continueAnyway = 'متابعة على أي حال';
  static const needsReview = 'مراجعة';

  // First launch
  static const welcomeTitle = 'مرحبًا بك';
  static const welcomeBody =
      'يستمع التطبيق إلى تلاوتك آيةً آية، ويتابع الكلمات أثناء القراءة، وينبّهك إلى ما قد يحتاج إلى تصحيح.';
  static const privacyBody =
      'يُعالَج الصوت في ذاكرة الهاتف لحظةً بلحظة ثم يُمحى فورًا. لا يُرسل أي شيء عبر الإنترنت.';
  static const reviewNotice =
      'هذه أداة مساعدة وليست بديلًا عن شيخ متقن. الكلمات البرتقالية تحتاج إلى مراجعتك.';
  static const allowMic = 'السماح باستخدام الميكروفون';
  static const micDenied =
      'لا يمكن الاستماع دون إذن الميكروفون. يمكنك منحه من إعدادات الهاتف.';

  // Selection
  static const riwaya = 'الرواية';
  static const surah = 'السورة';
  static const startAyah = 'آية البداية';
  static const start = 'ابدأ';
  static const lastUnlocked = 'آخر آية أُتمّت';

  // Recitation
  static const listen = 'ابدأ الاستماع';
  static const stopListening = 'إيقاف';
  static const listening = 'أستمع إليك…';
  static const preparing = 'جارٍ تجهيز محرك التحليل…';
  static const nextAyah = 'الآية التالية';
  static const retry = 'أعد القراءة';
  static const surahEnd = 'تمّت السورة. بارك الله فيك.';
  static const tapWordHint = 'اضغط على كلمة ملوّنة لمعرفة التفاصيل.';
  static const perSegmentMode = 'تظهر النتائج بعد كل وقفة على هذا الهاتف.';

  // Feedback
  static const expected = 'المتوقَّع';
  static const heard = 'ما سُمع';
  static const severityError = 'خطأ';
  static const severityReview = 'تحتاج إلى مراجعة';
  static const severityInfo = 'ملاحظة';
  static const noFindings = 'لا ملاحظات على هذه الكلمة.';

  // Settings
  static const settings = 'الإعدادات';
  static const reReciteMode = 'عند الخطأ أعد القراءة من';
  static const fromSegment = 'بداية المقطع';
  static const fromAyah = 'بداية الآية';
  static const maxAttempts = 'عدد المحاولات قبل «متابعة على أي حال»';
  static const liveMode = 'المتابعة المباشرة للكلمات';
  static const liveAuto = 'تلقائي حسب الهاتف';
  static const liveOn = 'مباشرة';
  static const liveOff = 'بعد كل وقفة';
  static const sources = 'المصادر والتراخيص';
  static const devSection = 'خيارات المطوّر (نسخة التطوير فقط)';
  static const devBlocking = 'اعتبار أخطاء الكلمات مانعة (للتجربة)';
  static const debugScreen = 'شاشة التشخيص وقياس السرعة';
}
