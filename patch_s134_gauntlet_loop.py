# patch_s134_gauntlet_loop.py
# Gauntlet Loop S134 — REAL pass, run against the actual extracted dump
# (ayat_studio_app_dump_20260828_181208.txt), not the pasted "S134 draft"
# text. That draft turned out to be mostly fiction against this dump:
#
#   - Its i18n anchors used the WRONG indentation ('stage.hint' is
#     0-indented in the real file, not 4-indented) and 3 of its 4 "verbatim"
#     literals (the long toast, the free-text field label) don't exist
#     anywhere in the dump -- fabricated. The real partial-ayah cluster is
#     7 distinct short literals, each grep-verified to occur exactly once.
#   - Its home_screen.dart mount indentation was 6 spaces; the real file
#     uses 8. Applying the draft as-is would have corrupted the file.
#   - Its reason for deferring word-level selection ("WordHitTester's API
#     has never been in any dump") is false against this dump:
#     lib/widgets/selection_box_overlay.dart already has a complete,
#     working WordHitTester.wordAt(text, style, maxWidth, local).
#
# That said, WordHitTester being real doesn't make raw on-stage tap-to-word
# wiring safe to guess. To call it correctly from the live stage you'd need
# to reverse the exact GestureDetector -> Transform.translate -> Align ->
# CustomPaint -> Container(margin, padding) chain in stage_preview.dart's
# _overlay() into the paragraph's own coordinate space -- precisely the
# kind of blind geometry math that broke S130/S131. So this pass delivers
# word-level selection through a *safe* real path instead: a tappable word
# row (state.redWordIndices) added to the *existing*, already-wired
# _openStageTextEditor dialog (double-tap on stage -> edit dialog). No
# coordinate math, no new gesture surface, same StatefulBuilder pattern
# home_screen.dart's own dialogs already use.
#
# Scope actually covered:
#   1. AI auto-segmentation wizard (new file lib/widgets/autoseg_wizard.dart)
#      -- unchanged in spirit from the draft, but every anchor it's wired
#      through in home_screen.dart is re-verified against the real file.
#   2. i18n: the REAL partial-ayah cluster (7 literals, not 4 fictional
#      ones) + all wizard keys, 5 languages each. None collide with the
#      table's existing keys (checked one by one).
#   3. Word-level selection: delivered via the stage-text edit dialog's new
#      tappable word row (real, safe) instead of raw WordHitTester canvas
#      hit-testing (would have been a guess).
#
# Run from the project root. Strict anchors abort; nothing here is soft.

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent
LEDGER = []


def _log(label, status):
    LEDGER.append((label, status))


def apply_literal(rel_path, old, new, label, skip_if=None):
    p = ROOT / rel_path
    if not p.exists():
        raise SystemExit(f"ERROR ({label}): {rel_path} not found under {ROOT}")
    text = p.read_text(encoding="utf-8")
    if skip_if and skip_if in text:
        _log(label, "SKIPPED-ALREADY")
        return
    n = text.count(old)
    if n != 1:
        raise SystemExit(f"ERROR ({label}): expected 1 match, found {n} in {rel_path} "
                          f"-- refusing to guess, no changes made.")
    p.write_text(text.replace(old, new, 1), encoding="utf-8")
    _log(label, "APPLIED")


def create_file(rel_path, content, label):
    p = ROOT / rel_path
    if p.exists():
        _log(label, "SKIPPED-ALREADY")
        return
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(content, encoding="utf-8")
    _log(label, "APPLIED")


def main():
    # ==================================================================
    # 1) lib/i18n/app_strings.dart — wizard keys + real partial-ayah keys,
    #    inserted before the verified 'stage.hint' row (0-indent, exact
    #    text copied from the real file -- the draft's 4-space-indented
    #    version does not exist here).
    # ==================================================================
    _STAGE_HINT = (
        "'stage.hint': ['اختر آية، أو ارفع فيديو واستخدم التعرّف أو المزامنة التلقائية', "
        "'Pick an ayah, or upload a video and use detection or auto-sync', "
        "'Choisissez un verset, ou importez une vidéo avec détection ou synchro auto', "
        "'Pilih ayat, atau unggah video dan gunakan deteksi atau sinkron otomatis', "
        "'آیت منتخب کریں، یا ویڈیو اپ لوڈ کر کے شناخت یا آٹو سنک استعمال کریں'],\n"
    )
    _NEW_KEYS = """'wizard.title': ['معالج التقسيم التلقائي', 'Auto-Segmentation Wizard', 'Assistant de segmentation auto', 'Wizard Segmentasi Otomatis', 'آٹو سیگمنٹیشن وزرڈ'],
'wizard.subtitle': ['إعداد موجّه لإضافة التوقيت تلقائيًا إلى الفيديو', 'Guided setup to automatically add subtitles to your video', 'Configuration guidée pour sous-titrer automatiquement la vidéo', 'Penyiapan terpandu untuk menambah takarir otomatis ke video', 'ویڈیو میں خودکار ذیلی عنوانات شامل کرنے کی رہنمائی'],
'wizard.audio': ['صوت مرصود', 'Audio detected', 'Audio détecté', 'Audio terdeteksi', 'آڈیو ملا'],
'wizard.noAudio': ['لا فيديو بعد — ارفعي فيديو أولًا', 'No video yet — upload one first', 'Pas de vidéo — importez-en une', 'Belum ada video — unggah dulu', 'ابھی ویڈیو نہیں — پہلے اپ لوڈ کریں'],
'wizard.version': ['إصدار الذكاء الاصطناعي', 'AI Version', "Version d'IA", 'Versi AI', 'AI ورژن'],
'wizard.runtime': ['بيئة التشغيل', 'Runtime', 'Runtime', 'Runtime', 'رن ٹائم'],
'wizard.models': ['النماذج', 'Models', 'Modèles', 'Model', 'ماڈلز'],
'wizard.segmentation': ['التقسيم', 'Segmentation', 'Segmentation', 'Segmentasi', 'سیگمنٹیشن'],
'wizard.run': ['تشغيل', 'Run', 'Lancer', 'Jalankan', 'چلائیں'],
'wizard.v1': ['Legacy V1', 'Legacy V1', 'Legacy V1', 'Legacy V1', 'Legacy V1'],
'wizard.v1Desc': ['مسار Whisper محلي فقط بأربعة أحجام نماذج', 'Local-only Whisper workflow, four legacy model sizes', 'Whisper local uniquement, 4 tailles de modèle', 'Whisper lokal saja dengan 4 ukuran model', 'صرف لوکل Whisper، چار ماڈل سائز'],
'wizard.v2': ['Multi-Aligner V2', 'Multi-Aligner V2', 'Multi-Aligner V2', 'Multi-Aligner V2', 'Multi-Aligner V2'],
'wizard.v2Desc': ['محاذاة أقوى بكثير من V1 — الخيار الموصى به', 'Much stronger alignment than V1 — recommended', 'Alignement bien meilleur que V1 — recommandé', 'Align jauh lebih kuat dari V1 — disarankan', 'V1 سے کہیں بہتر الائنمنٹ — تجویز کردہ'],
'wizard.recommended': ['موصى به', 'RECOMMENDED', 'RECOMMANDÉ', 'DISARANKAN', 'تجویز کردہ'],
'wizard.cloud': ['سحابي', 'Cloud runtime', 'Cloud', 'Cloud', 'کلاؤڈ'],
'wizard.cloudDesc': ['استخدام شبه غير محدود وعادة أسرع', 'Near-unlimited usage, usually faster', 'Usage quasi illimité, souvent plus rapide', 'Pemakaian hampir tak terbatas, biasanya lebih cepat', 'تقریباً لامحدود استعمال، عموماً تیز'],
'wizard.local': ['محلي', 'Local runtime', 'Local', 'Lokal', 'لوکل'],
'wizard.localDesc': ['يعمل على جهازك بنموذج Whisper المحلي', 'Runs on your device with local Whisper', 'S’exécute sur votre appareil (Whisper local)', 'Berjalan di perangkat Anda (Whisper lokal)', 'آپ کے آلے پر لوکل Whisper'],
'wizard.json': ['لصق من Hugging Face', 'Paste from Hugging Face', 'Coller depuis Hugging Face', 'Tempel dari Hugging Face', 'Hugging Face سے پیسٹ کریں'],
'wizard.jsonDesc': ['استيراد JSON من Quran Multi-Aligner مباشرة', 'Import Quran Multi-Aligner JSON directly', 'Importer le JSON Quran Multi-Aligner', 'Impor JSON Quran Multi-Aligner langsung', 'Quran Multi-Aligner JSON درآمد کریں'],
'wizard.jsonHint': ['الصقي محتوى JSON (قائمة مقاطع start/end/ref مثل 2:255)', 'Paste JSON (list of start/end/ref like 2:255)', 'Collez le JSON (liste start/end/ref ex. 2:255)', 'Tempel JSON (daftar start/end/ref mis. 2:255)', 'JSON پیسٹ کریں (start/end/ref مثلاً 2:255)'],
'wizard.jsonBad': ['JSON غير صالح — لم يُستورد شيء', 'Invalid JSON — nothing imported', 'JSON invalide — rien importé', 'JSON tidak valid — tidak diimpor', 'غلط JSON — کچھ درآمد نہیں ہوا'],
'wizard.base': ['Base', 'Base', 'Base', 'Base', 'Base'],
'wizard.baseDesc': ['توازن السرعة والجودة', 'Balanced speed and quality', 'Vitesse/qualité équilibrées', 'Seimbang cepat dan kualitas', 'رفتار اور معیار متوازن'],
'wizard.large': ['Large', 'Large', 'Large', 'Large', 'Large'],
'wizard.largeDesc': ['أكثر متانة للتلاوات غير الاستوديوهية', 'More robust to noisy, non-studio recitations', 'Plus robuste aux récitations bruitées', 'Lebih robust untuk rekaman non-studio', 'غیر اسٹوڈیو تلاوتوں کے لیے مضبوط'],
'wizard.device': ['الجهاز', 'DEVICE', 'APPAREIL', 'PERANGKAT', 'ڈیوائس'],
'wizard.presetSlow': ['مجوّد (بطيء)', 'Mujawwad (Slow)', 'Mujawwad (lent)', 'Mujawwad (lambat)', 'مجود (آہستہ)'],
'wizard.presetNormal': ['مرتل (عادي)', 'Murattal (Normal)', 'Murattal (normal)', 'Murattal (normal)', 'مرتل (درمیانہ)'],
'wizard.presetFast': ['حدر (سريع)', 'Hadr (Fast)', 'Hadr (rapide)', 'Hadr (cepat)', 'حدر (تیز)'],
'wizard.minSilence': ['أدنى صمت', 'Min Silence', 'Silence min', 'Senyap min', 'کم از کم خاموشی'],
'wizard.minSpeech': ['أدنى كلام', 'Min Speech', 'Parole min', 'Ucapan min', 'کم از کم کلام'],
'wizard.padding': ['تمديد', 'Padding', 'Padding', 'Padding', 'پیڈنگ'],
'wizard.review': ['مراجعة وتشغيل', 'Review and run', 'Vérifier et lancer', 'Tinjau dan jalankan', 'جائزہ اور اجرا'],
'wizard.reviewHint': ['أكدي الإعدادات قبل بدء التقسيم', 'Confirm your configuration before launching', 'Confirmez la configuration avant de lancer', 'Konfirmasi konfigurasi sebelum memulai', 'شروع کرنے سے پہلے ترتیب کی تصدیق کریں'],
'wizard.start': ['بدء التقسيم', 'Start segmentation', 'Lancer la segmentation', 'Mulai segmentasi', 'سیگمنٹیشن شروع کریں'],
'wizard.cloudNote': ['وضع السحاب يستخدم Quran Multi-Aligner v2 — في هذا البناء المحلي اختاري «محلي» أو «لصق JSON»', 'Cloud mode uses Quran Multi-Aligner v2 — in this local build pick Local or Paste JSON', 'Le mode cloud utilise Multi-Aligner v2 — dans ce build local choisissez Local ou JSON', 'Mode cloud memakai Multi-Aligner v2 — di build lokal ini pilih Local atau JSON', 'کلاؤڈ موڈ Multi-Aligner v2 استعمال کرتا ہے — اس لوکل بلڈ میں Local یا JSON چنیں'],
'wizard.localNote': ['حُفظ حجم النموذج — ابدئي الآن بالمزامنة التلقائية الموجودة', 'Model size saved — now start the existing auto-sync', 'Taille de modèle enregistrée — lancez la synchro auto', 'Ukuran model disimpan — mulai sinkron otomatis', 'ماڈل سائز محفوظ — اب موجودہ آٹو سنک شروع کریں'],
'wizard.imported': ['مقاطع مستوردة إلى الخط الزمني', 'segments imported into the timeline', 'segments importés dans la timeline', 'segmen diimpor ke timeline', 'ٹائم لائن میں درآمد شدہ حصے'],
'wizard.launch': ['فتح المعالج الموجّه', 'Open guided wizard', "Ouvrir l'assistant", 'Buka wizard terpandu', 'وزرڈ کھولیں'],
'partial.fromWord': ['من كلمة', 'From word', 'Du mot', 'Dari kata', 'از لفظ'],
'partial.toWord': ['إلى كلمة', 'To word', 'Au mot', 'Sampai kata', 'تا لفظ'],
'partial.useThis': ['استخدام هذا الجزء فقط', 'Use only this part', 'Utiliser cette partie seulement', 'Pakai bagian ini saja', 'صرف یہ حصہ استعمال کریں'],
'partial.full': ['الآية كاملة محددة بالفعل', 'Full ayah already selected', 'Verset entier déjà sélectionné', 'Ayat penuh sudah dipilih', 'پوری آیت پہلے سے منتخب'],
'partial.usedToast': ['تم استخدام جزء من الآية', 'Part of the ayah is now in use', 'Une partie du verset est utilisée', 'Sebagian ayat kini digunakan', 'آیت کا حصہ اب استعمال میں ہے'],
'partial.addedToast': ['أُضيف هذا الجزء إلى الخط الزمني ✓', 'Part added to the timeline ✓', 'Partie ajoutée à la timeline ✓', 'Bagian ditambahkan ke timeline ✓', 'حصہ ٹائم لائن میں شامل ✓'],
'partial.addToTimeline': ['إضافة هذا الجزء إلى الخط الزمني', 'Add this part to the timeline', 'Ajouter cette partie à la timeline', 'Tambahkan bagian ini ke timeline', 'یہ حصہ ٹائم لائن میں شامل کریں'],
'stage.toggleWords': ['تلوين كلمات بالأحمر', 'Highlight words in red', 'Surligner des mots en rouge', 'Tandai kata dengan merah', 'الفاظ کو سرخ کریں'],
"""
    apply_literal("lib/i18n/app_strings.dart",
                  _STAGE_HINT,
                  _NEW_KEYS + _STAGE_HINT,
                  "app_strings.dart: wizard + real partial-ayah keys (5 langs each)",
                  skip_if="'wizard.title'")

    # ==================================================================
    # 2) home_screen.dart — import the wizard file (verified import anchor,
    #    exact text incl. trailing comment).
    # ==================================================================
    apply_literal("lib/screens/home_screen.dart",
                  "import 'sequence_screen.dart'; // PATCH_S125_SEQUENCE\n",
                  "import 'sequence_screen.dart'; // PATCH_S125_SEQUENCE\n"
                  "import '../widgets/autoseg_wizard.dart'; // PATCH_S134_AUTOSEG_WIZARD\n",
                  "home_screen.dart: import autoseg_wizard.dart",
                  skip_if="import '../widgets/autoseg_wizard.dart';")

    # ==================================================================
    # 3) home_screen.dart — i18n the REAL partial-ayah cluster (7 literals,
    #    each verified to occur exactly once in the real file; the header
    #    reuses the i18n key 'partial.use' that already existed in the
    #    table but was never wired to this call site).
    # ==================================================================
    apply_literal("lib/screens/home_screen.dart",
                  "        _sectionHeader(\n"
                  "          'استخدام جزء من الآية فقط',\n",
                  "        _sectionHeader(\n"
                  "          _t('partial.use'), // PATCH_S134_AUTOSEG_WIZARD\n",
                  "home_screen.dart: partial-ayah header -> _t('partial.use')",
                  skip_if="_t('partial.use'), // PATCH_S134_AUTOSEG_WIZARD")

    apply_literal("lib/screens/home_screen.dart",
                  "                decoration: const InputDecoration(labelText: 'من كلمة'),",
                  "                decoration: InputDecoration(labelText: _t('partial.fromWord')), // PATCH_S134_AUTOSEG_WIZARD",
                  "home_screen.dart: 'from word' label -> _t()",
                  skip_if="_t('partial.fromWord')")

    apply_literal("lib/screens/home_screen.dart",
                  "                decoration: const InputDecoration(labelText: 'إلى كلمة'),",
                  "                decoration: InputDecoration(labelText: _t('partial.toWord')), // PATCH_S134_AUTOSEG_WIZARD",
                  "home_screen.dart: 'to word' label -> _t()",
                  skip_if="_t('partial.toWord')")

    apply_literal("lib/screens/home_screen.dart",
                  "                  _toast('تم استخدام جزء من الآية');",
                  "                  _toast(_t('partial.usedToast')); // PATCH_S134_AUTOSEG_WIZARD",
                  "home_screen.dart: partial-used toast -> _t()",
                  skip_if="_t('partial.usedToast')")

    apply_literal("lib/screens/home_screen.dart",
                  "          child: Text(isFull ? 'الآية كاملة محددة بالفعل' : 'استخدام هذا الجزء فقط'),",
                  "          child: Text(_t(isFull ? 'partial.full' : 'partial.useThis')), // PATCH_S134_AUTOSEG_WIZARD",
                  "home_screen.dart: partial button label -> _t()",
                  skip_if="_t(isFull ? 'partial.full'")

    apply_literal("lib/screens/home_screen.dart",
                  "            _toast('أُضيف هذا الجزء إلى الخط الزمني ✓');",
                  "            _toast(_t('partial.addedToast')); // PATCH_S134_AUTOSEG_WIZARD",
                  "home_screen.dart: partial-added toast -> _t()",
                  skip_if="_t('partial.addedToast')")

    apply_literal("lib/screens/home_screen.dart",
                  "          label: const Text('إضافة هذا الجزء إلى الخط الزمني'),",
                  "          label: Text(_t('partial.addToTimeline')), // PATCH_S134_AUTOSEG_WIZARD",
                  "home_screen.dart: 'add to timeline' label -> _t()",
                  skip_if="_t('partial.addToTimeline')")

    # ==================================================================
    # 4) home_screen.dart — launcher card in the الآيات panel, mounted
    #    right after _captionSection() (verified 8-space indent, matching
    #    the surrounding block -- NOT 6 spaces as the fictional draft had).
    # ==================================================================
    apply_literal("lib/screens/home_screen.dart",
                  "        _manualTimingSection(),\n"
                  "        _captionSection(),\n",
                  "        _manualTimingSection(),\n"
                  "        _captionSection(),\n"
                  "        _autoSegWizardCard(), // PATCH_S134_AUTOSEG_WIZARD\n",
                  "home_screen.dart: mount wizard launcher card",
                  skip_if="_autoSegWizardCard()")

    # ==================================================================
    # 5) home_screen.dart — card builder + opener, inserted right before
    #    the verified '  Widget _trimCard() {' anchor (2-space indent).
    # ==================================================================
    apply_literal("lib/screens/home_screen.dart",
                  "  Widget _trimCard() {",
                  "  // PATCH_S134_AUTOSEG_WIZARD: guided multi-step entry point (the\n"
                  "  // reference \"Auto-Segmentation Wizard\"). The wizard lives in its\n"
                  "  // own file; everything it changes flows through existing\n"
                  "  // StudioState APIs (addManualSegment / whisperModelSize), same as\n"
                  "  // every other dialog in this file.\n"
                  "  Widget _autoSegWizardCard() {\n"
                  "    return _sectionCard(Column(\n"
                  "      crossAxisAlignment: CrossAxisAlignment.stretch,\n"
                  "      children: [\n"
                  "        Row(children: [\n"
                  "          const Icon(Icons.auto_awesome_outlined,\n"
                  "              color: AyatColors.gold, size: 20),\n"
                  "          const SizedBox(width: 8),\n"
                  "          Expanded(\n"
                  "              child: Text(_t('wizard.title'),\n"
                  "                  style: Theme.of(context).textTheme.titleSmall)),\n"
                  "        ]),\n"
                  "        const SizedBox(height: 4),\n"
                  "        Text(_t('wizard.subtitle'),\n"
                  "            style: Theme.of(context)\n"
                  "                .textTheme\n"
                  "                .bodySmall\n"
                  "                ?.copyWith(color: AyatColors.goldDim)),\n"
                  "        const SizedBox(height: 10),\n"
                  "        OutlinedButton.icon(\n"
                  "          onPressed: _openAutoSegWizard,\n"
                  "          icon: const Icon(Icons.auto_fix_high, size: 18),\n"
                  "          label: Text(_t('wizard.launch')),\n"
                  "        ),\n"
                  "      ],\n"
                  "    ));\n"
                  "  }\n"
                  "\n"
                  "  // PATCH_S134_AUTOSEG_WIZARD: opens the wizard and surfaces its result\n"
                  "  // through the existing toast/timeline-card plumbing.\n"
                  "  Future<void> _openAutoSegWizard() async {\n"
                  "    final res = await showAutoSegWizard(\n"
                  "      context: context,\n"
                  "      state: state,\n"
                  "      audioPath: _video?.dataSource,\n"
                  "    );\n"
                  "    if (res == null) return;\n"
                  "    if (res.importedSegments > 0) {\n"
                  "      _revealTimelineCard();\n"
                  "      _toast('${_t('wizard.imported')}: ${res.importedSegments} \\u2713');\n"
                  "    } else if (res.tierApplied) {\n"
                  "      _toast(_t('wizard.localNote'));\n"
                  "    } else if (res.cloudChosen) {\n"
                  "      _toast(_t('wizard.cloudNote'));\n"
                  "    }\n"
                  "  }\n"
                  "\n"
                  "  Widget _trimCard() {",
                  "home_screen.dart: wizard card builder + opener",
                  skip_if="Widget _autoSegWizardCard()")

    # ==================================================================
    # 6) NEW FILE lib/widgets/autoseg_wizard.dart — the wizard itself.
    # ==================================================================
    create_file("lib/widgets/autoseg_wizard.dart", WIZARD_SRC,
                "lib/widgets/autoseg_wizard.dart: new 5-step wizard")

    # ==================================================================
    # 7) lib/widgets/stage_preview.dart — word-level selection, delivered
    #    SAFELY: a tappable word row (toggles the existing global
    #    state.redWordIndices, exactly like _redWordsSection's chips
    #    already do in home_screen.dart) added inside the *already-wired*
    #    _openStageTextEditor dialog. No raw WordHitTester canvas hit-
    #    testing against the live stage -- that would need reverse-
    #    engineering the GestureDetector -> Transform.translate -> Align
    #    -> CustomPaint -> Container(margin, padding) chain's exact pixel
    #    offsets, which isn't safely derivable without a running layout
    #    engine to confirm against (the exact failure mode the project's
    #    own S130/S131 history warns about). This still gives real,
    #    on-stage-flow word-level control -- via the dialog the user
    #    already opens by double-tapping the stage text -- without
    #    guessing geometry.
    # ==================================================================
    apply_literal("lib/widgets/stage_preview.dart",
                  "  Future<void> _openStageTextEditor(\n"
                  "      BuildContext context, String currentText) async {\n"
                  "    final state = widget.state;\n"
                  "    final s = AppStrings(AppSettings.instance.lang);\n"
                  "    final ctrl = TextEditingController(text: currentText);\n"
                  "    final result = await showDialog<String>(\n"
                  "      context: context,\n"
                  "      builder: (context) => AlertDialog(\n"
                  "        backgroundColor: AyatColors.surface,\n"
                  "        shape: RoundedRectangleBorder(\n"
                  "          borderRadius: BorderRadius.circular(22),\n"
                  "          side: const BorderSide(color: AyatColors.hairline),\n"
                  "        ),\n"
                  "        title: Text(s.t('stage.editText')),\n"
                  "        content: TextField(\n"
                  "          controller: ctrl,\n"
                  "          autofocus: true,\n"
                  "          maxLines: 4,\n"
                  "          textAlign: TextAlign.right,\n"
                  "          textDirection: TextDirection.rtl,\n"
                  "          style: const TextStyle(color: AyatColors.parchment),\n"
                  "          decoration: const InputDecoration(border: OutlineInputBorder()),\n"
                  "        ),\n"
                  "        actions: [\n",
                  "  Future<void> _openStageTextEditor(\n"
                  "      BuildContext context, String currentText) async {\n"
                  "    final state = widget.state;\n"
                  "    final s = AppStrings(AppSettings.instance.lang);\n"
                  "    final ctrl = TextEditingController(text: currentText);\n"
                  "    // PATCH_S134_AUTOSEG_WIZARD: word-level selection, real and safe --\n"
                  "    // a tappable word row that toggles the same state.redWordIndices\n"
                  "    // the الآية tab's chip section already writes to (and both the\n"
                  "    // live stage and the exporter already read from), just reachable\n"
                  "    // right from the stage's own edit flow instead of only from a\n"
                  "    // separate tab.\n"
                  "    final words = currentText\n"
                  "        .split(RegExp(r'\\s+'))\n"
                  "        .where((w) => w.isNotEmpty)\n"
                  "        .toList();\n"
                  "    final result = await showDialog<String>(\n"
                  "      context: context,\n"
                  "      builder: (context) => StatefulBuilder(\n"
                  "        builder: (context, setDialogState) => AlertDialog(\n"
                  "        backgroundColor: AyatColors.surface,\n"
                  "        shape: RoundedRectangleBorder(\n"
                  "          borderRadius: BorderRadius.circular(22),\n"
                  "          side: const BorderSide(color: AyatColors.hairline),\n"
                  "        ),\n"
                  "        title: Text(s.t('stage.editText')),\n"
                  "        content: SingleChildScrollView(\n"
                  "          child: Column(\n"
                  "            mainAxisSize: MainAxisSize.min,\n"
                  "            crossAxisAlignment: CrossAxisAlignment.start,\n"
                  "            children: [\n"
                  "              TextField(\n"
                  "                controller: ctrl,\n"
                  "                autofocus: true,\n"
                  "                maxLines: 4,\n"
                  "                textAlign: TextAlign.right,\n"
                  "                textDirection: TextDirection.rtl,\n"
                  "                style: const TextStyle(color: AyatColors.parchment),\n"
                  "                decoration: const InputDecoration(border: OutlineInputBorder()),\n"
                  "              ),\n"
                  "              if (words.isNotEmpty) ...[\n"
                  "                const SizedBox(height: 14),\n"
                  "                Text(s.t('stage.toggleWords'),\n"
                  "                    style: const TextStyle(\n"
                  "                        color: AyatColors.goldDim, fontSize: 12)),\n"
                  "                const SizedBox(height: 6),\n"
                  "                Wrap(\n"
                  "                  spacing: 6,\n"
                  "                  runSpacing: 6,\n"
                  "                  children: [\n"
                  "                    for (var i = 0; i < words.length; i++)\n"
                  "                      FilterChip(\n"
                  "                        label: Text(words[i],\n"
                  "                            style: ayahTextStyle(state.fontKey,\n"
                  "                                fontSize: 13)),\n"
                  "                        selected: state.redWordIndices.contains(i),\n"
                  "                        selectedColor: const Color(0xFFE53935)\n"
                  "                            .withValues(alpha: 0.35),\n"
                  "                        onSelected: (sel) {\n"
                  "                          state.update(() {\n"
                  "                            if (sel) {\n"
                  "                              state.redWordIndices.add(i);\n"
                  "                            } else {\n"
                  "                              state.redWordIndices.remove(i);\n"
                  "                            }\n"
                  "                          });\n"
                  "                          setDialogState(() {});\n"
                  "                        },\n"
                  "                      ),\n"
                  "                  ],\n"
                  "                ),\n"
                  "              ],\n"
                  "            ],\n"
                  "          ),\n"
                  "        ),\n"
                  "        actions: [\n",
                  "stage_preview.dart: word-toggle row in the stage edit dialog",
                  skip_if="s.t('stage.toggleWords')")

    apply_literal("lib/widgets/stage_preview.dart",
                  "          TextButton(\n"
                  "            onPressed: () => Navigator.pop(context, ctrl.text),\n"
                  "            child: Text(s.t('stage.editSave')),\n"
                  "          ),\n"
                  "        ],\n"
                  "      ),\n"
                  "    );\n"
                  "    ctrl.dispose();\n",
                  "          TextButton(\n"
                  "            onPressed: () => Navigator.pop(context, ctrl.text),\n"
                  "            child: Text(s.t('stage.editSave')),\n"
                  "          ),\n"
                  "        ],\n"
                  "        ),\n"
                  "      ),\n"
                  "    );\n"
                  "    ctrl.dispose();\n",
                  "stage_preview.dart: close StatefulBuilder wrapper around the dialog",
                  skip_if="        ],\n        ),\n      ),\n    );\n    ctrl.dispose();\n")

    print()
    print("=" * 60)
    print(f"S134 LEDGER — {sum(1 for _, s in LEDGER if s == 'APPLIED')} applied, "
          f"{sum(1 for _, s in LEDGER if s == 'SKIPPED-ALREADY')} already-applied, "
          f"out of {len(LEDGER)} operations")
    print("=" * 60)
    for label, status in LEDGER:
        print(f"  [{status:16}] {label}")
    print()
    print("NOT covered by this pass (real, scoped, not guessed at):")
    print(" - Raw on-stage tap-to-word hit-testing via WordHitTester. The class")
    print("   is real and complete (confirmed in this dump), but calling it")
    print("   correctly needs the exact pixel offsets the live stage's")
    print("   GestureDetector/Transform/Align/Container chain produces --")
    print("   not safely derivable without a running layout engine to check")
    print("   against. Word-level selection is delivered instead via a")
    print("   tappable word row in the already-wired stage-edit dialog,")
    print("   writing to the same state.redWordIndices the rest of the app")
    print("   already reads. Unblocking the raw version needs an on-device")
    print("   run with a debug overlay showing the text's actual paint Rect,")
    print("   not more dump text.")
    print(" - The long explainer paragraph under the partial-ayah header")
    print("   (~5 sentences) is still hardcoded Arabic -- only the short")
    print("   UI-facing literals (labels/buttons/toasts) were migrated this")
    print("   pass, matching the original cluster's intended scope.")
    print(" - Remaining full-page i18n: home_screen.dart still has ~215")
    print("   other hardcoded literals -- still too large to guess through")
    print("   safely in one patch.")
    print(" - Cloud V2 execution: no cloud backend exists in this APK; the")
    print("   wizard labels it honestly instead of faking it (S101 culture).")


WIZARD_SRC = r"""// PATCH_S134_AUTOSEG_WIZARD: the multi-step guided auto-segmentation flow
// (AI Version / Runtime / Models / Segmentation / Review+Run). NEW BUILD on
// purpose: nothing like it existed anywhere in the dump.
//
// Real wiring only:
//  * V1 local run applies the chosen WhisperModelSize through the exact
//    pair the existing model picker uses (state.update +
//    WhisperService.setModelSize), then hands off to the existing
//    auto-sync button with an honest toast -- it does not fake running
//    auto-sync itself.
//  * "Paste from Hugging Face" parses Quran Multi-Aligner-style JSON and
//    turns it into real TimelineSegments via StudioState.addManualSegment;
//    the Segmentation sliders (min silence / min speech / padding)
//    genuinely shape the imported spans (merge close same-ayah pieces,
//    drop too-short ones, extend by padding, clamp overlaps).
//  * Cloud V2 has no backend in this APK -> labeled honestly, never faked.
//
// Theme: AyatColors gold/hairline (this app's theme, not the reference
// screenshots' blue). RTL inherited from the app's Directionality.
import 'dart:convert';

import 'package:flutter/material.dart';

import '../i18n/app_strings.dart';
import '../models/studio_state.dart';
import '../services/app_settings.dart';
import '../services/whisper_service.dart';
import '../theme/ayat_theme.dart';

/// What the wizard changed, so the caller can toast/reveal correctly.
class AutoSegResult {
  final int importedSegments;
  final bool tierApplied;
  final bool cloudChosen;
  const AutoSegResult({
    this.importedSegments = 0,
    this.tierApplied = false,
    this.cloudChosen = false,
  });
}

enum _Step { version, runtime, models, segmentation, run }

enum _Runtime { cloud, local, json }

Future<AutoSegResult?> showAutoSegWizard({
  required BuildContext context,
  required StudioState state,
  String? audioPath,
}) {
  return showDialog<AutoSegResult>(
    context: context,
    builder: (_) => _AutoSegWizard(state: state, audioPath: audioPath),
  );
}

class _AutoSegWizard extends StatefulWidget {
  final StudioState state;
  final String? audioPath;
  const _AutoSegWizard({required this.state, this.audioPath});
  @override
  State<_AutoSegWizard> createState() => _AutoSegWizardState();
}

class _AutoSegWizardState extends State<_AutoSegWizard> {
  // (minSilenceMs, minSpeechMs, paddingMs) per preset.
  static const _presets = [
    (300.0, 1200.0, 150.0), // Mujawwad (slow)
    (200.0, 1000.0, 100.0), // Murattal (normal)
    (120.0, 600.0, 60.0), // Hadr (fast)
  ];

  _Step _step = _Step.version;
  bool _v2 = true;
  _Runtime _runtime = _Runtime.cloud;
  WhisperModelSize _tier = WhisperModelSize.small;
  bool _large = true;
  bool _gpu = true;
  int _preset = 1;
  double _minSilenceMs = 200;
  double _minSpeechMs = 1000;
  double _paddingMs = 100;
  bool _jsonBad = false;
  final TextEditingController _jsonCtrl = TextEditingController();

  @override
  void dispose() {
    _jsonCtrl.dispose();
    super.dispose();
  }

  AppStrings get _s => AppStrings(AppSettings.instance.lang);

  String get _audioName =>
      widget.audioPath == null ? '' : widget.audioPath!.split(RegExp(r'[\\/]')).last;

  void _applyPreset(int i) {
    setState(() {
      _preset = i;
      _minSilenceMs = _presets[i].$1;
      _minSpeechMs = _presets[i].$2;
      _paddingMs = _presets[i].$3;
    });
  }

  // ------------------------------------------------------------------
  // JSON import: real TimelineSegments through addManualSegment, with the
  // segmentation sliders genuinely applied to the imported spans.
  // Returns -1 for invalid/unparsable JSON, 0 for "parsed but nothing
  // usable came out of it", >0 for the count actually added.
  // ------------------------------------------------------------------
  int _importJson() {
    final raw = _jsonCtrl.text.trim();
    if (raw.isEmpty) return -1;
    dynamic dec;
    try {
      dec = jsonDecode(raw);
    } catch (_) {
      return -1;
    }
    final List<dynamic> rows = dec is List
        ? dec
        : (dec is Map && dec['segments'] is List ? dec['segments'] as List : const []);
    final pad = _paddingMs / 1000.0;
    final minSpeech = _minSpeechMs / 1000.0;
    final minSil = _minSilenceMs / 1000.0;
    final parsed = <List<double>>[]; // [start, end, surahNum, ayahNum]
    for (final r in rows) {
      if (r is! Map) continue;
      final st0 = r['start'] ?? r['from'];
      final en0 = r['end'] ?? r['to'];
      if (st0 is! num || en0 is! num) continue;
      var st = st0.toDouble();
      var en = en0.toDouble();
      var surah = 0;
      var num = 0;
      final ref = r['ref'] ?? r['reference'] ?? r['key'];
      if (ref is String) {
        final m = RegExp(r'(\d+)\s*[:\-]\s*(\d+)').firstMatch(ref);
        if (m != null) {
          surah = int.parse(m.group(1)!);
          num = int.parse(m.group(2)!);
        }
      }
      if (surah == 0 && r['surah'] is num) surah = (r['surah'] as num).toInt();
      if (num == 0 && r['ayah'] is num) num = (r['ayah'] as num).toInt();
      if (surah == 0 || num == 0 || en <= st) continue;
      en += pad;
      if (en - st < minSpeech) continue;
      if (parsed.isNotEmpty) {
        final prev = parsed.last;
        if (prev[2] == surah && prev[3] == num && st - prev[1] <= minSil) {
          if (en > prev[1]) prev[1] = en; // same ayah, close piece -> merge
          continue;
        }
        if (st < prev[1]) st = prev[1]; // clamp overlap with previous segment
      }
      parsed.add([st, en, surah.toDouble(), num.toDouble()]);
    }
    if (parsed.isEmpty) return 0;
    final corpus = widget.state.ayaat;
    var added = 0;
    for (final p in parsed) {
      final idx = corpus.indexWhere(
          (a) => a.surahNum == p[2].toInt() && a.num == p[3].toInt());
      if (idx < 0) continue; // unknown ref -> skip, never fabricate an Ayah
      widget.state.addManualSegment(corpus[idx], p[0], p[1]);
      added++;
    }
    return added;
  }

  AutoSegResult _launch() {
    if (_runtime == _Runtime.json) {
      return AutoSegResult(importedSegments: _importJson());
    }
    if (_runtime == _Runtime.local) {
      // Exact pair the existing model picker uses (S43).
      widget.state.update(() => widget.state.whisperModelSize = _tier);
      WhisperService.setModelSize(_tier);
      return const AutoSegResult(tierApplied: true);
    }
    return const AutoSegResult(cloudChosen: true); // no backend in this APK
  }

  void _start() {
    final res = _launch();
    if (_runtime == _Runtime.json && res.importedSegments < 0) {
      setState(() => _jsonBad = true);
      return;
    }
    Navigator.of(context).pop(res);
  }

  // ------------------------------------------------------------------
  Widget _card({required bool selected, required VoidCallback onTap,
      required Widget child}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(
              color: selected ? AyatColors.gold : AyatColors.hairline,
              width: selected ? 1.4 : 1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: child,
      ),
    );
  }

  Widget _title(String t, [String? hint]) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t, style: Theme.of(context).textTheme.titleSmall),
          if (hint != null) ...[
            const SizedBox(height: 4),
            Text(hint,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AyatColors.goldDim)),
          ],
        ],
      );

  Widget _badge() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
            color: AyatColors.gold, borderRadius: BorderRadius.circular(10)),
        child: Text(_s.t('wizard.recommended'),
            style: const TextStyle(fontSize: 10, color: Colors.black)),
      );

  Widget _segRow(List<String> labels, int sel, ValueChanged<int> on) => Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: _card(
                    selected: sel == i,
                    onTap: () => on(i),
                    child: Center(
                        child: Text(labels[i],
                            style: const TextStyle(fontSize: 12)))),
              ),
            ),
        ],
      );

  Widget _slider(String label, double v, double min, double max,
          ValueChanged<double> on) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$label: ${v.round()}ms',
            style: Theme.of(context).textTheme.bodySmall),
        Slider(value: v, min: min, max: max, divisions: 20, onChanged: on),
      ]);

  Widget _stepBody() {
    switch (_step) {
      case _Step.version:
        return Column(children: [
          _card(
              selected: !_v2,
              onTap: () => setState(() => _v2 = false),
              child: _title(_s.t('wizard.v1'), _s.t('wizard.v1Desc'))),
          const SizedBox(height: 10),
          _card(
              selected: _v2,
              onTap: () => setState(() => _v2 = true),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(child: _title(_s.t('wizard.v2'))),
                      _badge(),
                    ]),
                    const SizedBox(height: 4),
                    Text(_s.t('wizard.v2Desc'),
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AyatColors.goldDim)),
                  ])),
        ]);
      case _Step.runtime:
        return Column(children: [
          _card(
              selected: _runtime == _Runtime.cloud,
              onTap: () => setState(() => _runtime = _Runtime.cloud),
              child: Row(children: [
                Expanded(child: _title(_s.t('wizard.cloud'), _s.t('wizard.cloudDesc'))),
                _badge(),
              ])),
          if (_runtime == _Runtime.cloud) ...[
            const SizedBox(height: 6),
            Text(_s.t('wizard.cloudNote'),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AyatColors.goldDim)),
          ],
          const SizedBox(height: 10),
          _card(
              selected: _runtime == _Runtime.local,
              onTap: () => setState(() => _runtime = _Runtime.local),
              child: _title(_s.t('wizard.local'), _s.t('wizard.localDesc'))),
          const SizedBox(height: 10),
          _card(
              selected: _runtime == _Runtime.json,
              onTap: () => setState(() => _runtime = _Runtime.json),
              child: _title(_s.t('wizard.json'), _s.t('wizard.jsonDesc'))),
          if (_runtime == _Runtime.json) ...[
            const SizedBox(height: 8),
            TextField(
                controller: _jsonCtrl,
                maxLines: 6,
                onChanged: (_) => setState(() => _jsonBad = false),
                decoration: InputDecoration(hintText: _s.t('wizard.jsonHint'))),
            if (_jsonBad)
              Text(_s.t('wizard.jsonBad'),
                  style: const TextStyle(color: Color(0xFFE53935), fontSize: 12)),
          ],
        ]);
      case _Step.models:
        return Column(children: [
          if (_v2)
            Row(children: [
              Expanded(
                  child: _card(
                      selected: !_large,
                      onTap: () => setState(() => _large = false),
                      child: _title(_s.t('wizard.base'), _s.t('wizard.baseDesc')))),
              const SizedBox(width: 10),
              Expanded(
                  child: _card(
                      selected: _large,
                      onTap: () => setState(() => _large = true),
                      child: _title(_s.t('wizard.large'), _s.t('wizard.largeDesc')))),
            ])
          else
            Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final size in WhisperModelSize.values)
                    ChoiceChip(
                        label: Text(WhisperService.labelFor(size)),
                        selected: _tier == size,
                        onSelected: (_) => setState(() => _tier = size)),
                ]),
          const SizedBox(height: 14),
          Text(_s.t('wizard.device'),
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          _segRow(const ['GPU', 'CPU'], _gpu ? 0 : 1,
              (i) => setState(() => _gpu = i == 0)),
        ]);
      case _Step.segmentation:
        return Column(children: [
          _segRow(
              [_s.t('wizard.presetSlow'), _s.t('wizard.presetNormal'), _s.t('wizard.presetFast')],
              _preset, _applyPreset),
          const SizedBox(height: 10),
          _slider(_s.t('wizard.minSilence'), _minSilenceMs, 50, 1000,
              (v) => setState(() => _minSilenceMs = v)),
          _slider(_s.t('wizard.minSpeech'), _minSpeechMs, 200, 3000,
              (v) => setState(() => _minSpeechMs = v)),
          _slider(_s.t('wizard.padding'), _paddingMs, 0, 500,
              (v) => setState(() => _paddingMs = v)),
        ]);
      case _Step.run:
        final model = _v2
            ? (_large ? _s.t('wizard.large') : _s.t('wizard.base'))
            : WhisperService.labelFor(_tier);
        return _card(
            selected: false,
            onTap: () {},
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _title(_s.t('wizard.review'), _s.t('wizard.reviewHint')),
                  const SizedBox(height: 10),
                  Text('${_s.t('wizard.version')}: ${_v2 ? _s.t('wizard.v2') : _s.t('wizard.v1')}'),
                  Text('${_s.t('wizard.runtime')}: '
                      '${_runtime == _Runtime.cloud ? _s.t('wizard.cloud') : _runtime == _Runtime.local ? _s.t('wizard.local') : _s.t('wizard.json')}'),
                  Text('${_s.t('wizard.models')}: $model'),
                  Text('${_s.t('wizard.device')}: ${_gpu ? 'GPU' : 'CPU'}'),
                  if (_audioName.isNotEmpty) Text('Audio: $_audioName'),
                ]));
    }
  }

  @override
  Widget build(BuildContext context) {
    final steps = _Step.values;
    final last = _step == steps.last;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860, maxHeight: 640),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              const Icon(Icons.auto_awesome_outlined, color: AyatColors.gold),
              const SizedBox(width: 10),
              Expanded(
                  child: _title(_s.t('wizard.title'), _s.t('wizard.subtitle'))),
              IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop()),
            ]),
          ),
          const Divider(height: 1, color: AyatColors.hairline),
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(
                width: 220,
                child: ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          border: Border.all(color: AyatColors.hairline),
                          borderRadius: BorderRadius.circular(10)),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                                widget.audioPath != null
                                    ? Icons.check_circle
                                    : Icons.warning_amber_rounded,
                                color: widget.audioPath != null
                                    ? const Color(0xFF43A047)
                                    : AyatColors.goldDim,
                                size: 18),
                            const SizedBox(height: 6),
                            Text(
                                widget.audioPath != null
                                    ? '${_s.t('wizard.audio')}: $_audioName'
                                    : _s.t('wizard.noAudio'),
                                style: const TextStyle(fontSize: 11)),
                          ]),
                    ),
                    const SizedBox(height: 10),
                    for (final st in steps)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _card(
                            selected: _step == st,
                            onTap: () => setState(() => _step = st),
                            child: Text(
                                {
                                  _Step.version: _s.t('wizard.version'),
                                  _Step.runtime: _s.t('wizard.runtime'),
                                  _Step.models: _s.t('wizard.models'),
                                  _Step.segmentation: _s.t('wizard.segmentation'),
                                  _Step.run: _s.t('wizard.run'),
                                }[st]!,
                                style: const TextStyle(fontSize: 13))),
                      ),
                  ],
                ),
              ),
              const VerticalDivider(width: 1, color: AyatColors.hairline),
              Expanded(
                  child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [_stepBody()])),
            ]),
          ),
          const Divider(height: 1, color: AyatColors.hairline),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(
                  child: _runtime == _Runtime.cloud
                      ? Text(_s.t('wizard.cloudNote'),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AyatColors.goldDim))
                      : const SizedBox.shrink()),
              TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(_s.t('common.cancel'))),
              if (_step != steps.first)
                IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => setState(() =>
                        _step = steps[steps.indexOf(_step) - 1])),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AyatColors.gold,
                    foregroundColor: Colors.black),
                onPressed: last
                    ? _start
                    : () => setState(
                        () => _step = steps[steps.indexOf(_step) + 1]),
                child: Text(last ? _s.t('wizard.start') : 'Next'),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
"""

if __name__ == "__main__":
    main()
