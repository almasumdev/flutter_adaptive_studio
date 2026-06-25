/// Minimal leveled logger for the CLI. No external dependency so the tool stays
/// light. Writes humans-readable, prefixed lines to stdout/stderr.
library;

import 'dart:io';

/// Verbosity for [Logger].
enum LogLevel { quiet, normal, verbose }

/// A tiny logger shared across the generator pipeline.
class Logger {
  Logger({this.level = LogLevel.normal});

  LogLevel level;

  /// Per the design principle, a missing optional asset is a *skip*, not a
  /// failure — surfaced via [skip] so the user always knows what was omitted.
  void skip(String message) => _line(stdout, '  ~ skip: $message');

  void step(String message) => _line(stdout, '• $message');

  void detail(String message) {
    if (level == LogLevel.verbose) _line(stdout, '    $message');
  }

  void info(String message) => _line(stdout, message);

  void success(String message) => _line(stdout, '✓ $message');

  void warn(String message) => _line(stderr, '⚠ $message');

  void error(String message) => _line(stderr, '✗ $message');

  void _line(IOSink sink, String message) {
    if (level == LogLevel.quiet && sink == stdout) return;
    sink.writeln(message);
  }
}
