// PATCH_S129_QURAN_CAPTION_PARITY
// Centralised detection of the two formulaic openings that appear in almost
// every recitation but are NOT ayat of the corpus the matcher scores against.
//
// Treating them as ordinary ASR windows produces either a false match on
// الفاتحة:1 or a "no match" refusal; both look like bugs to the user.
// Callers that want special UI (non-ayah card, skip, or a fixed Bismillah
// plate) import these helpers instead of inventing their own regexes.

/// True when [text] (already stripped of tashkeel is fine) is a Basmala.
bool isBasmala(String text) {
  final t = text
      .replaceAll(RegExp(r'[ً-ٰٟۖ-ۭـ\s]+'), '')
      .replaceAll('أ', 'ا')
      .replaceAll('إ', 'ا')
      .replaceAll('آ', 'ا');
  // Core tokens that survive every common Whisper corruption of the formula.
  return t.contains('بسمالله') ||
      t.contains('بسمالل') ||
      (t.contains('بسم') && t.contains('الرحمن') && t.contains('الرحيم'));
}

/// True when [text] is an Istiʿādha (أعوذ بالله من الشيطان الرجيم and variants).
bool isIstiatha(String text) {
  final t = text
      .replaceAll(RegExp(r'[ً-ٰٟۖ-ۭـ\s]+'), '')
      .replaceAll('أ', 'ا')
      .replaceAll('إ', 'ا')
      .replaceAll('آ', 'ا');
  return (t.contains('اعوذ') || t.contains('اعوذبالله') || t.contains('عاذ')) &&
      (t.contains('شيطان') || t.contains('الشيطان'));
}

/// True when the window should be treated as a non-ayah formula rather than
/// forced through AyahMatcher.
bool isNonAyahFormula(String text) => isBasmala(text) || isIstiatha(text);
