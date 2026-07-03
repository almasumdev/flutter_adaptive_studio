/// CLI entry point.
///
///   dart run flutter_adaptive_studio [init|generate|doctor|preview|revert] [options]
///
/// After `dart pub global activate flutter_adaptive_studio`, the same commands
/// are available via the short `fas` alias (e.g. `fas generate`).
library;

import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_adaptive_studio/generator.dart';
// Internal libraries used only by the `preview` command (not public API).
import 'package:flutter_adaptive_studio/src/config/config_loader.dart';
import 'package:flutter_adaptive_studio/src/preview/preview_generator.dart';
import 'package:path/path.dart' as p;

const _commands = {'init', 'sync', 'generate', 'doctor', 'preview', 'revert'};

void main(List<String> args) {
  final parser = ArgParser()
    ..addOption('project',
        abbr: 'p', help: 'Path to the target Flutter project.', defaultsTo: '.')
    ..addOption('config',
        abbr: 'c', help: 'Explicit config file. Otherwise auto-discovered.')
    ..addOption('flavor',
        abbr: 'F',
        help:
            'Build flavor: merge `flavors.<name>` and write to src/<name>/res.')
    ..addFlag('verbose', abbr: 'v', negatable: false, help: 'Verbose output.')
    ..addFlag('quiet', abbr: 'q', negatable: false, help: 'Errors only.')
    ..addFlag('force', abbr: 'f', negatable: false, help: 'Overwrite (init).')
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show usage.');

  final ArgResults opts;
  try {
    opts = parser.parse(args);
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    stderr.writeln(parser.usage);
    exit(64);
  }

  if (opts['help'] as bool) {
    stdout.writeln('flutter_adaptive_studio: Android & iOS icons & splash\n');
    stdout.writeln(
        'Usage: dart run flutter_adaptive_studio <command> [options]\n'
        '   or: fas <command> [options]   (after `dart pub global activate`)\n');
    stdout.writeln('Commands:');
    stdout.writeln('  init       Write a starter config into the project');
    stdout.writeln('  sync       Add new config options (commented), keeping '
        'your values');
    stdout.writeln('  generate   Generate icons + splash (default)');
    stdout.writeln('  doctor     Validate config + environment');
    stdout.writeln('  preview    Write an HTML launcher-mask preview sheet');
    stdout.writeln('  revert     Remove generated files\n');
    stdout.writeln(parser.usage);
    return;
  }

  final command = opts.rest.isEmpty ? 'generate' : opts.rest.first;
  if (!_commands.contains(command)) {
    stderr.writeln(
        'Unknown command "$command". One of: ${_commands.join(', ')}.');
    exit(64);
  }

  final level = (opts['verbose'] as bool)
      ? LogLevel.verbose
      : (opts['quiet'] as bool)
          ? LogLevel.quiet
          : LogLevel.normal;
  final logger = Logger(level: level);
  final projectRoot = p.normalize(p.absolute(opts['project'] as String));
  final configPath = opts['config'] as String?;
  final flavor = opts['flavor'] as String?;
  logger.info('flutter_adaptive_studio · $command · $projectRoot\n');

  switch (command) {
    case 'init':
      final path = Initializer(projectRoot: projectRoot, logger: logger)
          .run(force: opts['force'] as bool);
      exit(path == null ? 1 : 0);
    case 'sync':
      final added = ConfigSync(
              projectRoot: projectRoot, configPath: configPath, logger: logger)
          .run();
      exit(added < 0 ? 1 : 0);
    case 'doctor':
      exit(Doctor(
                  projectRoot: projectRoot,
                  configPath: configPath,
                  flavor: flavor,
                  logger: logger)
              .run()
          ? 0
          : 1);
    case 'revert':
      Reverter(
              projectRoot: projectRoot,
              configPath: configPath,
              flavor: flavor,
              logger: logger)
          .run();
      return;
    case 'preview':
      _preview(projectRoot, configPath, logger);
      return;
    case 'generate':
    default:
      _generate(projectRoot, configPath, flavor, logger);
  }
}

void _generate(
    String projectRoot, String? configPath, String? flavor, Logger logger) {
  final report = AdaptiveStudio(
    projectRoot: projectRoot,
    configPath: configPath,
    flavor: flavor,
    logger: logger,
  ).run();
  if (report == null) exit(1);

  stdout.writeln('');
  for (final w in report.warnings) {
    logger.warn(w);
  }
  for (final r in report.removed) {
    logger.step('removed stale: $r');
  }
  if (report.written.isEmpty) {
    logger.warn('Nothing generated. Check your config and sources.');
  } else {
    final removed = report.removed.isEmpty
        ? ''
        : '; ${report.removed.length} stale removed';
    logger.success('Generated ${report.written.length} file(s); '
        '${report.skipped.length} skipped$removed.');
  }
}

void _preview(String projectRoot, String? configPath, Logger logger) {
  final loader = ConfigLoader(projectRoot);
  final config = loader.load(explicitPath: configPath);
  if (config == null) {
    logger.error('No config found.');
    exit(1);
  }
  final out = PreviewGenerator(config: config, loader: loader, logger: logger)
      .generate();
  if (out == null) exit(1);
  logger.success('Open $out in a browser.');
}
