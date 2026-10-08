// PATCH_S181_CLIPTOUCH
// One-at-a-time queue for the heavy background jobs that start right after a
// big file is opened (waveform decode, filmstrip). Running them side by side,
// right while the player is starting, is what made the editor stutter for a
// while after an upload and then "become normal".
class HeavyGate {
  HeavyGate._();

  static Future<void> _tail = Future<void>.value();

  /// Runs [job] after every job queued before it has finished, and after a
  /// short pause so the first frames of the player are not competing with it.
  static Future<T> run<T>(Future<T> Function() job) {
    final Future<T> done = _tail
        .then<void>((_) => Future<void>.delayed(const Duration(milliseconds: 350)))
        .then<T>((_) => job());
    _tail = done.then<void>((_) {}, onError: (Object _) {});
    return done;
  }
}
