/// Platform abstraction. Implementing a new platform (iOS, web, macOS, windows)
/// is "add a [PlatformGenerator]" — nothing in the Android path hard-codes a
/// platform assumption, which keeps the other gates open by design.
library;

abstract class PlatformGenerator {
  /// Human-readable platform name (e.g. "Android").
  String get name;

  /// Runs generation and returns a report of what happened.
  GenerationReport generate();
}

/// Accumulates the outcome of a generation run.
class GenerationReport {
  final List<String> written = [];
  final List<String> skipped = [];
  final List<String> warnings = [];

  /// Stale files deleted so they don't shadow what we just wrote (e.g. a
  /// density PNG that would override a freshly generated vector drawable).
  final List<String> removed = [];

  bool get isEmpty =>
      written.isEmpty && skipped.isEmpty && warnings.isEmpty && removed.isEmpty;

  void merge(GenerationReport other) {
    written.addAll(other.written);
    skipped.addAll(other.skipped);
    warnings.addAll(other.warnings);
    removed.addAll(other.removed);
  }
}
