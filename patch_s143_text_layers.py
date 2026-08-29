# patch_s143_text_layers.py
#
# THE PROBLEM (as reported):
#   The "اكتب نص الآية" box tries to do two jobs at once -- match what you
#   typed against the Quran, AND act as a plain caption -- and "تطبيق كنص
#   ثابت" silently OVERWRITES whatever fixed text was there before. There is
#   no way to have more than one fixed-text box, and pressing the button
#   again just replaces box #1 instead of adding box #2.
#
# THE FIX:
#   A brand new, separate "طبقات نص ثابتة" (fixed text layers) section,
#   modeled on the same list pattern the app already uses for
#   "نطاق آيات متعدد" (S57) -- but evolved per your screenshots:
#     - No Quran matching here at all. What you type is what appears,
#       always. Zero ambiguity, zero silent overwrite.
#     - Every tap on "إضافة طبقة نص" adds ONE MORE independent box, the
#       existing ones stay exactly as they were.
#     - Each layer has its own position (top / middle / bottom of frame)
#       so several can be on screen without stacking on top of each other.
#     - Layers combine freely with the ayah text AND with the caption AND
#       with each other -- nothing here replaces anything else.
#     - Each layer is listed below the input with a delete button, so you
#       can see everything that's currently on screen and remove any one
#       of them.
#   The existing "اكتب نص الآية" ayah-matching box is untouched -- it still
#   does exactly what it did before. This is a genuinely new, separate
#   feature living next to it, not a rewrite of it.
#
# WHAT THIS PATCH TOUCHES:
#   1. lib/models/studio_state.dart   -- new TextLayer model + state list
#   2. lib/services/overlay_renderer.dart -- draws the layers into the
#      exported video (same renderer the export pipeline already uses,
#      per its own "Preview = Export" rule)
#   3. lib/services/export_service.dart -- passes state.textLayers into
#      the (single) OverlayStyle construction site
#   4. lib/widgets/stage_preview.dart -- draws the layers live, mirroring
#      how PATCH_S116 made captionText show up live instead of only at
#      export
#   5. lib/screens/home_screen.dart -- the new "طبقات نص ثابتة" card + its
#      own controller/position field
#
# NOT covered by this patch (flagged rather than guessed at):
#   - Free dragging of each layer (like the ayah text's own drag-to-move).
#     Position is top/middle/bottom for now, same three slots the ayah
#     text and the caption already use. Free placement is a bigger change
#     (per-layer Offset + hit-testing) and is a reasonable S144 if you
#     want it next.
#   - Per-layer font/animation beyond size, color and position.
#
# Run from the project root (same convention as the other patch_sNNN
# scripts in this repo).

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


STUDIO_STATE = "lib/models/studio_state.dart"
OVERLAY_RENDERER = "lib/services/overlay_renderer.dart"
EXPORT_SERVICE = "lib/services/export_service.dart"
STAGE_PREVIEW = "lib/widgets/stage_preview.dart"
HOME_SCREEN = "lib/screens/home_screen.dart"


# --------------------------------------------------------------------------
# 1. lib/models/studio_state.dart -- TextLayer model + list on StudioState
# --------------------------------------------------------------------------

def patch_studio_state():
    old_enum = (
        "enum S128LabelShape { rounded, circle, pill, scallop, hexagon }\n"
        "\n"
        "class StudioState extends ChangeNotifier {"
    )
    new_enum = (
        "enum S128LabelShape { rounded, circle, pill, scallop, hexagon }\n"
        "\n"
        "// PATCH_S143_TEXT_LAYERS: a single independent \"fixed text\" box, "
        "stacked\n"
        "// freely on top of the ayah and the caption. Unlike ayahText/"
        "captionText\n"
        "// (one slot each, silently overwritten), these live in a real list "
        "-- add\n"
        "// as many as you like, remove any one without touching the "
        "others.\n"
        "class TextLayer {\n"
        "  String text;\n"
        "  AyahTextPosition position;\n"
        "  double fontSize; // preview-scale px, same convention as "
        "ayahFontSize\n"
        "  Color color;\n"
        "  TextLayer({\n"
        "    required this.text,\n"
        "    this.position = AyahTextPosition.top,\n"
        "    this.fontSize = 20,\n"
        "    this.color = const Color(0xFFECC875),\n"
        "  });\n"
        "}\n"
        "\n"
        "class StudioState extends ChangeNotifier {"
    )
    apply_literal(STUDIO_STATE, old_enum, new_enum,
                  "studio_state.dart: add TextLayer model",
                  skip_if="class TextLayer {")

    old_field = (
        "  bool get hasAyah => ayahText.isNotEmpty;\n"
        "\n"
        "  // PATCH_S129_QURAN_CAPTION_PARITY: project identity "
        "(dashboard + chapters header)"
    )
    new_field = (
        "  bool get hasAyah => ayahText.isNotEmpty;\n"
        "\n"
        "  // ---- PATCH_S143_TEXT_LAYERS: stackable fixed-text boxes "
        "----------------\n"
        "  List<TextLayer> textLayers = [];\n"
        "\n"
        "  void addTextLayer(TextLayer layer) {\n"
        "    textLayers = [...textLayers, layer];\n"
        "    notifyListeners();\n"
        "  }\n"
        "\n"
        "  void updateTextLayerAt(int index, TextLayer layer) {\n"
        "    if (index < 0 || index >= textLayers.length) return;\n"
        "    final next = [...textLayers];\n"
        "    next[index] = layer;\n"
        "    textLayers = next;\n"
        "    notifyListeners();\n"
        "  }\n"
        "\n"
        "  void removeTextLayerAt(int index) {\n"
        "    if (index < 0 || index >= textLayers.length) return;\n"
        "    final next = [...textLayers]..removeAt(index);\n"
        "    textLayers = next;\n"
        "    notifyListeners();\n"
        "  }\n"
        "\n"
        "  // PATCH_S129_QURAN_CAPTION_PARITY: project identity "
        "(dashboard + chapters header)"
    )
    apply_literal(STUDIO_STATE, old_field, new_field,
                  "studio_state.dart: add textLayers list + add/update/remove",
                  skip_if="List<TextLayer> textLayers = [];")


# --------------------------------------------------------------------------
# 2. lib/services/overlay_renderer.dart -- render the layers (export)
# --------------------------------------------------------------------------

def patch_overlay_renderer():
    old_imports = (
        "import '../data/studio_presets.dart';\n"
        "import '../data/text_transitions.dart'; // PATCH_S126_TEXT_TRANSITIONS\n"
        "import '../theme/ayat_fonts.dart';"
    )
    new_imports = (
        "import '../data/studio_presets.dart';\n"
        "import '../data/text_transitions.dart'; // PATCH_S126_TEXT_TRANSITIONS\n"
        "import '../models/studio_state.dart'; // PATCH_S143_TEXT_LAYERS: TextLayer\n"
        "import '../theme/ayat_fonts.dart';"
    )
    apply_literal(OVERLAY_RENDERER, old_imports, new_imports,
                  "overlay_renderer.dart: import TextLayer",
                  skip_if="PATCH_S143_TEXT_LAYERS: TextLayer")

    old_field = (
        "  final Set<int> redWordIndices;\n"
        "  final String captionText;\n"
        "  final CaptionPosition captionPosition;\n"
    )
    new_field = (
        "  final Set<int> redWordIndices;\n"
        "  final String captionText;\n"
        "  final CaptionPosition captionPosition;\n"
        "  // PATCH_S143_TEXT_LAYERS: independent stacked fixed-text boxes,\n"
        "  // drawn on top of the ayah and the caption, never replacing "
        "either.\n"
        "  final List<TextLayer> textLayers;\n"
    )
    apply_literal(OVERLAY_RENDERER, old_field, new_field,
                  "overlay_renderer.dart: OverlayStyle.textLayers field",
                  skip_if="final List<TextLayer> textLayers;")

    old_ctor = (
        "    this.captionText = '',\n"
        "    this.captionPosition = CaptionPosition.bottom,\n"
        "    this.motion = TextMotion.identity,\n"
        "  });"
    )
    new_ctor = (
        "    this.captionText = '',\n"
        "    this.captionPosition = CaptionPosition.bottom,\n"
        "    this.motion = TextMotion.identity,\n"
        "    this.textLayers = const [], // PATCH_S143_TEXT_LAYERS\n"
        "  });"
    )
    apply_literal(OVERLAY_RENDERER, old_ctor, new_ctor,
                  "overlay_renderer.dart: OverlayStyle constructor param",
                  skip_if="this.textLayers = const [], // PATCH_S143_TEXT_LAYERS")

    old_with_motion = (
        "        captionText: captionText,\n"
        "        captionPosition: captionPosition,\n"
        "        motion: m,\n"
        "      );"
    )
    new_with_motion = (
        "        captionText: captionText,\n"
        "        captionPosition: captionPosition,\n"
        "        motion: m,\n"
        "        textLayers: textLayers, // PATCH_S143_TEXT_LAYERS\n"
        "      );"
    )
    apply_literal(OVERLAY_RENDERER, old_with_motion, new_with_motion,
                  "overlay_renderer.dart: withMotion carries textLayers",
                  skip_if="textLayers: textLayers, // PATCH_S143_TEXT_LAYERS")

    old_paint_tail = (
        "      final capY = style.captionPosition == CaptionPosition.top\n"
        "          ? h * 0.05\n"
        "          : h * 0.93 - capPainter.height;\n"
        "      capPainter.paint(canvas, Offset((w - capPainter.width) / 2, capY));\n"
        "    }\n"
        "\n"
        "    return _picToPng(rec.endRecording(), w, h);"
    )
    new_paint_tail = (
        "      final capY = style.captionPosition == CaptionPosition.top\n"
        "          ? h * 0.05\n"
        "          : h * 0.93 - capPainter.height;\n"
        "      capPainter.paint(canvas, Offset((w - capPainter.width) / 2, capY));\n"
        "    }\n"
        "\n"
        "    // PATCH_S143_TEXT_LAYERS: independent stacked fixed-text boxes.\n"
        "    // Grouped by band (top/center/bottom) so several layers in the\n"
        "    // same band stack instead of overlapping -- matches the live\n"
        "    // preview in stage_preview.dart exactly (same rule as every\n"
        "    // other overlay this renderer draws: preview == export).\n"
        "    if (style.textLayers.isNotEmpty) {\n"
        "      final layerScale = w / 270.0;\n"
        "      TextPainter layerPainter(TextLayer layer) => TextPainter(\n"
        "            text: TextSpan(\n"
        "              text: layer.text,\n"
        "              style: ayahTextStyle(\n"
        "                style.fontKey,\n"
        "                fontSize: layer.fontSize * layerScale,\n"
        "                color: layer.color.withValues(alpha: opacity),\n"
        "                shadows: [\n"
        "                  Shadow(\n"
        "                      color: Color.fromRGBO(0, 0, 0, 0.7 * opacity),\n"
        "                      blurRadius: 6 * layerScale),\n"
        "                ],\n"
        "              ),\n"
        "            ),\n"
        "            textAlign: TextAlign.center,\n"
        "            textDirection: TextDirection.rtl,\n"
        "          )..layout(maxWidth: w * 0.86);\n"
        "\n"
        "      final top = style.textLayers\n"
        "          .where((l) => l.position == AyahTextPosition.top)\n"
        "          .toList();\n"
        "      final center = style.textLayers\n"
        "          .where((l) => l.position == AyahTextPosition.center)\n"
        "          .toList();\n"
        "      final bottom = style.textLayers\n"
        "          .where((l) => l.position == AyahTextPosition.bottom)\n"
        "          .toList();\n"
        "\n"
        "      var y = h * 0.06;\n"
        "      for (final layer in top) {\n"
        "        final p = layerPainter(layer);\n"
        "        p.paint(canvas, Offset((w - p.width) / 2, y));\n"
        "        y += p.height + 6 * layerScale;\n"
        "      }\n"
        "\n"
        "      var totalCenterH = 0.0;\n"
        "      final centerPainters = <TextPainter>[];\n"
        "      for (final layer in center) {\n"
        "        final p = layerPainter(layer);\n"
        "        centerPainters.add(p);\n"
        "        totalCenterH += p.height + 6 * layerScale;\n"
        "      }\n"
        "      var centerY = h * 0.5 - totalCenterH / 2;\n"
        "      for (final p in centerPainters) {\n"
        "        p.paint(canvas, Offset((w - p.width) / 2, centerY));\n"
        "        centerY += p.height + 6 * layerScale;\n"
        "      }\n"
        "\n"
        "      var bottomY = h * 0.94;\n"
        "      for (final layer in bottom.reversed) {\n"
        "        final p = layerPainter(layer);\n"
        "        bottomY -= p.height;\n"
        "        p.paint(canvas, Offset((w - p.width) / 2, bottomY));\n"
        "        bottomY -= 6 * layerScale;\n"
        "      }\n"
        "    }\n"
        "\n"
        "    return _picToPng(rec.endRecording(), w, h);"
    )
    apply_literal(OVERLAY_RENDERER, old_paint_tail, new_paint_tail,
                  "overlay_renderer.dart: paint text layers into export",
                  skip_if="PATCH_S143_TEXT_LAYERS: independent stacked fixed-text boxes.")


# --------------------------------------------------------------------------
# 3. lib/services/export_service.dart -- wire textLayers into the (only)
#    OverlayStyle construction site
# --------------------------------------------------------------------------

def patch_export_service():
    old = (
        "        redWordIndices: state.redWordIndices,\n"
        "        captionText: state.captionText,\n"
        "        captionPosition: state.captionPosition,\n"
        "      );"
    )
    new = (
        "        redWordIndices: state.redWordIndices,\n"
        "        captionText: state.captionText,\n"
        "        captionPosition: state.captionPosition,\n"
        "        textLayers: state.textLayers, // PATCH_S143_TEXT_LAYERS\n"
        "      );"
    )
    apply_literal(EXPORT_SERVICE, old, new,
                  "export_service.dart: pass state.textLayers to OverlayStyle",
                  skip_if="textLayers: state.textLayers, // PATCH_S143_TEXT_LAYERS")


# --------------------------------------------------------------------------
# 4. lib/widgets/stage_preview.dart -- show the layers live (preview == export)
# --------------------------------------------------------------------------

def patch_stage_preview():
    old = (
        "                  ),\n"
        "                // PATCH_S123_WATERMARK: shown live, in the same "
        "corner and at"
    )
    new = (
        "                  ),\n"
        "                // PATCH_S143_TEXT_LAYERS: mirrors PATCH_S116's fix "
        "for\n"
        "                // captionText -- these were drawn by the export "
        "renderer\n"
        "                // from day one, so show them live too instead of "
        "the\n"
        "                // preview lying about what the export will look "
        "like.\n"
        "                if (state.textLayers.isNotEmpty)\n"
        "                  ..._buildTextLayerWidgets(state.textLayers, "
        "scale),\n"
        "                // PATCH_S123_WATERMARK: shown live, in the same "
        "corner and at"
    )
    apply_literal(STAGE_PREVIEW, old, new,
                  "stage_preview.dart: draw text layers live in the Stack",
                  skip_if="PATCH_S143_TEXT_LAYERS: mirrors PATCH_S116")

    # Helper method: groups by band and stacks each band as a Column, same
    # top/center/bottom bands the renderer above uses for export.
    old_class_marker = "class _StagePreviewState extends State<StagePreview>"
    # Insert the helper right before the class's closing brace is risky to
    # locate generically, so instead we hang it off the first method we know
    # exists in this class already: the watermark preview builder.
    old_watermark_method = "Widget _watermarkPreview(StudioState state, double scale) {"
    new_watermark_method = (
        "  // PATCH_S143_TEXT_LAYERS: groups layers by band (top/center/"
        "bottom)\n"
        "  // and stacks each band top-to-bottom via a Column -- Flutter "
        "does the\n"
        "  // stacking math for free here, unlike the manual TextPainter "
        "y-walk\n"
        "  // the export renderer needs (see overlay_renderer.dart).\n"
        "  List<Widget> _buildTextLayerWidgets(\n"
        "      List<TextLayer> layers, double scale) {\n"
        "    Widget layerText(TextLayer layer) => Padding(\n"
        "          padding: EdgeInsets.symmetric(vertical: 3 * "
        "scale.clamp(0.8, 1.6)),\n"
        "          child: Text(\n"
        "            layer.text,\n"
        "            textAlign: TextAlign.center,\n"
        "            textDirection: TextDirection.rtl,\n"
        "            style: TextStyle(\n"
        "              fontSize: layer.fontSize * scale.clamp(0.8, 1.6),\n"
        "              color: layer.color,\n"
        "              shadows: const [\n"
        "                Shadow(color: Color(0xB3000000), blurRadius: 6),\n"
        "              ],\n"
        "            ),\n"
        "          ),\n"
        "        );\n"
        "\n"
        "    final top = layers\n"
        "        .where((l) => l.position == AyahTextPosition.top)\n"
        "        .toList();\n"
        "    final center = layers\n"
        "        .where((l) => l.position == AyahTextPosition.center)\n"
        "        .toList();\n"
        "    final bottom = layers\n"
        "        .where((l) => l.position == AyahTextPosition.bottom)\n"
        "        .toList();\n"
        "\n"
        "    final widgets = <Widget>[];\n"
        "    if (top.isNotEmpty) {\n"
        "      widgets.add(PositionedDirectional(\n"
        "        top: 46,\n"
        "        start: 12,\n"
        "        end: 12,\n"
        "        child: IgnorePointer(\n"
        "          child: Column(\n"
        "            mainAxisSize: MainAxisSize.min,\n"
        "            children: [for (final l in top) layerText(l)],\n"
        "          ),\n"
        "        ),\n"
        "      ));\n"
        "    }\n"
        "    if (center.isNotEmpty) {\n"
        "      widgets.add(PositionedDirectional(\n"
        "        top: 0,\n"
        "        bottom: 0,\n"
        "        start: 12,\n"
        "        end: 12,\n"
        "        child: IgnorePointer(\n"
        "          child: Center(\n"
        "            child: Column(\n"
        "              mainAxisSize: MainAxisSize.min,\n"
        "              children: [for (final l in center) layerText(l)],\n"
        "            ),\n"
        "          ),\n"
        "        ),\n"
        "      ));\n"
        "    }\n"
        "    if (bottom.isNotEmpty) {\n"
        "      widgets.add(PositionedDirectional(\n"
        "        bottom: 46,\n"
        "        start: 12,\n"
        "        end: 12,\n"
        "        child: IgnorePointer(\n"
        "          child: Column(\n"
        "            mainAxisSize: MainAxisSize.min,\n"
        "            children: [for (final l in bottom) layerText(l)],\n"
        "          ),\n"
        "        ),\n"
        "      ));\n"
        "    }\n"
        "    return widgets;\n"
        "  }\n"
        "\n"
        "  Widget _watermarkPreview(StudioState state, double scale) {"
    )
    apply_literal(STAGE_PREVIEW, old_watermark_method, new_watermark_method,
                  "stage_preview.dart: add _buildTextLayerWidgets helper",
                  skip_if="List<Widget> _buildTextLayerWidgets(")
    _ = old_class_marker  # kept only as a documented anchor, unused directly


# --------------------------------------------------------------------------
# 5. lib/screens/home_screen.dart -- new "طبقات نص ثابتة" card
# --------------------------------------------------------------------------

def patch_home_screen():
    old_ctrls = (
        "  final _customArCtrl = TextEditingController();\n"
        "  final _customEnCtrl = TextEditingController();\n"
    )
    new_ctrls = (
        "  final _customArCtrl = TextEditingController();\n"
        "  final _customEnCtrl = TextEditingController();\n"
        "  // PATCH_S143_TEXT_LAYERS: separate from the ayah-matching "
        "controllers\n"
        "  // above -- this box never tries to match the Quran, it just "
        "adds a\n"
        "  // new stacked text layer verbatim.\n"
        "  final _newLayerCtrl = TextEditingController();\n"
        "  AyahTextPosition _newLayerPosition = AyahTextPosition.top;\n"
    )
    apply_literal(HOME_SCREEN, old_ctrls, new_ctrls,
                  "home_screen.dart: add _newLayerCtrl + _newLayerPosition",
                  skip_if="_newLayerCtrl = TextEditingController();")

    old_dispose = (
        "    _customArCtrl.dispose();\n"
        "    _customEnCtrl.dispose();\n"
    )
    new_dispose = (
        "    _customArCtrl.dispose();\n"
        "    _customEnCtrl.dispose();\n"
        "    _newLayerCtrl.dispose(); // PATCH_S143_TEXT_LAYERS\n"
    )
    apply_literal(HOME_SCREEN, old_dispose, new_dispose,
                  "home_screen.dart: dispose _newLayerCtrl",
                  skip_if="_newLayerCtrl.dispose();")

    old_card_tail = (
        "            Row(children: [\n"
        "              Expanded(child: ElevatedButton(\n"
        "                  onPressed: _applyCustomText,\n"
        "                  child: const Text('تطبيق كنص ثابت'))),\n"
        "              const SizedBox(width: 8),\n"
        "              Expanded(child: OutlinedButton.icon(\n"
        "                  onPressed: _saveTypedTextToTimeline,\n"
        "                  icon: const Icon(Icons.timeline, size: 18),\n"
        "                  label: const Text('حفظ في الخط الزمني'))),\n"
        "            ]),\n"
        "          ],\n"
        "        )),\n"
    )
    new_card_tail = (
        "            Row(children: [\n"
        "              Expanded(child: ElevatedButton(\n"
        "                  onPressed: _applyCustomText,\n"
        "                  child: const Text('تطبيق كنص ثابت'))),\n"
        "              const SizedBox(width: 8),\n"
        "              Expanded(child: OutlinedButton.icon(\n"
        "                  onPressed: _saveTypedTextToTimeline,\n"
        "                  icon: const Icon(Icons.timeline, size: 18),\n"
        "                  label: const Text('حفظ في الخط الزمني'))),\n"
        "            ]),\n"
        "          ],\n"
        "        )),\n"
        "        // PATCH_S143_TEXT_LAYERS: a completely separate, "
        "no-matching\n"
        "        // stack of fixed text boxes. Distinct from the card "
        "above --\n"
        "        // nothing here is ever auto-detected against the Quran "
        "or\n"
        "        // silently overwritten. Every tap on \"إضافة طبقة نص\" "
        "adds one\n"
        "        // more independent layer; the list below shows every "
        "layer\n"
        "        // currently on screen with its own delete button.\n"
        "        _sectionCard(Column(\n"
        "          crossAxisAlignment: CrossAxisAlignment.stretch,\n"
        "          children: [\n"
        "            _sectionHeader(\n"
        "              'طبقات نص ثابتة',\n"
        "              'نص عربي بسيط تكتبينه بنفسك -- بلا أي تعرّف أو "
        "تخمين، وما '\n"
        "              'تكتبينه هو ما يظهر دائمًا. كل ضغطة على \"إضافة طبقة "
        "نص\" '\n"
        "              'تضيف مربعًا جديدًا مستقلاً بجانب ما أضفتِه سابقًا -- "
        "لا شيء '\n"
        "              'يُستبدل. تظهر كل الطبقات معًا فوق الفيديو وفوق نص "
        "الآية.',\n"
        "            ),\n"
        "            const SizedBox(height: 8),\n"
        "            TextField(\n"
        "              controller: _newLayerCtrl,\n"
        "              maxLines: 2,\n"
        "              textAlign: TextAlign.right,\n"
        "              decoration: const InputDecoration(\n"
        "                hintText: 'اكتب أي نص… (اسم القناة، تعليق، عنوان، "
        "...)',\n"
        "                border: OutlineInputBorder(),\n"
        "              ),\n"
        "            ),\n"
        "            const SizedBox(height: 8),\n"
        "            Row(children: [\n"
        "              const Text('الموضع:'),\n"
        "              const SizedBox(width: 10),\n"
        "              DropdownButton<AyahTextPosition>(\n"
        "                value: _newLayerPosition,\n"
        "                items: const [\n"
        "                  DropdownMenuItem(\n"
        "                      value: AyahTextPosition.top,\n"
        "                      child: Text('أعلى الشاشة')),\n"
        "                  DropdownMenuItem(\n"
        "                      value: AyahTextPosition.center,\n"
        "                      child: Text('منتصف الشاشة')),\n"
        "                  DropdownMenuItem(\n"
        "                      value: AyahTextPosition.bottom,\n"
        "                      child: Text('أسفل الشاشة')),\n"
        "                ],\n"
        "                onChanged: (v) => setState(\n"
        "                    () => _newLayerPosition = v ?? "
        "AyahTextPosition.top),\n"
        "              ),\n"
        "            ]),\n"
        "            const SizedBox(height: 10),\n"
        "            OutlinedButton.icon(\n"
        "              onPressed: () {\n"
        "                final txt = _newLayerCtrl.text.trim();\n"
        "                if (txt.isEmpty) {\n"
        "                  _toast('اكتبي نصًا أولًا');\n"
        "                  return;\n"
        "                }\n"
        "                state.addTextLayer(\n"
        "                    TextLayer(text: txt, position: "
        "_newLayerPosition));\n"
        "                _newLayerCtrl.clear();\n"
        "                setState(() {});\n"
        "              },\n"
        "              icon: const Icon(Icons.add_box_outlined, size: 18),\n"
        "              label: const Text('إضافة طبقة نص'),\n"
        "            ),\n"
        "            if (state.textLayers.isNotEmpty) ...[\n"
        "              const SizedBox(height: 12),\n"
        "              for (var i = 0; i < state.textLayers.length; i++)\n"
        "                Padding(\n"
        "                  padding: const EdgeInsets.only(bottom: 6),\n"
        "                  child: Container(\n"
        "                    padding: const EdgeInsets.symmetric(\n"
        "                        horizontal: 10, vertical: 8),\n"
        "                    decoration: BoxDecoration(\n"
        "                      border: Border.all(color: "
        "AyatColors.hairline),\n"
        "                      borderRadius: BorderRadius.circular(10),\n"
        "                    ),\n"
        "                    child: Row(children: [\n"
        "                      Expanded(\n"
        "                        child: Text(\n"
        "                          state.textLayers[i].text,\n"
        "                          maxLines: 1,\n"
        "                          overflow: TextOverflow.ellipsis,\n"
        "                          textDirection: TextDirection.rtl,\n"
        "                        ),\n"
        "                      ),\n"
        "                      IconButton(\n"
        "                        tooltip: 'حذف الطبقة',\n"
        "                        icon: const Icon(Icons.delete_outline, "
        "size: 20),\n"
        "                        onPressed: () => "
        "state.removeTextLayerAt(i),\n"
        "                      ),\n"
        "                    ]),\n"
        "                  ),\n"
        "                ),\n"
        "            ],\n"
        "          ],\n"
        "        )),\n"
    )
    apply_literal(HOME_SCREEN, old_card_tail, new_card_tail,
                  "home_screen.dart: add the 'طبقات نص ثابتة' card",
                  skip_if="طبقات نص ثابتة")


def main():
    patch_studio_state()
    patch_overlay_renderer()
    patch_export_service()
    patch_stage_preview()
    patch_home_screen()

    print("\n=== S143 text-layers patch ledger ===")
    for label, status in LEDGER:
        print(f"[{status}] {label}")
    print("======================================\n")


if __name__ == "__main__":
    main()
