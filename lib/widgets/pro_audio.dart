// PATCH_S195_AUDIO_TAB
// The Audio tab («الأصوات»).
//   AudioLayer        - invisible: plays the sounds in step with the main clip,
//                       with their volume and fades, so the preview sounds like
//                       the export.
//   ProAudioClipsPage - the tool panel (add music / a sound / the sound of a
//                       video, volume, fades, loop, mute, timing, cut, copy).
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:video_player/video_player.dart';

import '../models/audio_clip.dart';
import '../models/studio_state.dart';
import '../theme/ayat_theme.dart';
import 'gold_switch.dart';
import 'motion.dart';

// ------------------------------------------------------------ preview player

class AudioLayer extends StatefulWidget {
  final StudioState state;
  final VideoPlayerController? main;
  const AudioLayer({super.key, required this.state, required this.main});

  @override
  State<AudioLayer> createState() => _AudioLayerState();
}

class _AudioLayerState extends State<AudioLayer> {
  final Map<int, VideoPlayerController> _ctl = {};
  final Map<int, String> _ctlPath = {};
  final Set<int> _booting = {};
  final Map<int, int> _seekAtUs = {};
  final Map<int, double> _lastVol = {};
  final Map<int, bool> _looping = {};
  final Stopwatch _sw = Stopwatch()..start();
  Timer? _timer;
  double _lastPos = -1;
  int _lastAtUs = 0;
  StudioState? _hookedState;

  @override
  void initState() {
    super.initState();
    _hook();
    _reconcile();
    _timer = Timer.periodic(
        const Duration(milliseconds: 90), (_) => _syncAll());
  }

  @override
  void didUpdateWidget(covariant AudioLayer old) {
    super.didUpdateWidget(old);
    _hook();
    _reconcile();
  }

  void _hook() {
    if (_hookedState != widget.state) {
      _hookedState?.removeListener(_onState);
      _hookedState = widget.state;
      widget.state.addListener(_onState);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _hookedState?.removeListener(_onState);
    for (final c in _ctl.values) {
      c.dispose();
    }
    _ctl.clear();
    super.dispose();
  }

  void _onState() {
    if (!mounted) return;
    _reconcile();
    _syncAll();
  }

  // ---------------------------------------------------------- controllers

  void _reconcile() {
    final want = <int, AudioClip>{
      for (final c in widget.state.audioClips) c.id: c
    };
    for (final id in _ctl.keys.toList()) {
      final w = want[id];
      if (w == null || _ctlPath[id] != w.path) {
        _ctl.remove(id)?.dispose();
        _ctlPath.remove(id);
        _seekAtUs.remove(id);
        _lastVol.remove(id);
        _looping.remove(id);
      }
    }
    for (final c in want.values) {
      if (_ctl.containsKey(c.id) || _booting.contains(c.id)) continue;
      _boot(c);
    }
  }

  Future<void> _boot(AudioClip c) async {
    _booting.add(c.id);
    final vc = VideoPlayerController.file(File(c.path),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
    try {
      await vc.initialize();
      await vc.setVolume(0);
      await vc.setLooping(c.loop);
    } catch (_) {
      _booting.remove(c.id);
      await vc.dispose();
      return;
    }
    _booting.remove(c.id);
    final stillThere = widget.state.audioClips.any((e) => e.id == c.id);
    if (!mounted || !stillThere) {
      await vc.dispose();
      return;
    }
    _ctl[c.id] = vc;
    _ctlPath[c.id] = c.path;
    _looping[c.id] = c.loop;
    _syncAll();
  }

  // ----------------------------------------------------------------- time

  /// The player reports its position a few times a second; between two
  /// reports the time is extrapolated so the sounds stay in step.
  double _now() {
    final m = widget.main;
    if (m == null || !m.value.isInitialized) return 0;
    final v = m.value;
    final p = v.position.inMicroseconds / 1000000.0;
    if (p != _lastPos) {
      _lastPos = p;
      _lastAtUs = _sw.elapsedMicroseconds;
    }
    if (!v.isPlaying) return p;
    final el =
        (_sw.elapsedMicroseconds - _lastAtUs) / 1000000.0 * v.playbackSpeed;
    return p + (el < 0 ? 0.0 : (el > 0.6 ? 0.6 : el));
  }

  void _seek(VideoPlayerController vc, int id, double sec, int nowUs) {
    _seekAtUs[id] = nowUs;
    vc.seekTo(Duration(milliseconds: (sec * 1000).round()));
  }

  /// Keeps every sound in step with the main clip.
  void _syncAll() {
    if (!mounted) return;
    final m = widget.main;
    if (m == null || !m.value.isInitialized) return;
    final st = widget.state;
    final playing = m.value.isPlaying;
    final speed = m.value.playbackSpeed;
    final t = _now();
    final nowUs = _sw.elapsedMicroseconds;
    for (final c in st.audioClips) {
      final vc = _ctl[c.id];
      if (vc == null || !vc.value.isInitialized) continue;

      // volume follows the fades; the preview tops out at 100 %
      final silent = st.muteAudio || c.muted;
      final g = silent ? 0.0 : c.gainAt(t).clamp(0.0, 1.0).toDouble();
      final last = _lastVol[c.id];
      if (last == null || (last - g).abs() > 0.015) {
        _lastVol[c.id] = g;
        vc.setVolume(g);
      }
      if (_looping[c.id] != c.loop) {
        _looping[c.id] = c.loop;
        vc.setLooping(c.loop);
      }

      final shouldPlay = playing && !silent && c.playsAt(t);
      if (!shouldPlay) {
        if (vc.value.isPlaying) vc.pause();
        continue;
      }
      if ((vc.value.playbackSpeed - speed).abs() > 0.01) {
        vc.setPlaybackSpeed(speed);
      }
      final dur = vc.value.duration.inMilliseconds / 1000.0;
      final want = c.mediaTimeAt(t);
      final cur = vc.value.position.inMilliseconds / 1000.0;
      var diff = (cur - want).abs();
      if (c.loop && dur > 0.05 && dur - diff < diff) diff = dur - diff;
      final since = nowUs - (_seekAtUs[c.id] ?? -1000000000);
      if (!vc.value.isPlaying) {
        _seek(vc, c.id, want, nowUs);
        vc.play();
      } else if (diff > 0.35 && since > 500000) {
        _seek(vc, c.id, want, nowUs);
      }
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

// ------------------------------------------------------------------- panel

class ProAudioClipsPage extends StatelessWidget {
  final StudioState state;
  final VideoPlayerController? controller;
  final VoidCallback onAddAudio;
  final VoidCallback onAddFromVideo;
  final void Function(String) onToast;
  const ProAudioClipsPage({
    super.key,
    required this.state,
    required this.controller,
    required this.onAddAudio,
    required this.onAddFromVideo,
    required this.onToast,
  });

  double _t() => controller == null
      ? 0.0
      : controller!.value.position.inMilliseconds / 1000.0;

  static IconData _kindIcon(AudioKind k) => switch (k) {
        AudioKind.music => Icons.music_note,
        AudioKind.effect => Icons.surround_sound_outlined,
        AudioKind.voice => Icons.mic_none,
        AudioKind.extracted => Icons.movie_outlined,
      };

  Widget _title(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 14,
              decoration: BoxDecoration(
                color: AyatColors.goldBright,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 8),
            Text(text, style: Theme.of(context).textTheme.labelLarge),
          ],
        ),
      );

  Widget _slider({
    required String label,
    required String shown,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(label,
              style: const TextStyle(fontSize: 12, color: AyatColors.parchment)),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max).toDouble(),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 46,
          child: Text(shown,
              textAlign: TextAlign.end,
              style: const TextStyle(
                  fontSize: 11.5, color: AyatColors.parchmentDim)),
        ),
      ],
    );
  }

  Widget _btn(IconData icon, String label, VoidCallback onTap,
      {bool gold = false}) {
    return PressableScale(
      borderRadius: BorderRadius.circular(12),
      pressedScale: 0.92,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: gold ? AyatColors.gold.withValues(alpha: 0.22) : AyatColors.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: gold ? AyatColors.goldBright : AyatColors.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 17,
                color: gold ? AyatColors.goldBright : AyatColors.parchmentDim),
            const SizedBox(width: 6),
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: gold ? AyatColors.goldBright : AyatColors.parchment)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _switchRow(String label, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12.5, color: AyatColors.parchment)),
          ),
          GoldSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  void _listen(AudioClip c) {
    final v = controller;
    if (v == null || !v.value.isInitialized) return;
    final from = math.max(0.0, c.start - 0.3);
    v.seekTo(Duration(milliseconds: (from * 1000).round())).then((_) => v.play());
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final sel = state.selectedAudio;
        final i = state.audioSel;
        final total = state.videoDurationSec > 0
            ? state.videoDurationSec
            : math.max(10.0, sel == null ? 10.0 : sel.end + 2);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                    child: _btn(Icons.library_music_outlined,
                        'موسيقى أو صوت', onAddAudio,
                        gold: true)),
                const SizedBox(width: 10),
                Expanded(
                    child: _btn(Icons.movie_outlined, 'صوت من فيديو',
                        onAddFromVideo,
                        gold: true)),
              ],
            ),
            if (state.audioClips.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 14, 4, 6),
                child: Text(
                  'أضف موسيقى أو مؤثرًا صوتيًا أو صوت فيديو آخر — يظهر على المخطط '
                  'الزمني في مسار «الأصوات»، فاسحبه لتحريكه، واسحب حافتيه للقص، '
                  'ويُمزج مع صوت المقطع والتلاوة في الفيديو المُصدَّر.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12.5,
                      height: 1.6,
                      color: AyatColors.parchmentDim),
                ),
              ),
            if (state.audioClips.isNotEmpty) ...[
              _title(context, 'الأصوات (${state.audioClips.length})'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var k = 0; k < state.audioClips.length; k++)
                    ChoiceChip(
                      avatar: Icon(_kindIcon(state.audioClips[k].kind), size: 16),
                      label: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 130),
                        child: Text(state.audioClips[k].name,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      selected: k == i,
                      onSelected: (_) {
                        state.selectAudio(k);
                        controller?.seekTo(Duration(
                            milliseconds:
                                (state.audioClips[k].start * 1000).round()));
                      },
                    ),
                ],
              ),
            ],
            if (sel != null) ...[
              _title(context, 'النوع'),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final k in AudioKind.values)
                    ChoiceChip(
                      avatar: Icon(_kindIcon(k), size: 16),
                      label: Text(audioKindLabel(k)),
                      selected: sel.kind == k,
                      onSelected: (_) => state.update(() => sel.kind = k),
                    ),
                ],
              ),
              _title(context, 'مستوى الصوت'),
              _slider(
                label: 'الصوت',
                shown: '${(sel.volume * 100).round()}%',
                value: sel.volume,
                min: 0,
                max: kAudioMaxVol,
                onChanged: (v) => state.update(() =>
                    sel.volume = (v - 1).abs() < 0.03 ? 1.0 : v),
              ),
              if (sel.volume > 1.001)
                const Padding(
                  padding: EdgeInsets.only(bottom: 2),
                  child: Text(
                    'فوق ١٠٠٪ يُسمع التكبير في الفيديو المُصدَّر فقط.',
                    style: TextStyle(
                        fontSize: 11.5, color: AyatColors.parchmentDim),
                  ),
                ),
              _slider(
                label: 'دخول',
                shown: '${sel.fadeIn.toStringAsFixed(1)} ث',
                value: sel.fadeIn,
                min: 0,
                max: math.max(0.2, math.min(5.0, sel.length / 2)),
                onChanged: (v) => state.update(
                    () => sel.fadeIn = (v * 10).round() / 10.0),
              ),
              _slider(
                label: 'خروج',
                shown: '${sel.fadeOut.toStringAsFixed(1)} ث',
                value: sel.fadeOut,
                min: 0,
                max: math.max(0.2, math.min(5.0, sel.length / 2)),
                onChanged: (v) => state.update(
                    () => sel.fadeOut = (v * 10).round() / 10.0),
              ),
              _switchRow('تكرار الصوت إن كان أقصر من مدّته', sel.loop,
                  (v) => state.update(() => sel.loop = v)),
              _switchRow('كتم هذا الصوت', sel.muted,
                  (v) => state.update(() => sel.muted = v)),
              _title(context, 'التوقيت'),
              _slider(
                label: 'البداية',
                shown: '${sel.start.toStringAsFixed(1)} ث',
                value: sel.start,
                min: 0,
                max: total,
                onChanged: (v) {
                  state.pushHistory();
                  state.setAudioWindow(i, start: (v * 10).round() / 10.0);
                },
              ),
              _slider(
                label: 'النهاية',
                shown: '${sel.end.toStringAsFixed(1)} ث',
                value: sel.end,
                min: 0,
                max: total,
                onChanged: (v) {
                  state.pushHistory();
                  state.setAudioWindow(i, end: (v * 10).round() / 10.0);
                },
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _btn(Icons.first_page, 'ابدأ هنا', () {
                    state.pushHistory();
                    state.setAudioWindow(i, start: _t());
                  }),
                  _btn(Icons.last_page, 'انتهِ هنا', () {
                    state.pushHistory();
                    state.setAudioWindow(i, end: _t());
                  }),
                  _btn(Icons.fit_screen_outlined, 'حتى نهاية المقطع', () {
                    final d = state.videoDurationSec;
                    if (d <= 0) return;
                    state.pushHistory();
                    state.setAudioWindow(i, end: d);
                  }),
                ],
              ),
              _title(context, 'إجراءات'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _btn(Icons.play_circle_outline, 'استمع', () => _listen(sel),
                      gold: true),
                  _btn(Icons.content_cut, 'تقسيم', () {
                    if (state.splitAudioAt(i, _t())) {
                      HapticFeedback.mediumImpact();
                    } else {
                      onToast('ضع المؤشر داخل الصوت ثم قسّم');
                    }
                  }),
                  _btn(Icons.content_copy, 'نسخ', () {
                    state.duplicateAudioAt(i);
                    onToast('تم النسخ');
                  }),
                  _btn(Icons.restart_alt, 'إعادة الضبط', () {
                    state.update(() {
                      sel.volume = 1.0;
                      sel.fadeIn = 0.0;
                      sel.fadeOut = 0.0;
                      sel.loop = false;
                      sel.muted = false;
                    });
                  }),
                  _btn(Icons.delete_outline, 'حذف', () {
                    state.removeAudioAt(i);
                  }),
                ],
              ),
            ],
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'صوت المقطع والتلاوة والخلفية الصوتية تبقى في أداة «الصوت» — '
                'هنا الأصوات التي تضعها بنفسك فوقها على المخطط الزمني.',
                style: TextStyle(
                    fontSize: 11.5, height: 1.5, color: AyatColors.parchmentDim),
              ),
            ),
          ],
        );
      },
    );
  }
}
