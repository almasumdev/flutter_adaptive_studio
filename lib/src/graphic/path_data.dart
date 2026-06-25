/// Lightweight SVG path-data utilities.
///
/// We do NOT re-emit path data — VectorDrawable's `android:pathData` accepts the
/// exact same `d` grammar (including relative commands), so paths pass through
/// verbatim. What we DO need is a bounding box, to fit foreground art into the
/// adaptive-icon safe zone. The box is computed conservatively (control points
/// and arc radii are included) so the fit never clips real geometry.
library;

import 'bounds.dart';

class PathData {
  /// Computes a conservative bounding box for an SVG path `d` string.
  /// Returns `null` if the path has no drawable points.
  static Bounds? bounds(String d) {
    final s = _Scanner(d);
    Bounds? box;
    var cx = 0.0, cy = 0.0; // current point
    var sx = 0.0, sy = 0.0; // subpath start
    void add(double x, double y) {
      box = box == null ? Bounds.fromPoint(x, y) : (box!..includePoint(x, y));
    }

    var cmd = '';
    while (!s.atEnd) {
      if (s.isCommandAhead()) cmd = s.readCommand();
      final rel = cmd == cmd.toLowerCase();
      final u = cmd.toUpperCase();
      switch (u) {
        case 'M':
          var x = s.num(), y = s.num();
          if (rel) {
            x += cx;
            y += cy;
          }
          cx = x;
          cy = y;
          sx = x;
          sy = y;
          add(x, y);
          cmd = rel ? 'l' : 'L'; // subsequent pairs are implicit lineto
        case 'L':
          var x = s.num(), y = s.num();
          if (rel) {
            x += cx;
            y += cy;
          }
          cx = x;
          cy = y;
          add(x, y);
        case 'H':
          var x = s.num();
          if (rel) x += cx;
          cx = x;
          add(x, cy);
        case 'V':
          var y = s.num();
          if (rel) y += cy;
          cy = y;
          add(cx, y);
        case 'C':
          final p = _readPoints(s, 3, rel, cx, cy);
          add(p[0], p[1]); // control 1
          add(p[2], p[3]); // control 2
          add(p[4], p[5]); // end
          cx = p[4];
          cy = p[5];
        case 'S':
        case 'Q':
          final p = _readPoints(s, 2, rel, cx, cy);
          add(p[0], p[1]);
          add(p[2], p[3]);
          cx = p[2];
          cy = p[3];
        case 'T':
          var x = s.num(), y = s.num();
          if (rel) {
            x += cx;
            y += cy;
          }
          cx = x;
          cy = y;
          add(x, y);
        case 'A':
          final rx = s.num().abs(), ry = s.num().abs();
          s.num(); // x-axis-rotation
          s.num(); // large-arc-flag
          s.num(); // sweep-flag
          var x = s.num(), y = s.num();
          if (rel) {
            x += cx;
            y += cy;
          }
          // Conservative: bound start/end expanded by the radii.
          add(cx - rx, cy - ry);
          add(cx + rx, cy + ry);
          add(x - rx, y - ry);
          add(x + rx, y + ry);
          cx = x;
          cy = y;
        case 'Z':
          cx = sx;
          cy = sy;
        default:
          // Unknown token — bail rather than loop forever.
          return box;
      }
    }
    return box;
  }

  /// Reads [count] coordinate pairs, applying relative offset to each pair.
  static List<double> _readPoints(
      _Scanner s, int count, bool rel, double cx, double cy) {
    final out = <double>[];
    for (var i = 0; i < count; i++) {
      var x = s.num(), y = s.num();
      if (rel) {
        x += cx;
        y += cy;
      }
      out
        ..add(x)
        ..add(y);
    }
    return out;
  }
}

/// A forgiving scanner for SVG path-data / number lists.
class _Scanner {
  _Scanner(this.s);
  final String s;
  int i = 0;

  void _skipSep() {
    while (i < s.length) {
      final c = s.codeUnitAt(i);
      if (c == 0x20 || c == 0x2C || c == 0x09 || c == 0x0A || c == 0x0D) {
        i++;
      } else {
        break;
      }
    }
  }

  bool get atEnd {
    _skipSep();
    return i >= s.length;
  }

  bool isCommandAhead() {
    _skipSep();
    if (i >= s.length) return false;
    final c = s[i];
    return RegExp(r'[a-zA-Z]').hasMatch(c);
  }

  String readCommand() {
    _skipSep();
    return s[i++];
  }

  double num() {
    _skipSep();
    final start = i;
    if (i < s.length && (s[i] == '+' || s[i] == '-')) i++;
    while (i < s.length && _isDigit(s[i])) {
      i++;
    }
    if (i < s.length && s[i] == '.') {
      i++;
      while (i < s.length && _isDigit(s[i])) {
        i++;
      }
    }
    if (i < s.length && (s[i] == 'e' || s[i] == 'E')) {
      i++;
      if (i < s.length && (s[i] == '+' || s[i] == '-')) i++;
      while (i < s.length && _isDigit(s[i])) {
        i++;
      }
    }
    return double.parse(s.substring(start, i));
  }

  static bool _isDigit(String c) {
    final u = c.codeUnitAt(0);
    return u >= 0x30 && u <= 0x39;
  }
}
