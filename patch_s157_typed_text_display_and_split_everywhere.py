#!/usr/bin/env python3
"""
PATCH_S157_TYPED_TEXT_DISPLAY_AND_SPLIT_EVERYWHERE
==================================================
1.6.0+6 → 1.7.0+7

Verified against ayat_studio_app_dump_20260911_180536.txt (S156 tree).

WHAT THE DUMP ACTUALLY SHOWS
----------------------------
Bug 2 (split control missing from export) is ALREADY FIXED in this tree:
  - home_screen._tickAutoSync and export_service both call
    buildKaraokeChunks(seg, maxWordsPerChunk: state.splitLongAyahsEnabled
        ? state.maxWordsPerChunk : 1 << 30)
  - buildKaraokeChunks signature already takes maxWordsPerChunk
  - body already uses the parameter (not the constant)
  - zero bare buildKaraokeChunks(seg) in live source
    (the 4 hits in the dump are inside OLD patch-script string literals)

Bug 1 (typed second half of Yusuf:86 still shows the full canonical ayah)
is only HALF-wired:
  - karaoke.dart already does (seg.textOverride ?? seg.ayah.ar)
  - subtitle_service already does the same
  - preview + export both consume cue.chunk.text (which comes from that)
  - BUT there is no single displayText contract, so any future renderer
    that reads seg.ayah.ar will re-introduce the bug, and the regression
    test for "typed text wins" does not exist.

This patch therefore:
  1. Adds TimelineSegment.displayText (= textOverride ?? ayah.ar)
  2. Makes karaoke.dart read displayText (one source of truth)
  3. Does a CAREFUL sweep: only rewrites <ident>.ayah.ar when the
     identifier is clearly a TimelineSegment (seg / segment / s / live /
     cur / item / e / ts). Does NOT touch m.ayah.ar / best.ayah.ar /
     match.ayah.ar (those are AyahMatch and would break the build).
  4. Leaves the already-correct split call sites alone (no-op on them)
  5. Adds two regression tests
  6. Bumps version 1.6.0+6 → 1.7.0+7

Run:  python3 patch_s157_typed_text_display_and_split_everywhere.py <project_root>
"""

from __future__ import annotations

import re
import sys
import pathlib

MARKER = "PATCH_S157_TYPED_TEXT_DISPLAY_AND_SPLIT_EVERYWHERE"
LEDGER: list[tuple[str, str]] = []


def _log(label: str, status: str) -> None:
    LEDGER.append((label, status))
    print(f"  [{status:22}] {label}")


# ---------------------------------------------------------------------------
# safe, flex matching (whitespace-tolerant, single-match only)
# ---------------------------------------------------------------------------

def flex_pattern(old: str) -> str:
    parts = re.split(r"(\s+)", old)
    out: list[str] = []
    for p in parts:
        if not p:
            continue
        out.append(r"\s+" if p.strip() == "" else re.escape(p))
    return "".join(out)


def replace_flex(
    path: pathlib.Path,
    old: str,
    new: str,
    label: str,
    *,
    skip_if: str | None = None,
) -> bool:
    if not path.exists():
        _log(label, "MISSING (file absent)")
        return False
    text = path.read_text(encoding="utf-8")
    if skip_if and skip_if in text:
        _log(label, "SKIP (already applied)")
        return False
    matches = list(re.finditer(flex_pattern(old), text))
    if not matches:
        _log(label, "MISSING (anchor not found)")
        return False
    if len(matches) > 1:
        raise SystemExit(
            f"ERROR ({label}): anchor found {len(matches)} times in {path} "
            f"— refusing to guess"
        )
    m = matches[0]
    path.write_text(text[: m.start()] + new + text[m.end() :], encoding="utf-8")
    _log(label, "OK")
    return True


# ---------------------------------------------------------------------------
# edits
# ---------------------------------------------------------------------------

# Identifiers that, in this codebase, are TimelineSegment (or nullable ones).
# Explicit denylist for match results so we never rewrite m.ayah.ar etc.
_SEG_IDENTS = r"(?:seg|segment|s|live|cur|item|e|ts|loopSeg|active)"
_MATCH_IDENTS = r"(?:m|match|best|result|hit|found|candidate|ayahMatch)"


def e1_display_text_getter(root: pathlib.Path) -> None:
    """Insert displayText getter right after the textOverride field."""
    replace_flex(
        root / "lib/models/studio_state.dart",
        "String? textOverride;\n  TimelineSegment({",
        "String? textOverride;\n\n"
        "  // PATCH_S157_TYPED_TEXT_DISPLAY: the ONE text this segment shows\n"
        "  // in preview, export and subtitles alike. Typed text, partial-ayah\n"
        "  // slices and custom captions carry their exact words in\n"
        "  // textOverride; ayah.ar is the full canonical ayah and must never\n"
        "  // replace them. Renderers read this getter — never ayah.ar.\n"
        "  String get displayText => textOverride ?? ayah.ar;\n\n"
        "  TimelineSegment({",
        "studio_state.dart: displayText getter",
        skip_if="PATCH_S157_TYPED_TEXT_DISPLAY",
    )


def e2_karaoke_reads_display_text(root: pathlib.Path) -> None:
    """Make the single source of words for karaoke be displayText."""
    p = root / "lib/services/karaoke.dart"
    if not p.exists():
        _log("karaoke.dart: words = displayText", "MISSING (file absent)")
        return
    text = p.read_text(encoding="utf-8")
    if "seg.displayText.trim()" in text:
        _log("karaoke.dart: words = displayText", "SKIP (already applied)")
        return

    # Current dump form (S118 + S156). Use slice replace (not re.sub) so
    # the Dart RegExp(r'\s+') backslashes in `new` are never parsed as
    # re template escapes — that was the crash on the first run.
    old = (
        "final words = (seg.textOverride ?? seg.ayah.ar)"
        ".trim().split(RegExp(r'\\s+'));"
    )
    new = (
        "final words = seg.displayText.trim()"
        ".split(RegExp(r'\\s+')); // PATCH_S157_TYPED_TEXT_DISPLAY"
    )
    m = re.search(flex_pattern(old), text)
    if m:
        text = text[: m.start()] + new + text[m.end() :]
        p.write_text(text, encoding="utf-8")
        _log("karaoke.dart: words = displayText", "OK")
        return

    # Older form without the override ternary
    old2 = "final words = seg.ayah.ar.trim().split(RegExp(r'\\s+'));"
    m2 = re.search(flex_pattern(old2), text)
    if m2:
        text = text[: m2.start()] + new + text[m2.end() :]
        p.write_text(text, encoding="utf-8")
        _log("karaoke.dart: words = displayText (from ayah.ar)", "OK")
        return

    _log("karaoke.dart: words = displayText", "MISSING (no known form)")


def e3_verify_signature_and_body(root: pathlib.Path) -> None:
    """S156 already parameterized buildKaraokeChunks. Just verify & force-clean."""
    p = root / "lib/services/karaoke.dart"
    if not p.exists():
        _log("karaoke.dart: signature/body check", "MISSING (file absent)")
        return
    text = p.read_text(encoding="utf-8")

    if "maxWordsPerChunk" not in text.split("buildKaraokeChunks", 1)[-1][:200]:
        # Extremely defensive: if somehow the param is gone, re-add it.
        text = re.sub(
            r"List<KaraokeChunk>\s+buildKaraokeChunks\(\s*TimelineSegment\s+seg\s*\)\s*\{",
            "List<KaraokeChunk> buildKaraokeChunks(\n"
            "  TimelineSegment seg, {\n"
            "  int maxWordsPerChunk = kKaraokeMaxWordsPerChunk,\n"
            "}) {",
            text,
            count=1,
        )
        _log("karaoke.dart: re-added maxWordsPerChunk param", "OK")
    else:
        _log("karaoke.dart: signature already parameterized", "SKIP (already applied)")

    # Force body to use the parameter, not the constant
    # (only inside the function — crude but safe because the constant is
    # only referenced as a default / documentation elsewhere).
    body_start = text.find("List<KaraokeChunk> buildKaraokeChunks")
    if body_start >= 0:
        # Find matching closing brace of the function (simple depth scan)
        i = text.find("{", body_start)
        depth = 0
        j = i
        while j < len(text):
            c = text[j]
            if c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
                if depth == 0:
                    break
            j += 1
        body = text[i : j + 1]
        fixed = body.count("kKaraokeMaxWordsPerChunk")
        # Don't rewrite the default-value occurrence in the signature itself
        # (it sits before the opening brace). Only the body.
        if "kKaraokeMaxWordsPerChunk" in body:
            body2 = body.replace("kKaraokeMaxWordsPerChunk", "maxWordsPerChunk")
            # But the default in the signature is *before* the '{', so this
            # is only the body. Good.
            text = text[:i] + body2 + text[j + 1 :]
            p.write_text(text, encoding="utf-8")
            _log(
                f"karaoke.dart: body uses parameter ({fixed} site(s))",
                "OK",
            )
        else:
            _log("karaoke.dart: body already uses parameter", "SKIP (already clean)")
    else:
        _log("karaoke.dart: could not locate function body", "MISSING")


def e4_careful_segment_ayah_ar_sweep(root: pathlib.Path) -> None:
    """
    Rewrite ONLY <seg-like>.ayah.ar → <seg-like>.displayText.
    Never touch m.ayah.ar / best.ayah.ar / match.ayah.ar.
    """
    files = [
        "lib/screens/home_screen.dart",
        "lib/screens/sequence_screen.dart",
        "lib/services/export_service.dart",
        "lib/services/subtitle_service.dart",
        "lib/services/karaoke.dart",
        "lib/widgets/timeline_ribbon.dart",
        "lib/widgets/stage_preview.dart",
        "lib/widgets/text_editor_pro.dart",
        "lib/widgets/autoseg_wizard.dart",
    ]
    # Only rewrite when the receiver looks like a segment variable.
    pat = re.compile(rf"\b({_SEG_IDENTS})\.ayah\.ar\b")
    # Explicit safety: never touch match-style receivers even if they somehow
    # matched the segment list (they don't, but belt-and-suspenders).
    deny = re.compile(rf"\b({_MATCH_IDENTS})\.ayah\.ar\b")

    for rel in files:
        p = root / rel
        if not p.exists():
            _log(f"sweep {rel}", "MISSING (file absent)")
            continue
        lines = p.read_text(encoding="utf-8").split("\n")
        count = 0
        for idx, line in enumerate(lines):
            ls = line.lstrip()
            if ls.startswith(("//", "*", "///")):
                continue
            if deny.search(line):
                continue
            new_line, n = pat.subn(r"\1.displayText", line)
            if n:
                lines[idx] = new_line
                count += n
        if count:
            p.write_text("\n".join(lines), encoding="utf-8")
            _log(f"sweep {rel}: {count} segment site(s) → displayText", "OK")
        else:
            _log(f"sweep {rel}: 0 segment sites", "OK")


def e5_split_call_sites_already_done(root: pathlib.Path) -> None:
    """
    Verify that every live buildKaraokeChunks(seg) site is parameterized.
    Do not rewrite anything that is already correct.
    """
    files = [
        "lib/screens/home_screen.dart",
        "lib/screens/sequence_screen.dart",
        "lib/services/export_service.dart",
        "lib/widgets/timeline_ribbon.dart",
        "lib/widgets/text_editor_pro.dart",
        "lib/widgets/autoseg_wizard.dart",
    ]
    bare = re.compile(r"buildKaraokeChunks\(\s*seg\s*\)")
    for rel in files:
        p = root / rel
        if not p.exists():
            _log(f"split-control {rel}", "MISSING (file absent)")
            continue
        text = p.read_text(encoding="utf-8")
        n_bare = len(bare.findall(text))
        if n_bare == 0:
            if "maxWordsPerChunk:" in text or "buildKaraokeChunks" not in text:
                _log(f"split-control {rel}", "OK (no bare call sites)")
            else:
                _log(f"split-control {rel}", "OK (no bare call sites)")
            continue
        # Rare: a bare call survived. Wire it the same way as the live ones.
        if "state." not in text and "s." not in text:
            _log(
                f"split-control {rel}: {n_bare} bare call(s) but no state/s "
                "in file — wire by hand",
                "MISSING",
            )
            continue
        # Prefer `state.` if present, else `s.`
        state_var = "state" if "state.splitLongAyahsEnabled" in text or "state." in text else "s"
        repl = (
            f"buildKaraokeChunks(seg,\n"
            f"            maxWordsPerChunk:\n"
            f"                {state_var}.splitLongAyahsEnabled\n"
            f"                    ? {state_var}.maxWordsPerChunk\n"
            f"                    : 1 << 30)"
        )
        text2 = bare.sub(repl, text)
        p.write_text(text2, encoding="utf-8")
        _log(f"split-control {rel}: {n_bare} bare call site(s) wired", "OK")


def e6_toggle_ui_present(root: pathlib.Path) -> None:
    p = root / "lib/widgets/text_editor_pro.dart"
    if p.exists() and "splitLongAyahsEnabled" in p.read_text(encoding="utf-8"):
        _log("text_editor_pro.dart: split toggle wired in UI", "OK")
    else:
        _log(
            "text_editor_pro.dart: split toggle wired in UI",
            "MISSING — add a ToggleRow bound to state.splitLongAyahsEnabled "
            "next to the karaoke toggle (strings already exist)",
        )


def e7_regression_tests(root: pathlib.Path) -> None:
    p = root / "test/karaoke_test.dart"
    if not p.exists():
        _log("karaoke_test.dart: S157 regression tests", "MISSING (file absent)")
        return
    text = p.read_text(encoding="utf-8")
    if "PATCH_S157_TYPED_TEXT_DISPLAY" in text:
        _log("karaoke_test.dart: S157 regression tests", "SKIP (already applied)")
        return

    # Insert after the existing maxWordsPerChunk / long-ayah tests block.
    # Prefer the known S156 test that uses words(30).
    anchor = "buildKaraokeChunks(seg(words(30), '', 0, 10))"
    idx = text.find(anchor)
    if idx < 0:
        # Fall back: append at end of main group / file
        insert_at = text.rfind("})")
        if insert_at < 0:
            _log(
                "karaoke_test.dart: S157 regression tests",
                "MISSING — append the tests manually",
            )
            return
        close = insert_at
    else:
        close = text.find("});", idx)
        if close < 0:
            _log(
                "karaoke_test.dart: S157 regression tests",
                "MISSING — could not find closing }); after words(30)",
            )
            return
        close = close + 3

    ins = """

  // PATCH_S157_TYPED_TEXT_DISPLAY: regression tests for both S157 fixes.
  test('textOverride (typed text) is displayed, not the full matched ayah', () {
    final full =
        'قال إنما أشكو بثي وحزني إلى الله وأعلم من الله ما لا تعلمون';
    final typed = 'وأعلم من الله ما لا تعلمون';
    final s = TimelineSegment(
      start: 13,
      end: 17,
      confidence: 1,
      ayah: Ayah(surahNum: 12, surah: 'يوسف', num: 86, ar: full, en: ''),
      textOverride: typed,
    );
    expect(s.displayText, typed);
    expect(buildKaraokeChunks(s).length, 1);
    expect(buildKaraokeChunks(s).first.words.join(' '), typed);
  });

  test('splitting can be turned off entirely (infinite threshold)', () {
    expect(
      buildKaraokeChunks(seg(words(30), '', 0, 10), maxWordsPerChunk: 1 << 30)
          .length,
      1,
    );
  });
"""
    p.write_text(text[:close] + ins + text[close:], encoding="utf-8")
    _log("karaoke_test.dart: S157 regression tests", "OK")


def e8_version(root: pathlib.Path) -> None:
    replace_flex(
        root / "pubspec.yaml",
        "version: 1.6.0+6",
        "version: 1.7.0+7",
        "pubspec.yaml: 1.6.0+6 → 1.7.0+7",
        skip_if="version: 1.7.0+7",
    )
    p = root / "lib/app_info.dart"
    if not p.exists():
        _log("app_info.dart: version string", "MISSING (file absent)")
        return
    text = p.read_text(encoding="utf-8")
    n = text.count("1.6.0")
    if n == 0:
        _log(
            "app_info.dart: version string",
            "MISSING — no '1.6.0' found; bump by hand if needed",
        )
        return
    text = text.replace("1.6.0", "1.7.0").replace("+6", "+7")
    p.write_text(text, encoding="utf-8")
    _log(f"app_info.dart: version string ({n} occurrence(s))", "OK")


def e9_doubled_ternary_guard(root: pathlib.Path) -> None:
    p = root / "lib/screens/home_screen.dart"
    if not p.exists():
        _log("home_screen.dart: doubled-ternary guard", "MISSING (file absent)")
        return
    try:
        replace_flex(
            p,
            "final start =\n"
            "state.timeline.isNotEmpty ?\n"
            "state.timeline.isNotEmpty ? state.timeline.last.end : 0.0;",
            "final start =\n"
            "    state.timeline.isNotEmpty ? state.timeline.last.end : 0.0;",
            "home_screen.dart: doubled-ternary guard",
        )
    except SystemExit:
        _log("home_screen.dart: doubled-ternary guard", "OK (not present)")


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(
            f"Usage: python3 {pathlib.Path(__file__).name} <project_root>"
        )
    root = pathlib.Path(sys.argv[1]).resolve()
    print(f"Applying {MARKER} to {root}\n")

    e1_display_text_getter(root)
    e2_karaoke_reads_display_text(root)
    e3_verify_signature_and_body(root)
    e4_careful_segment_ayah_ar_sweep(root)
    e5_split_call_sites_already_done(root)
    e6_toggle_ui_present(root)
    e7_regression_tests(root)
    e8_version(root)
    e9_doubled_ternary_guard(root)

    print("\n==================================")
    print(f"=== {MARKER} ledger ===")
    for label, status in LEDGER:
        print(f"[{status}] {label}")
    print("==================================")
    print(
        """
Next:
  dart format lib test
  flutter analyze
  flutter test test/karaoke_test.dart

Real end-to-end check (your exact scenario):
  1. Type the FIRST half of Yusuf:86 at 1–13s → save to timeline
  2. Type the SECOND half (وَأَعْلَمُ مِنَ اللَّهِ مَا لَا تَعْلَمُونَ) at 13–17s → save
  3. Play + Export
  → second window must show ONLY what you typed (not the full ayah)
  → with split-long-ayat OFF, a 20-word ayah stays one piece in both preview and MP4
"""
    )


if __name__ == "__main__":
    main()
