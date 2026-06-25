/// SVG rasteriser that shells out to a detected system tool. Tries, in order:
/// `resvg`, `rsvg-convert`, `inkscape`, then ImageMagick `magick` (IM7 only —
/// never the bare `convert`, which on Windows is an unrelated system utility).
///
/// Available only when one of those is on PATH; otherwise the caller skips SVG
/// raster outputs. A bundled resvg-FFI backend (no system dependency) is the
/// planned production default.
library;

import 'dart:io';

import 'rasterizer.dart';

class ProcessRasterizer implements Rasterizer {
  ProcessRasterizer() : _tool = _detect();

  final _SvgTool? _tool;

  @override
  String get name =>
      _tool == null ? 'process (none found)' : 'process:${_tool.exe}';

  @override
  bool get available => _tool != null;

  @override
  bool supports(String extension) => extension.toLowerCase() == '.svg';

  @override
  bool renderToPng({
    required String sourcePath,
    required int sizePx,
    required String outPath,
  }) {
    final tool = _tool;
    if (tool == null) return false;
    File(outPath).parent.createSync(recursive: true);
    final result = Process.runSync(
      tool.exe,
      tool.args(sourcePath, outPath, sizePx),
    );
    return result.exitCode == 0 && File(outPath).existsSync();
  }

  static _SvgTool? _detect() {
    for (final candidate in _candidates) {
      if (_canRun(candidate.exe, candidate.versionArgs)) return candidate;
    }
    return null;
  }

  static bool _canRun(String exe, List<String> args) {
    try {
      final r = Process.runSync(exe, args);
      return r.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }

  static final List<_SvgTool> _candidates = [
    _SvgTool(
      exe: 'resvg',
      versionArgs: const ['--version'],
      args: (src, out, size) => ['-w', '$size', '-h', '$size', src, out],
    ),
    _SvgTool(
      exe: 'rsvg-convert',
      versionArgs: const ['--version'],
      args: (src, out, size) => ['-w', '$size', '-h', '$size', src, '-o', out],
    ),
    _SvgTool(
      exe: 'inkscape',
      versionArgs: const ['--version'],
      args: (src, out, size) => [
        src,
        '--export-type=png',
        '--export-filename=$out',
        '-w',
        '$size',
        '-h',
        '$size',
      ],
    ),
    _SvgTool(
      exe: 'magick',
      versionArgs: const ['-version'],
      args: (src, out, size) =>
          ['-background', 'none', src, '-resize', '${size}x$size', out],
    ),
  ];
}

class _SvgTool {
  _SvgTool({required this.exe, required this.versionArgs, required this.args});
  final String exe;
  final List<String> versionArgs;
  final List<String> Function(String src, String out, int size) args;
}
