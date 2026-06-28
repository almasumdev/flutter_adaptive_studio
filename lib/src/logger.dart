/// Minimal leveled logger for the CLI. No external dependency so the tool stays
/// light. Writes humans-readable, prefixed lines to stdout/stderr.
library;

import 'dart:io';

/// Verbosity for [Logger].
enum LogLevel {
  /// Suppresses stdout output; only stderr (warnings/errors) is written.
  quiet,

  /// Default verbosity: normal stdout output without verbose details.
  normal,

  /// Maximum verbosity: also emits [Logger.detail] lines.
  verbose,
}

/// A tiny logger shared across the generator pipeline.
class Logger {
  /// Creates a logger at the given [level] (defaults to [LogLevel.normal]).
  Logger({this.level = LogLevel.normal});

  /// Current verbosity controlling which messages are emitted.
  LogLevel level;

  /// Per the design principle, a missing optional asset is a *skip*, not a
  /// failure — surfaced via [skip] so the user always knows what was omitted.
  void skip(String message) => _line(stdout, '  ~ skip: $message');

  /// Logs a top-level pipeline step to stdout.
  void step(String message) => _line(stdout, '• $message');

  /// Logs an indented detail line to stdout, only when [level] is verbose.
  void detail(String message) {
    if (level == LogLevel.verbose) _line(stdout, '    $message');
  }

  /// Logs a plain informational line to stdout.
  void info(String message) => _line(stdout, message);

  /// Logs a success line to stdout.
  void success(String message) => _line(stdout, '✓ $message');

  /// Logs a warning line to stderr.
  void warn(String message) => _line(stderr, '⚠ $message');

  /// Logs an error line to stderr.
  void error(String message) => _line(stderr, '✗ $message');

  void _line(IOSink sink, String message) {
    if (level == LogLevel.quiet && sink == stdout) return;
    sink.writeln(message);
  }
}
