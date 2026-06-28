/// Platform abstraction. Implementing a new platform (iOS, web, macOS, windows)
/// is "add a [PlatformGenerator]" — nothing in the Android path hard-codes a
/// platform assumption, which keeps the other gates open by design.
library;

/// Contract for a per-platform asset generator (Android, iOS, web, ...).
abstract class PlatformGenerator {
  /// Human-readable platform name (e.g. "Android").
  String get name;

  /// Runs generation and returns a report of what happened.
  GenerationReport generate();
}

/// Accumulates the outcome of a generation run.
class GenerationReport {
  /// Paths of files written during the run.
  final List<String> written = [];

  /// Messages describing optional assets that were skipped.
  final List<String> skipped = [];

  /// Non-fatal warnings emitted during the run.
  final List<String> warnings = [];

  /// Stale files deleted so they don't shadow what we just wrote (e.g. a
  /// density PNG that would override a freshly generated vector drawable).
  final List<String> removed = [];

  /// True when nothing was written, skipped, warned, or removed.
  bool get isEmpty =>
      written.isEmpty && skipped.isEmpty && warnings.isEmpty && removed.isEmpty;

  /// Appends all entries from [other] into this report.
  void merge(GenerationReport other) {
    written.addAll(other.written);
    skipped.addAll(other.skipped);
    warnings.addAll(other.warnings);
    removed.addAll(other.removed);
  }
}
