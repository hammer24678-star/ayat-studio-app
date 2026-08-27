// PATCH_S129B_FIX_BASMALA_RECOGNITION
// Detects the two opening formulas the caption/chapters pipeline must
// treat specially: a caption that is the basmala or the istiatha is not
// a recited ayah -- no ayah number, no chapter marker, no subtitle cue.
//
// S129 BUG FIXED HERE: the basmala constant used to carry tashkeel while
// callers pass plain text, so isBasmala() never matched (CI #137). Both
// sides now go through foldFormula() before comparison.

/// Strips tashkeel, Quranic annotation marks, tatweel; unifies alef/hamza/
/// wasla, ya and ta-marbuta; collapses whitespace -- the same discipline
/// AyahMatcher uses, so matcher-fed text and corpus text both match.
String foldFormula(String s) => s
    .replaceAll(RegExp('[\u064B-\u0652\u0653-\u065F\u0670\u0640\u06D6-\u06ED]'), '')
    .replaceAll(RegExp('[\u0671\u0622\u0623\u0625]'), '\u0627') // wasla/madda/hamza -> alef
    .replaceAll('\u0649', '\u064A') // ya
    .replaceAll('\u0629', '\u0647') // ta-marbuta
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

const kBasmalaFolded = 'بسم الله الرحمن الرحيم';
const kIstiathaFolded = 'اعوذ بالله من الشيطان الرجيم';

bool isBasmala(String text) {
  final t = foldFormula(text);
  return t == kBasmalaFolded || t.startsWith('$kBasmalaFolded ');
}

bool isIstiatha(String text) {
  final t = foldFormula(text);
  return t == kIstiathaFolded ||
      t.startsWith('$kIstiathaFolded ') ||
      t.startsWith('اعوذ بالله');
}

/// Either opening formula.
bool isQuranicFormula(String text) => isBasmala(text) || isIstiatha(text);
// PATCH_S129C_ADD_ISNONAYAHFORMULA: the caption-parity test (and the chapters pipeline) speak
// 'non-ayah formula' -- same rule, canonical name.
bool isNonAyahFormula(String text) => isBasmala(text) || isIstiatha(text);

