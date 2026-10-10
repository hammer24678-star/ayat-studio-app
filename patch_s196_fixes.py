#!/usr/bin/env python3
"""patch_s196_fixes.py - run from the repo root, after S195.
 * export / auto-sync progress callbacks no longer call setState once the
   screen is gone (crash when leaving mid-job)
 * reciter preview: no setState / player creation after the screen is gone
 * pressing a long job while another runs now says so instead of doing nothing
"""
import os, sys
M = 'PATCH_S196_FIXES'
EDITS = {'lib/screens/home_screen.dart': [('        scanEnd: state.manualTrimSet ? state.trimManualEnd : null,\n        onStatus: (s) => _setBusyStatus(s),\n        onProgress: (f) {\n          BackgroundJob.update(null, f); // PATCH_S163\n          setState(() => _busyProgress = f);\n', '        scanEnd: state.manualTrimSet ? state.trimManualEnd : null,\n        onStatus: (s) => _setBusyStatus(s),\n        onProgress: (f) {\n          BackgroundJob.update(null, f); // PATCH_S163\n          if (!mounted) return; // PATCH_S196_FIXES\n          setState(() => _busyProgress = f);\n'), ('      return ExportService.export(\n        state: state,\n        onStatus: (s) => _setBusyStatus(s),\n        onProgress: (f) {\n          BackgroundJob.update(null, f); // PATCH_S163\n          setState(() => _busyProgress = f);\n', '      return ExportService.export(\n        state: state,\n        onStatus: (s) => _setBusyStatus(s),\n        onProgress: (f) {\n          BackgroundJob.update(null, f); // PATCH_S163\n          if (!mounted) return; // PATCH_S196_FIXES\n          setState(() => _busyProgress = f);\n'), ('      await _reciterPreview!.dispose();\n      setState(() {\n        _reciterPreview = null;', '      await _reciterPreview!.dispose();\n      if (!mounted) return; // PATCH_S196_FIXES\n      setState(() {\n        _reciterPreview = null;'), ('    await _reciterPreview?.dispose();\n    final c = VideoPlayerController.file(File(path));\n    setState(() {', '    await _reciterPreview?.dispose();\n    if (!mounted) return; // PATCH_S196_FIXES\n    final c = VideoPlayerController.file(File(path));\n    setState(() {'), ('    if (_busy) return null;\n    setState(() {\n      _busy = true;', "    if (_busy) {\n      _toast('هناك عملية جارية، انتظر حتى تنتهي'); // PATCH_S196_FIXES\n      return null;\n    }\n    setState(() {\n      _busy = true;")]}
bad = []
texts = {}
for p, eds in EDITS.items():
    if not os.path.exists(p):
        sys.exit('Run from the repo root (missing ' + p + ').')
    t = open(p, encoding='utf-8').read()
    if M in t:
        print('  OK      already applied'); sys.exit(0)
    texts[p] = t
    for old, new in eds:
        n = t.count(old)
        if n != 1:
            bad.append(p + ': ' + str(n) + ' match(es) for ' + repr(old[:60]))
if bad:
    sys.exit('Anchor check failed, nothing written:\n  ' + '\n  '.join(bad))
for p, eds in EDITS.items():
    t = texts[p]
    for old, new in eds:
        t = t.replace(old, new, 1)
    open(p, 'w', encoding='utf-8').write(t)
    print('  PATCHED', p, '(' + str(len(eds)) + ' edits)')
print('S196 applied. Next: git add -A && git commit -m "S196: lifecycle fixes" && git push')
