#!/usr/bin/env python3
"""
patch_s66c_tokenizer_from_openai_base.py

FIXES the "Prepare Quran-tuned Whisper model" workflow's run #2 failure:

    FATAL: merged-quran-model/ is still missing ['vocab.json', 'added_tokens.json']
    after saving both processor and slow tokenizer -- contents:
    ['processor_config.json', 'model.safetensors', 'config.json',
     'tokenizer_config.json', 'generation_config.json', 'tokenizer.json']

ROOT CAUSE (S66b's fix wasn't wrong, it just wasn't enough):
S66b's theory was correct -- WhisperProcessor's fast tokenizer doesn't
reliably emit legacy vocab.json/merges.txt -- but the fix (explicitly
loading `WhisperTokenizer`, the slow class, from `base_id` and saving
that instead) still produced no vocab.json. The listed output contents
prove why: tarteel-ai/whisper-base-ar-quran's own HF repo simply does not
host vocab.json/merges.txt/added_tokens.json at all -- only tokenizer.json
(the fast-tokenizer-only format). `WhisperTokenizer.from_pretrained()`
against a repo with no vocab_file/merges_file falls back to converting
the fast tokenizer.json in memory, and that converted object's
save_pretrained() doesn't reliably backfill the legacy files either --
there's simply no vocab.json anywhere upstream of tarteel-ai's repo to
copy.

THE FIX: don't ask tarteel-ai's repo for tokenizer files at all. Fine-
tuning Whisper (what both tarteel-ai's Quran fine-tune and KheemP's LoRA
adapter on top of it are) does not change the tokenizer/vocabulary --
every Whisper checkpoint of a given size shares the same BPE vocab as
OpenAI's original release. `openai/whisper-base` is the canonical HF
mirror of that original checkpoint and reliably ships the legacy
vocab.json/merges.txt/added_tokens.json files (this is the same source
whisper.cpp's own conversion docs/examples have used for years). So:
load the processor AND the slow tokenizer from `openai/whisper-base`
instead of `base_id` -- the merged model's weights are still 100% the
tarteel+LoRA merge from the previous step; only the tokenizer files
(which were never tarteel/LoRA-specific to begin with) now come from a
source that's guaranteed to actually have them.

WHAT THIS PATCH DOES:
  .github/workflows/prepare-quran-model.yml
    - processor + slow-tokenizer loads now point at 'openai/whisper-base'
      instead of `base_id` (tarteel-ai/whisper-base-ar-quran)
    - keeps S66b's existence check as a safety net

Usage:
  python3 patch_s66c_tokenizer_from_openai_base.py /path/to/ayat_studio_app
  (defaults to . if no path given)

After running: git add/commit/push (to BOTH claude/ai-quality-improvement-6t78zi
and main, same reason S66b called out -- the Actions tab only runs
workflow_dispatch definitions that exist on the default branch), then
re-run "Prepare Quran-tuned Whisper model (one-time / on-demand)" from the
Actions tab.
"""

import sys
import pathlib

MARKER = "PATCH_S66C_TOKENIZER_FROM_OPENAI_BASE"


def die(msg):
    print(f"ERROR: {msg}")
    sys.exit(1)


def replace_once(text, old, new, label):
    count = text.count(old)
    if count == 0:
        die(f"could not find anchor for [{label}] -- file may have changed since S66c was written.")
    if count > 1:
        die(f"anchor for [{label}] is not unique ({count} matches) -- refusing to guess, no changes made.")
    return text.replace(old, new, 1)


def patch_prepare_workflow(project_dir):
    target = project_dir / ".github" / "workflows" / "prepare-quran-model.yml"
    if not target.exists():
        die(f"{target} not found -- run patch_s66_quran_tuned_whisper_model.py first.")
    text = target.read_text()
    if MARKER in text:
        return False
    if "PATCH_S66B_VOCAB_JSON_FIX" not in text:
        die(f"{target} doesn't look like it has S66b's fix applied yet -- "
            "run patch_s66b_fix_vocab_json.py first, this patch builds on it.")

    old = (
        "          # convert-h5-to-ggml.py reads vocab.json/added_tokens.json directly out\n"
        "          # of dir_model. WhisperProcessor wraps a FAST tokenizer, whose\n"
        "          # save_pretrained() is not guaranteed to emit the legacy vocab.json/\n"
        "          # merges.txt/added_tokens.json files on current transformers versions --\n"
        "          # that's exactly what caused this job's original vocab.json\n"
        "          # FileNotFoundError. PATCH_S66B_VOCAB_JSON_FIX: also load + save the SLOW tokenizer,\n"
        "          # whose save_vocabulary() always dumps its BPE encoder straight to\n"
        "          # vocab.json, no ambiguity.\n"
        "          proc = WhisperProcessor.from_pretrained(base_id)\n"
        "          proc.save_pretrained(out_dir)\n"
        "\n"
        "          from transformers import WhisperTokenizer\n"
        "          slow_tok = WhisperTokenizer.from_pretrained(base_id)\n"
        "          slow_tok.save_pretrained(out_dir)\n"
        "\n"
        "          import os\n"
        "          required = [\"vocab.json\", \"added_tokens.json\", \"config.json\"]\n"
        "          missing = [f for f in required if not os.path.exists(os.path.join(out_dir, f))]\n"
        "          if missing:\n"
        "              raise SystemExit(\n"
        "                  f\"FATAL: {out_dir}/ is still missing {missing} after saving both \"\n"
        "                  f\"processor and slow tokenizer -- contents: {os.listdir(out_dir)}\"\n"
        "              )\n"
        "          print(f\"Merged model saved to {out_dir}/ (verified: {required} all present)\")\n"
        "          PY\n"
    )
    new = (
        "          # convert-h5-to-ggml.py reads vocab.json/added_tokens.json directly out\n"
        "          # of dir_model. PATCH_S66B_VOCAB_JSON_FIX's attempt (load the SLOW\n"
        "          # tokenizer from base_id) still came up empty: tarteel-ai's own repo\n"
        "          # simply doesn't host vocab.json/merges.txt/added_tokens.json at all,\n"
        f"          # only tokenizer.json (fast-only). {MARKER}: fine-tuning\n"
        "          # Whisper never changes its tokenizer/vocab, so pull the tokenizer\n"
        "          # files from openai/whisper-base instead -- the canonical HF mirror\n"
        "          # that reliably ships the legacy files -- while the model WEIGHTS\n"
        "          # loaded/merged above remain the tarteel+LoRA merge, untouched.\n"
        "          tok_source = \"openai/whisper-base\"\n"
        "          proc = WhisperProcessor.from_pretrained(tok_source)\n"
        "          proc.save_pretrained(out_dir)\n"
        "\n"
        "          from transformers import WhisperTokenizer\n"
        "          slow_tok = WhisperTokenizer.from_pretrained(tok_source)\n"
        "          slow_tok.save_pretrained(out_dir)\n"
        "\n"
        "          import os\n"
        "          required = [\"vocab.json\", \"added_tokens.json\", \"config.json\"]\n"
        "          missing = [f for f in required if not os.path.exists(os.path.join(out_dir, f))]\n"
        "          if missing:\n"
        "              raise SystemExit(\n"
        "                  f\"FATAL: {out_dir}/ is still missing {missing} after saving both \"\n"
        "                  f\"processor and slow tokenizer from {tok_source} -- contents: {os.listdir(out_dir)}\"\n"
        "              )\n"
        "          print(f\"Merged model saved to {out_dir}/ (verified: {required} all present)\")\n"
        "          PY\n"
    )
    text = replace_once(text, old, new, "prepare-quran-model.yml tokenizer source -> openai/whisper-base")

    target.write_text(text)
    return True


def main():
    project_dir = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    changed = patch_prepare_workflow(project_dir)
    print(f"{'OK: patched' if changed else 'SKIP: already applied'} .github/workflows/prepare-quran-model.yml")

    print()
    print("Next steps:")
    print("  git add .github/workflows/prepare-quran-model.yml")
    print("  git commit -m 'S66c: source tokenizer files from openai/whisper-base (tarteel repo lacks legacy vocab.json)'")
    print("  git push")
    print()
    print("Same reminder as S66b: this workflow file must be on the DEFAULT branch")
    print("(main) to be runnable from the Actions tab. Push/merge it onto main too,")
    print("not just claude/ai-quality-improvement-6t78zi.")
    print()
    print("Then re-run 'Prepare Quran-tuned Whisper model (one-time / on-demand)' from")
    print("the Actions tab. The merge step should now print '... all present)', and the")
    print("convert step should complete and publish ggml-quran-lora-base.bin to the")
    print("'models' release.")


if __name__ == "__main__":
    main()
