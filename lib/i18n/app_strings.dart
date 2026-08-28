// PATCH_S123_I18N: the app shipped Arabic-only. This is the string table
// behind every localized surface (splash, welcome, settings, the whole
// mushaf reader, the studio's chrome and the watermark controls).
//
// Deliberately a plain Dart map rather than gen_l10n/.arb: it needs no code
// generation step in a repo whose CI runs `flutter build` directly, it keeps
// all five languages for a phrase on ONE line so a translation can never
// silently drift from its siblings, and it costs one map lookup per string.
//
// Every value list is ordered exactly like [AppLang.values]. The test in
// test/i18n_test.dart fails the build if any row is the wrong length, so a
// half-translated key can't ship.

/// Interface languages. Arabic stays the default and the app's first
/// language; the rest are the largest Quran-reading audiences.
enum AppLang { ar, en, fr, id, ur }

/// Languages written right-to-left — drives the app's [Directionality].
bool isRtlLang(AppLang l) => l == AppLang.ar || l == AppLang.ur;

/// The name of each language, written in that language (never translated —
/// a language picker you can't read is useless).
const Map<AppLang, String> kLangNames = {
  AppLang.ar: 'العربية',
  AppLang.en: 'English',
  AppLang.fr: 'Français',
  AppLang.id: 'Bahasa Indonesia',
  AppLang.ur: 'اردو',
};

/// BCP-47 tag, used for [Locale] and for number formatting decisions.
const Map<AppLang, String> kLangCodes = {
  AppLang.ar: 'ar',
  AppLang.en: 'en',
  AppLang.fr: 'fr',
  AppLang.id: 'id',
  AppLang.ur: 'ur',
};

class AppStrings {
  final AppLang lang;
  const AppStrings(this.lang);

  /// Looks up [key]. An unknown key returns the key itself rather than
  /// throwing — a missing string should be a visible typo in the UI, never
  /// a crash in a user's hands.
  String t(String key) {
    final row = _table[key];
    if (row == null) return key;
    return row[lang.index];
  }

  /// [t] with `{}` placeholders filled left to right.
  String f(String key, List<Object> args) {
    var s = t(key);
    for (final a in args) {
      s = s.replaceFirst('{}', '$a');
    }
    return s;
  }
}

// Order of every row: [ar, en, fr, id, ur]
const Map<String, List<String>> _table = {
  // ---- app identity ----
  'app.name': [
    'استوديو الآيات',
    'Ayat Studio',
    'Ayat Studio',
    'Ayat Studio',
    'آیات اسٹوڈیو',
  ],
  // PATCH_S129_QURAN_CAPTION_PARITY
  'export.chapters': [
    'فصول يوتيوب',
    'YouTube chapters',
    'Chapitres YouTube',
    'Bab YouTube',
    'یوٹیوب ابواب',
  ],
  'export.chapters.hint': [
    'ملف نصي بأوقات كل آية — الصقه في وصف فيديو يوتيوب',
    'A text file of every ayah timestamp — paste into a YouTube description',
    'Fichier texte des horodatages — à coller dans la description YouTube',
    'File teks stempel waktu setiap ayat — tempel di deskripsi YouTube',
    'ہر آیت کے وقت کی ٹیکسٹ فائل — یوٹیوب تفصیل میں پیسٹ کریں',
  ],
  'project.name': [
    'اسم المشروع',
    'Project name',
    'Nom du projet',
    'Nama proyek',
    'پروجیکٹ کا نام',
  ],
  'project.reciter': [
    'اسم القارئ',
    'Reciter name',
    'Nom du récitateur',
    'Nama qari',
    'قاری کا نام',
  ],
  'style.translation.size': [
    'حجم الترجمة',
    'Translation size',
    'Taille de la traduction',
    'Ukuran terjemahan',
    'ترجمہ کا سائز',
  ],
  'style.translation.opacity': [
    'شفافية الترجمة',
    'Translation opacity',
    'Opacité de la traduction',
    'Opasitas terjemahan',
    'ترجمہ کی شفافیت',
  ],
  'app.eyebrow': [
    'تصميم مقاطع قرآنية',
    'Quranic video design',
    'Création de vidéos coraniques',
    'Desain video Al-Qur\'an',
    'قرآنی ویڈیو ڈیزائن',
  ],
  'app.tagline': [
    'حوّل أي فيديو إلى تصميم قرآني احترافي: الآية، ترجمة المعاني، والقارئ — كلها في مكان واحد.',
    'Turn any clip into a polished Quranic video: the ayah, its meaning, and the reciter — all in one place.',
    'Transformez n\'importe quelle vidéo en création coranique soignée : le verset, sa signification et le récitateur — tout au même endroit.',
    'Ubah video apa pun menjadi karya Al-Qur\'an yang rapi: ayat, maknanya, dan qari — semuanya dalam satu tempat.',
    'کسی بھی ویڈیو کو بہترین قرآنی ڈیزائن میں بدلیں: آیت، ترجمہ اور قاری — سب ایک جگہ۔',
  ],
  'app.feature.ai': [
    'تعرّف تلقائي بالذكاء الاصطناعي على الآية وترجمتها',
    'AI detects the recited ayah and its translation',
    'L\'IA reconnaît le verset récité et sa traduction',
    'AI mengenali ayat yang dibaca beserta terjemahannya',
    'مصنوعی ذہانت آیت اور اس کا ترجمہ خود پہچانتی ہے',
  ],
  'app.feature.templates': [
    'خلفيات، كروم، وقوالب نصية جاهزة',
    'Backgrounds, chroma key, and ready-made text templates',
    'Arrière-plans, incrustation couleur et modèles de texte',
    'Latar, chroma key, dan template teks siap pakai',
    'پس منظر، کروما کی اور تیار ٹیکسٹ ٹیمپلیٹس',
  ],
  'app.feature.reciters': [
    'تلاوات قرّاء جاهزة مع معاينة صوتية',
    'A reciter library with audio preview',
    'Une bibliothèque de récitateurs avec aperçu audio',
    'Pustaka qari dengan pratinjau audio',
    'قاریوں کی لائبریری بمع آڈیو پیش نظارہ',
  ],
  'app.feature.mushaf': [
    'المصحف كاملاً بصفحاته وتفسيره وبحث في الآيات',
    'The full mushaf — real pages, tafsir, and ayah search',
    'Le mushaf complet — vraies pages, tafsir et recherche de versets',
    'Mushaf lengkap — halaman asli, tafsir, dan pencarian ayat',
    'مکمل مصحف — اصل صفحات، تفسیر اور آیت تلاش',
  ],
  'app.start': [
    'ابدأ التصميم',
    'Start designing',
    'Commencer',
    'Mulai mendesain',
    'ڈیزائن شروع کریں',
  ],
  'app.learnMore': [
    'معرفة المزيد عن التطبيق',
    'Learn more about the app',
    'En savoir plus sur l\'application',
    'Pelajari lebih lanjut tentang aplikasi',
    'ایپ کے بارے میں مزید جانیں',
  ],

  // ---- generic ----
  'common.close': ['إغلاق', 'Close', 'Fermer', 'Tutup', 'بند کریں'],
  'common.cancel': ['إلغاء', 'Cancel', 'Annuler', 'Batal', 'منسوخ'],
  'common.done': ['تم', 'Done', 'Terminé', 'Selesai', 'مکمل'],
  'common.retry': [
    'إعادة المحاولة',
    'Try again',
    'Réessayer',
    'Coba lagi',
    'دوبارہ کوشش',
  ],
  'common.loading': [
    'جارٍ التحميل…',
    'Loading…',
    'Chargement…',
    'Memuat…',
    'لوڈ ہو رہا ہے…',
  ],
  'common.search': ['بحث', 'Search', 'Rechercher', 'Cari', 'تلاش'],
  'common.copy': ['نسخ', 'Copy', 'Copier', 'Salin', 'کاپی'],
  'common.copied': [
    'تم النسخ',
    'Copied',
    'Copié',
    'Disalin',
    'کاپی ہو گیا',
  ],
  'common.share': ['مشاركة', 'Share', 'Partager', 'Bagikan', 'شیئر'],
  'common.on': ['مفعّل', 'On', 'Activé', 'Aktif', 'آن'],
  'common.off': ['معطّل', 'Off', 'Désactivé', 'Nonaktif', 'آف'],
  'common.settings': ['الإعدادات', 'Settings', 'Paramètres', 'Pengaturan', 'ترتیبات'],
// PATCH_S128_TEXT_EDITOR_PRO_SIMPLE_MODE_SELECTION_GUIDE_I18N: studio surfaces.
'studio.loaded': ['تم تحميل القرآن الكريم كاملاً (6236 آية)', 'The full Quran is loaded (6,236 ayat)', 'Le Coran complet est chargé (6 236 versets)', 'Al-Quran lengkap dimuat (6.236 ayat)', 'مکمل قرآن کریم لوڈ ہو گیا (6236 آیات)'],
'stage.hint': ['اختر آية، أو ارفع فيديو واستخدم التعرّف أو المزامنة التلقائية', 'Pick an ayah, or upload a video and use detection or auto-sync', 'Choisissez un verset, ou importez une vidéo avec détection ou synchro auto', 'Pilih ayat, atau unggah video dan gunakan deteksi atau sinkron otomatis', 'آیت منتخب کریں، یا ویڈیو اپ لوڈ کر کے شناخت یا آٹو سنک استعمال کریں'],
// PATCH_S133_STAGE_TEXT_SELECT_EDIT: tap-to-select + double-tap-to-edit dialog.
'stage.editText': ['تعديل النص الظاهر', 'Edit displayed text', 'Modifier le texte affiché', 'Edit teks yang ditampilkan', 'ظاہر ہونے والا متن ترمیم کریں'],
'stage.editSave': ['حفظ', 'Save', 'Enregistrer', 'Simpan', 'محفوظ کریں'],
'aspect.story916': ['قصة 9:16', 'Story 9:16', 'Story 9:16', 'Story 9:16', 'اسٹوری 9:16'],
'aspect.square11': ['مربع 1:1', 'Square 1:1', 'Carré 1:1', 'Persegi 1:1', 'مربع 1:1'],
'aspect.landscape169': ['عريض 16:9', 'Wide 16:9', 'Large 16:9', 'Lebar 16:9', 'وائیڈ 16:9'],
'aspect.portrait45': ['منشور 4:5', 'Post 4:5', 'Post 4:5', 'Pos 4:5', 'پوسٹ 4:5'],
'aspect.custom': ['مخصص', 'Custom', 'Personnalisé', 'Kustom', 'حسب ضرورت'],
'autosync.btn': ['مزامنة تلقائية: اكتب كل آية أثناء التلاوة', 'Auto-sync: writes each ayah as it is recited', 'Synchro auto : écrit chaque verset pendant la récitation', 'Sinkron otomatis: menulis tiap ayat saat dilantunkan', 'آٹو سنک: تلاوت کے دوران ہر آیت لکھتا ہے'],
'autosync.btnRescan': ['إعادة المزامنة التلقائية (تستبدل الرصد الحالي)', 'Re-run auto-sync (replaces the current detection)', 'Relancer la synchro auto (remplace la détection actuelle)', 'Jalankan ulang sinkron otomatis (menggantikan deteksi saat ini)', 'دوبارہ آٹو سنک (موجودہ شناخت کی جگہ)'],
'autosync.hint': ['تعمل جيدًا في نحو نصف الفيديو غالبًا؛ راجع/عدّل الباقي من بطاقة «مراجعة الآيات المرصودة» بعد التشغيل.', 'It usually works well on about half the video; review or fix the rest from the Review detected ayat card after playback.', 'Fonctionne bien sur environ la moitié de la vidéo ; corrigez le reste via la carte Réviser les versets détectés.', 'Biasanya baik pada sekitar setengah video; periksa atau perbaiki sisanya dari kartu Tinjau ayat terdeteksi.', 'عام طور پر آدھی ویڈیو پر اچھا کام کرتا ہے؛ باقی کو کارڈ رصد شدہ آیات کا جائزہ سے درست کریں۔'],
'upload.video': ['رفع فيديو أو تلاوة صوتية', 'Upload a video or an audio recitation', 'Importer une vidéo ou une récitation audio', 'Unggah video atau rekaman tilawah', 'ویڈیو یا صوتی تلاوت اپ لوڈ کریں'],
'upload.detect': ['تعرّف من صوت الفيديو المرفوع', 'Detect from the uploaded video audio', 'Détecter depuis le son de la vidéo importée', 'Deteksi dari audio video yang diunggah', 'اپ لوڈ کردہ ویڈیو کی آواز سے شناخت کریں'],
'review.card': ['مراجعة الآيات المرصودة', 'Review detected ayat', 'Réviser les versets détectés', 'Tinjau ayat terdeteksi', 'رصد شدہ آیات کا جائزہ'],
'export.btn': ['تصدير الفيديو', 'Export the video', 'Exporter la vidéo', 'Ekspor video', 'ویڈیو ایکسپورٹ کریں'],
'trim.label': ['قص المقطع (من — إلى)', 'Trim the clip (from — to)', 'Rogner le clip (de — à)', 'Potong klip (dari — sampai)', 'کلپ تراشیں (از — تا)'],
'chroma.enable': ['تفعيل إزالة الخلفية', 'Enable background removal', 'Activer la suppression du fond', 'Aktifkan hapus latar', 'بیک گراؤنڈ ہٹانا فعال کریں'],
'bg.customNote': ['تذكير: هذه الخلفية ستظهر خلف آيات القرآن — يُستحسن اختيار صور تليق بالمحتوى القرآني (زخارف، خطوط، تدرّجات، مناظر طبيعية مجرّدة)، وتجنّب صور الأشخاص أو أي مشهد لا يناسب تلاوة الآيات.', 'Reminder: this background appears behind Quran ayat — choose visuals that suit Quranic content (patterns, calligraphy, gradients, abstract nature), and avoid images of people or anything unfit for a recitation.', 'Rappel : ce fond apparaît derrière les versets — choisissez des visuels dignes du Coran (motifs, calligraphie, dégradés, nature abstraite) et évitez les personnes ou toute scène inappropriée.', 'Pengingat: latar ini tampil di belakang ayat Al-Quran — pilih visual yang pantas (ornamen, kaligrafi, gradasi, alam abstrak) dan hindari gambar orang atau hal yang tidak layak.', 'یاد دہانی: یہ پس منظر آیات کے پیچھے دکھے گا — قرآنی مواد کے مناسب تصاویر چنیں (نقوش، خطاطی، گریڈینٹ، مجرد مناظر) اور لوگوں یا نامناسب مناظر سے گریز کریں۔'],
'multi.range': ['نطاق آيات متعدد', 'Multiple-ayah range', 'Plage de plusieurs versets', 'Rentang beberapa ayat', 'متعدد آیات کا دائرہ'],
'partial.use': ['استخدام جزء من الآية فقط', 'Use part of the ayah only', 'Utiliser une partie du verset', 'Gunakan sebagian ayat saja', 'صرف آیت کا حصہ استعمال کریں'],
// PATCH_S128 guide keys (from former S127)
'settings.guide': ['دليل الاستخدام', 'User guide', 'Guide d\'utilisation', 'Panduan penggunaan', 'رہنمائی'],
'settings.guideOpen': ['افتح الدليل السريع', 'Open the quick guide', 'Ouvrir le guide rapide', 'Buka panduan cepat', 'فوری رہنمائی کھولیں'],
'settings.guideHint': ['كل تحكمات اللمس: السحب، القرصة، وتظليل الكلمات.', 'Every touch control: drag, pinch and word highlighting.', 'Toutes les commandes tactiles : glisser, pincer, surligner.', 'Semua kontrol sentuh: seret, cubit, sorot kata.', 'ہر ٹچ کنٹرول: کھینچنا، چٹکی، نمایاں کرنا۔'],
'guide.title': ['دليل الاستخدام السريع', 'Quick-start guide', 'Guide rapide', 'Panduan cepat', 'فوری رہنمائی'],
'guide.box': ['المربع الذهبي المتقطع يعني أن النص محدد وجاهز للتعديل.', 'The dashed gold box means the text is selected.', 'Le cadre doré pointillé : le texte est sélectionné.', 'Kotak emas putus-putus berarti teks terpilih.', 'سنہری خانہ متن کے منتخب ہونے کی علامت ہے۔'],
'guide.drag': ['اسحب النص لتحريكه داخل المعاينة.', 'Drag the text to move it on the preview.', 'Glissez le texte pour le déplacer.', 'Seret teks untuk memindahkannya.', 'متن کو کھینچ کر حرکت دیں۔'],
'guide.pinch': ['قرصة بإصبعين لتكبير النص أو تصغيره.', 'Pinch with two fingers to resize the text.', 'Pincez pour redimensionner le texte.', 'Cubit untuk mengubah ukuran teks.', 'چٹکی سے سائز بدلیں۔'],
'guide.wordTap': ['اضغط أي كلمة لتظليلها بالأحمر، ومجددًا للإزالة.', 'Tap any word to highlight it red; tap again to undo.', 'Touchez un mot pour le surligner en rouge.', 'Ketuk kata untuk menyorotnya merah.', 'لفظ پر ٹچ کر کے سرخ کریں۔'],
'guide.timeline': ['اسحب الحد بين آيتين لتعديل التوقيتين معًا.', 'Drag the edge between two ayat to retune both.', 'Glissez la bordure entre deux versets.', 'Seret batas dua ayat untuk mengatur waktu.', 'دو آیات کی حد کھینچیں۔'],


  // ---- mushaf reader ----
  'mushaf.title': ['المصحف', 'Mushaf', 'Mushaf', 'Mushaf', 'مصحف'],
  'mushaf.open': [
    'افتح المصحف الشريف',
    'Open the Holy Quran',
    'Ouvrir le Saint Coran',
    'Buka Al-Qur\'an',
    'قرآن مجید کھولیں',
  ],
  'mushaf.openHint': [
    'صفحات المصحف كاملة، بحث في الآيات، وتفسير لكل آية',
    'Real mushaf pages, ayah search, and tafsir for every ayah',
    'Vraies pages du mushaf, recherche de versets et tafsir',
    'Halaman mushaf asli, pencarian ayat, dan tafsir',
    'اصل صفحات، آیت تلاش اور ہر آیت کی تفسیر',
  ],
  'mushaf.surahs': ['السور', 'Surahs', 'Sourates', 'Surah', 'سورتیں'],
  'mushaf.read': ['القراءة', 'Read', 'Lecture', 'Baca', 'قراءت'],
  'mushaf.tafsir': ['التفسير', 'Tafsir', 'Tafsir', 'Tafsir', 'تفسیر'],
  'mushaf.page': ['صفحة', 'Page', 'Page', 'Halaman', 'صفحہ'],
  'mushaf.pageOf': [
    'صفحة {} من {}',
    'Page {} of {}',
    'Page {} sur {}',
    'Halaman {} dari {}',
    'صفحہ {} از {}',
  ],
  'mushaf.juz': ['جزء', 'Juz', 'Juz', 'Juz', 'پارہ'],
  'mushaf.ayahCount': [
    '{} آية',
    '{} ayat',
    '{} versets',
    '{} ayat',
    '{} آیات',
  ],
  'mushaf.meccan': ['مكية', 'Meccan', 'Mecquoise', 'Makkiyah', 'مکی'],
  'mushaf.medinan': ['مدنية', 'Medinan', 'Médinoise', 'Madaniyah', 'مدنی'],
  'mushaf.goToPage': [
    'الانتقال إلى صفحة',
    'Go to page',
    'Aller à la page',
    'Ke halaman',
    'صفحہ پر جائیں',
  ],
  'mushaf.continueReading': [
    'متابعة القراءة',
    'Continue reading',
    'Reprendre la lecture',
    'Lanjutkan membaca',
    'پڑھنا جاری رکھیں',
  ],
  'mushaf.viewMode': [
    'طريقة العرض',
    'View mode',
    'Mode d\'affichage',
    'Mode tampilan',
    'نمائش انداز',
  ],
  'mushaf.viewPage': [
    'صفحات المصحف',
    'Mushaf pages',
    'Pages du mushaf',
    'Halaman mushaf',
    'مصحف صفحات',
  ],
  'mushaf.viewSurah': [
    'سورة كاملة',
    'Whole surah',
    'Sourate entière',
    'Satu surah penuh',
    'مکمل سورت',
  ],
  'mushaf.searchPlaceholder': [
    'اكتب آية أو جزءًا منها…',
    'Type an ayah or part of one…',
    'Saisissez un verset ou une partie…',
    'Ketik ayat atau sebagiannya…',
    'آیت یا اس کا حصہ لکھیں…',
  ],
  'mushaf.searchSurahPlaceholder': [
    'ابحث عن سورة…',
    'Search for a surah…',
    'Rechercher une sourate…',
    'Cari surah…',
    'سورت تلاش کریں…',
  ],
  'mushaf.searchNoResults': [
    'لا توجد نتائج مطابقة',
    'No matching results',
    'Aucun résultat',
    'Tidak ada hasil',
    'کوئی نتیجہ نہیں',
  ],
  'mushaf.searchHint': [
    'اكتب بأي رسم — البحث يتجاهل التشكيل وصور الهمزة، ويجد الآية حتى لو كتبتَ جزءًا منها فقط.',
    'Type it any way you like — the search ignores diacritics and hamza spelling, and finds an ayah from a fragment.',
    'Écrivez comme vous voulez — la recherche ignore les diacritiques et l\'orthographe du hamza, et trouve un verset à partir d\'un fragment.',
    'Ketik dengan cara apa pun — pencarian mengabaikan harakat dan penulisan hamzah, serta menemukan ayat dari potongan.',
    'کسی بھی طرح لکھیں — تلاش اعراب اور ہمزہ کے رسم کو نظرانداز کرتی ہے۔',
  ],
  'mushaf.searchResults': [
    '{} نتيجة',
    '{} results',
    '{} résultats',
    '{} hasil',
    '{} نتائج',
  ],
  'mushaf.sajda': [
    'سجدة تلاوة',
    'Prostration',
    'Prosternation',
    'Sujud tilawah',
    'سجدۂ تلاوت',
  ],
  'mushaf.fontSize': [
    'حجم الخط',
    'Text size',
    'Taille du texte',
    'Ukuran teks',
    'متن کا سائز',
  ],
  'mushaf.lightMode': [
    'الوضع الفاتح للمصحف',
    'Light mode for the reader',
    'Mode clair pour la lecture',
    'Mode terang untuk pembaca',
    'قراءت کے لیے روشن موڈ',
  ],
  'mushaf.lightModeHint': [
    'يخصّ شاشة المصحف وحدها — يبقى الاستوديو داكنًا كما هو.',
    'Applies to the Quran reader only — the studio stays dark.',
    'S\'applique uniquement au lecteur — le studio reste sombre.',
    'Hanya untuk pembaca Al-Qur\'an — studio tetap gelap.',
    'صرف قرآن ریڈر کے لیے — اسٹوڈیو تاریک ہی رہے گا۔',
  ],
  'mushaf.showTranslation': [
    'إظهار ترجمة المعاني',
    'Show the translation',
    'Afficher la traduction',
    'Tampilkan terjemahan',
    'ترجمہ دکھائیں',
  ],
  'mushaf.useInStudio': [
    'استخدام هذه الآية في التصميم',
    'Use this ayah in the studio',
    'Utiliser ce verset dans le studio',
    'Gunakan ayat ini di studio',
    'یہ آیت اسٹوڈیو میں استعمال کریں',
  ],
  'mushaf.ayahAdded': [
    'تم اختيار الآية في الاستوديو',
    'Ayah loaded into the studio',
    'Verset chargé dans le studio',
    'Ayat dimuat ke studio',
    'آیت اسٹوڈیو میں لے لی گئی',
  ],
  'mushaf.tafsirEdition': [
    'اختيار التفسير',
    'Tafsir edition',
    'Édition du tafsir',
    'Edisi tafsir',
    'تفسیر کا انتخاب',
  ],
  'mushaf.tafsirPick': [
    'اختر آية لعرض تفسيرها',
    'Pick an ayah to read its tafsir',
    'Choisissez un verset pour lire son tafsir',
    'Pilih ayat untuk membaca tafsirnya',
    'تفسیر پڑھنے کے لیے آیت منتخب کریں',
  ],
  'mushaf.tafsirLoading': [
    'جارٍ تحميل التفسير…',
    'Loading the tafsir…',
    'Chargement du tafsir…',
    'Memuat tafsir…',
    'تفسیر لوڈ ہو رہی ہے…',
  ],
  'mushaf.tafsirOffline': [
    'يتطلّب التفسير اتصالاً بالإنترنت أول مرة فقط — بعدها يُحفظ على الجهاز ويُقرأ بدون إنترنت.',
    'The tafsir needs a connection the first time only — after that it is cached on the device and reads offline.',
    'Le tafsir nécessite une connexion la première fois seulement — ensuite il est mis en cache et lisible hors ligne.',
    'Tafsir butuh koneksi hanya pertama kali — setelah itu disimpan di perangkat dan bisa dibaca offline.',
    'تفسیر کو صرف پہلی بار انٹرنیٹ چاہیے — پھر یہ ڈیوائس پر محفوظ ہو جاتی ہے۔',
  ],
  'mushaf.tafsirFailed': [
    'تعذّر تحميل التفسير',
    'Could not load the tafsir',
    'Impossible de charger le tafsir',
    'Gagal memuat tafsir',
    'تفسیر لوڈ نہیں ہو سکی',
  ],
  'mushaf.tafsirCached': [
    'محفوظ على الجهاز',
    'Saved on this device',
    'Enregistré sur cet appareil',
    'Tersimpan di perangkat ini',
    'اس ڈیوائس پر محفوظ',
  ],
  'mushaf.jumpToSurah': [
    'الذهاب إلى السورة',
    'Jump to surah',
    'Aller à la sourate',
    'Ke surah',
    'سورت پر جائیں',
  ],
  'mushaf.nextPage': [
    'الصفحة التالية',
    'Next page',
    'Page suivante',
    'Halaman berikutnya',
    'اگلا صفحہ',
  ],
  'mushaf.prevPage': [
    'الصفحة السابقة',
    'Previous page',
    'Page précédente',
    'Halaman sebelumnya',
    'پچھلا صفحہ',
  ],
  'mushaf.nextSurah': [
    'السورة التالية',
    'Next surah',
    'Sourate suivante',
    'Surah berikutnya',
    'اگلی سورت',
  ],
  'mushaf.prevSurah': [
    'السورة السابقة',
    'Previous surah',
    'Sourate précédente',
    'Surah sebelumnya',
    'پچھلی سورت',
  ],
  'mushaf.loadFailed': [
    'تعذّر تحميل نص هذه السورة',
    'Could not load this surah\'s text',
    'Impossible de charger le texte de cette sourate',
    'Gagal memuat teks surah ini',
    'اس سورت کا متن لوڈ نہیں ہو سکا',
  ],

  // ---- settings ----
  'settings.title': ['الإعدادات', 'Settings', 'Paramètres', 'Pengaturan', 'ترتیبات'],
  'settings.interface': [
    'الواجهة',
    'Interface',
    'Interface',
    'Antarmuka',
    'انٹرفیس',
  ],
  'settings.language': [
    'لغة التطبيق',
    'App language',
    'Langue de l\'application',
    'Bahasa aplikasi',
    'ایپ کی زبان',
  ],
  'settings.animations': [
    'حركات الواجهة',
    'Interface animations',
    'Animations de l\'interface',
    'Animasi antarmuka',
    'انٹرفیس اینیمیشنز',
  ],
  'settings.animationsHint': [
    'أطفئها لواجهة فورية بلا حركة — أخفّ على الأجهزة القديمة وأهدأ للعين.',
    'Turn them off for an instant, motion-free interface — lighter on older phones and calmer to use.',
    'Désactivez-les pour une interface instantanée sans mouvement — plus légère sur les anciens téléphones.',
    'Matikan untuk antarmuka tanpa gerakan — lebih ringan di ponsel lama.',
    'پرانے فونز کے لیے اینیمیشن بند کریں — تیز اور پرسکون۔',
  ],
  'settings.classicTabs': [
    'شريط التبويبات القديم (8 تبويبات)',
    'Classic tab layout (8 tabs)',
    'Disposition classique (8 onglets)',
    'Tata letak tab klasik (8 tab)',
    'کلاسک ٹیب لے آؤٹ (8 ٹیبز)',
  ],
  'settings.classicTabsHint': [
    'يستبدل التبويبات الخمس المجمّعة بشبكة الثماني تبويبات الأصلية.',
    'Swaps the 5 grouped tabs for the original 8-tab grid.',
    'Remplace les 5 onglets groupés par la grille originale de 8 onglets.',
    'Mengganti 5 tab yang dikelompokkan dengan grid 8 tab asli.',
    '5 گروپ شدہ ٹیبز کو اصل 8 ٹیب گرڈ سے بدل دیتا ہے۔',
  ],
  'settings.quran': [
    'المصحف',
    'Quran reader',
    'Lecteur du Coran',
    'Pembaca Al-Qur\'an',
    'قرآن ریڈر',
  ],
  'settings.about': ['حول', 'About', 'À propos', 'Tentang', 'تعارف'],
  'settings.version': ['الإصدار', 'Version', 'Version', 'Versi', 'ورژن'],
  'settings.privacy': [
    'سياسة الخصوصية',
    'Privacy policy',
    'Politique de confidentialité',
    'Kebijakan privasi',
    'رازداری کی پالیسی',
  ],
  'settings.languageNote': [
    'تتغيّر الواجهة فورًا. نص القرآن يبقى بالعربية دائمًا.',
    'The interface changes instantly. The Quran text itself always stays in Arabic.',
    'L\'interface change instantanément. Le texte du Coran reste toujours en arabe.',
    'Antarmuka berubah seketika. Teks Al-Qur\'an tetap dalam bahasa Arab.',
    'انٹرفیس فوراً بدل جاتا ہے۔ قرآن کا متن ہمیشہ عربی رہے گا۔',
  ],

  // ---- studio chrome ----
  'studio.tab.ayah': ['الآية', 'Ayah', 'Verset', 'Ayat', 'آیت'],
  'studio.tab.backgrounds': ['خلفيات', 'Backgrounds', 'Fonds', 'Latar', 'پس منظر'],
  'studio.tab.effects': ['تأثيرات', 'Effects', 'Effets', 'Efek', 'ایفیکٹس'],
  'studio.tab.chroma': ['كروم', 'Chroma', 'Chroma', 'Chroma', 'کروما'],
  'studio.tab.reciters': ['قرّاء', 'Reciters', 'Récitateurs', 'Qari', 'قاری'],
  'studio.tab.templates': ['قوالب', 'Templates', 'Modèles', 'Template', 'ٹیمپلیٹ'],
  'studio.tab.text': ['النص', 'Text', 'Texte', 'Teks', 'متن'],
  'studio.tab.export': ['تصدير', 'Export', 'Export', 'Ekspor', 'ایکسپورٹ'],
  'studio.group.ayat': ['الآيات', 'Ayat', 'Versets', 'Ayat', 'آیات'],
  'studio.group.shape': ['الشكل', 'Style', 'Style', 'Gaya', 'انداز'],
  'studio.group.media': ['الوسائط', 'Media', 'Média', 'Media', 'میڈیا'],
  'studio.group.more': ['المزيد', 'More', 'Plus', 'Lainnya', 'مزید'],
  'studio.undo': ['تراجع', 'Undo', 'Annuler', 'Urungkan', 'واپس'],
  'studio.redo': ['إعادة', 'Redo', 'Rétablir', 'Ulangi', 'دوبارہ'],
  'studio.info': [
    'معلومات عن التطبيق',
    'About this app',
    'À propos de l\'application',
    'Tentang aplikasi ini',
    'اس ایپ کے بارے میں',
  ],

  // ---- watermark ----
  'wm.section': [
    'العلامة المائية',
    'Watermark',
    'Filigrane',
    'Tanda air',
    'واٹر مارک',
  ],
  'wm.enable': [
    'إضافة علامة مائية',
    'Add a watermark',
    'Ajouter un filigrane',
    'Tambahkan tanda air',
    'واٹر مارک شامل کریں',
  ],
  'wm.hint': [
    'اختيارية تمامًا — التصدير بدونها هو الوضع الافتراضي، ولا يُضاف شيء إلى مقطعك ما لم تُفعّلها بنفسك.',
    'Completely optional — export carries no watermark by default, and nothing is added to your clip unless you switch this on yourself.',
    'Entièrement facultatif — l\'export ne comporte aucun filigrane par défaut, rien n\'est ajouté sans votre accord.',
    'Sepenuhnya opsional — ekspor tanpa tanda air secara bawaan, tidak ada yang ditambahkan kecuali Anda mengaktifkannya.',
    'مکمل اختیاری — بطور ڈیفالٹ کوئی واٹر مارک نہیں لگتا۔',
  ],
  'wm.text': [
    'نص العلامة',
    'Watermark text',
    'Texte du filigrane',
    'Teks tanda air',
    'واٹر مارک متن',
  ],
  'wm.position': ['الموضع', 'Position', 'Position', 'Posisi', 'مقام'],
  'wm.opacity': ['الشفافية', 'Opacity', 'Opacité', 'Opasitas', 'شفافیت'],
  'wm.size': ['الحجم', 'Size', 'Taille', 'Ukuran', 'سائز'],
  'wm.pos.topLeft': [
    'أعلى اليسار',
    'Top left',
    'En haut à gauche',
    'Kiri atas',
    'اوپر بائیں',
  ],
  'wm.pos.topRight': [
    'أعلى اليمين',
    'Top right',
    'En haut à droite',
    'Kanan atas',
    'اوپر دائیں',
  ],
  'wm.pos.bottomLeft': [
    'أسفل اليسار',
    'Bottom left',
    'En bas à gauche',
    'Kiri bawah',
    'نیچے بائیں',
  ],
  'wm.pos.bottomRight': [
    'أسفل اليمين',
    'Bottom right',
    'En bas à droite',
    'Kanan bawah',
    'نیچے دائیں',
  ],
  'wm.image': [
    'صورة/شعار',
    'Image or logo',
    'Image ou logo',
    'Gambar atau logo',
    'تصویر یا لوگو',
  ],
  'wm.pickImage': [
    'اختيار صورة',
    'Choose an image',
    'Choisir une image',
    'Pilih gambar',
    'تصویر منتخب کریں',
  ],
  'wm.clearImage': [
    'إزالة الصورة',
    'Remove the image',
    'Retirer l\'image',
    'Hapus gambar',
    'تصویر ہٹائیں',
  ],
  'audio.section': [
    'الصوت',
    'Audio',
    'Audio',
    'Audio',
    'آڈیو',
  ],
  'audio.originalUnder': [
    'صوت المقطع الأصلي تحت التلاوة',
    'Original clip audio under the recitation',
    'Son d\'origine sous la récitation',
    'Audio asli di bawah bacaan',
    'تلاوت کے نیچے اصل آواز',
  ],
  'audio.originalUnderHint': [
    'صفر يعني كتم صوت المقطع تمامًا كما كان سابقًا — ارفعه قليلًا إن أردت بقاء صوت الطبيعة أو المطر تحت التلاوة.',
    'Zero mutes the clip completely, as before — raise it a little to keep rain, wind or room tone under the reciter.',
    'Zéro coupe entièrement le son du clip, comme avant — montez-le un peu pour garder la pluie ou l\'ambiance sous le récitateur.',
    'Nol membisukan klip sepenuhnya, seperti sebelumnya — naikkan sedikit untuk mempertahankan suara alam di bawah bacaan.',
    'صفر کا مطلب کلپ کی آواز مکمل بند — تھوڑا بڑھائیں تو قدرتی آواز تلاوت کے نیچے رہے گی۔',
  ],
  'audio.muteAll': [
    'تصدير بدون صوت نهائيًا',
    'Export with no sound at all',
    'Exporter sans aucun son',
    'Ekspor tanpa suara sama sekali',
    'بالکل بغیر آواز ایکسپورٹ',
  ],

  // ---- editor extras ----
  'edit.speed': [
    'سرعة التشغيل',
    'Playback speed',
    'Vitesse de lecture',
    'Kecepatan pemutaran',
    'پلے بیک رفتار',
  ],
  'edit.speedHint': [
    'تُطبَّق على الفيديو والصوت معًا عند التصدير. تلاوة القارئ المضافة لا تتأثر.',
    'Applied to both video and audio at export. An added reciter track is left untouched.',
    'Appliquée à la vidéo et à l\'audio lors de l\'export. La piste du récitateur n\'est pas modifiée.',
    'Diterapkan pada video dan audio saat ekspor. Trek qari tidak terpengaruh.',
    'ایکسپورٹ پر ویڈیو اور آڈیو دونوں پر لاگو۔',
  ],
  'edit.muteOriginal': [
    'كتم صوت الفيديو الأصلي',
    'Mute the original video audio',
    'Couper le son de la vidéo d\'origine',
    'Bisukan audio video asli',
    'اصل ویڈیو کی آواز بند کریں',
  ],
  'edit.muteOriginalHint': [
    'مفيد عند إضافة تلاوة قارئ فوق مقطع فيه صوت محيط.',
    'Useful when laying a reciter track over a clip that has ambient sound.',
    'Utile lorsqu\'on superpose une récitation à une vidéo avec du son ambiant.',
    'Berguna saat menambahkan bacaan qari di atas klip bersuara.',
    'جب قاری کی تلاوت شامل کریں تو مفید ہے۔',
  ],
};

/// Exposed for the i18n test — every row must have one entry per [AppLang].
Map<String, List<String>> debugStringTable() => _table;
