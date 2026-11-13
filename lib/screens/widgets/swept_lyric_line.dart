// Ported from BitChord's SweptLyricLine (PlayerLyrics.kt, GPL-3.0); see
// BITCHORD_LICENSE.txt.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../services/lyrics/lyrics_models.dart';
import '../../services/lyrics/swept_lyric_timing.dart';

/// What the part of a line not yet sung is held back to.
const double kSweptUnsungAlpha = 0.45;

/// The bloom behind the line being sung, at its very strongest.
const double kSweptGlowAlpha = 0.62;

/// BitChord's measurements are set against its 34sp lyrics; they scale with
/// the type here so a larger line moves the same way.
const double _referenceFontSize = 34;

/// How far the sweep's leading edge fades out instead of ending on a cut.
const double _wipeFeather = 30;

/// How far the word being sung lifts off the line.
const double _wordRise = 2;

/// How much further up a row is opened for a word animated letter by letter,
/// in multiples of [_wordRise].
const double _growHeadroom = 3;

/// How far the bloom spreads off a letter (a Compose blur radius).
const double _glowRadius = 6;

/// One word-synced line drawn the way BitChord draws it: a dim copy of the
/// text with a lit copy clipped to whatever has been sung, its leading edge
/// feathered; the word being sung lifted off the line and settling back as
/// the singing moves on; and words held long enough swelling, rising and
/// lighting a letter at a time, with a blurred bloom behind those letters.
///
/// The text is laid out once; a frame only clips and redraws it. The line
/// listens to the clock only while it is actually moving.
class SweptLyricLine extends StatefulWidget {
  const SweptLyricLine({
    super.key,
    required this.line,
    required this.position,
    required this.style,
    required this.color,
    this.dimAlpha = kSweptUnsungAlpha,
    this.glowAlpha = 0,
    this.feather = false,
    this.rise = true,
    this.textAlign = TextAlign.start,
  });

  final LyricLine line;
  final ValueListenable<int> position;
  final TextStyle style;

  /// What the words are set in, lit; the unsung copy is this at [dimAlpha].
  final Color color;
  final double dimAlpha;
  final double glowAlpha;

  /// Softens the sweep's edge. Only the line being sung needs it.
  final bool feather;

  /// Whether words lift off the line as they are sung.
  final bool rise;
  final TextAlign textAlign;

  @override
  State<SweptLyricLine> createState() => _SweptLyricLineState();
}

class _SweptLyricLineState extends State<SweptLyricLine> {
  late SweptTiming _timing;
  final ValueNotifier<int> _drawnAt = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _timing = SweptTiming.of(widget.line);
    widget.position.addListener(_onTick);
    _onTick();
  }

  @override
  void didUpdateWidget(SweptLyricLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.line, widget.line)) {
      _timing = SweptTiming.of(widget.line);
    }
    if (!identical(oldWidget.position, widget.position)) {
      oldWidget.position.removeListener(_onTick);
      widget.position.addListener(_onTick);
    }
    _onTick();
  }

  @override
  void dispose() {
    widget.position.removeListener(_onTick);
    _drawnAt.dispose();
    super.dispose();
  }

  /// Where the line is drawn at: the clock while it moves, and one fixed
  /// moment either side of that, so a line nobody is singing never repaints.
  void _onTick() {
    final now = widget.position.value;
    final drawn = now < _timing.animatesFromMs
        ? _timing.animatesFromMs - 1
        : now > _timing.animatesUntilMs
        ? _timing.animatesUntilMs + 1
        : now;
    _drawnAt.value = drawn;
  }

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.merge(widget.style);
    final scaler = MediaQuery.textScalerOf(context);
    final rtl = _isRtl(widget.line.text);
    return Semantics(
      label: widget.line.text,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final layout = _LineLayout.build(
            text: widget.line.text,
            style: style.copyWith(color: widget.color),
            scaler: scaler,
            rtl: rtl,
            textAlign: widget.textAlign,
            maxWidth: constraints.maxWidth,
          );
          return CustomPaint(
            size: Size(
              constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : layout.painter.width,
              layout.painter.height,
            ),
            painter: _SweptPainter(
              layout: layout,
              timing: _timing,
              drawnAt: _drawnAt,
              dimAlpha: widget.dimAlpha,
              glowAlpha: widget.glowAlpha,
              feather: widget.feather,
              rise: widget.rise,
              scale: (style.fontSize ?? _referenceFontSize) /
                  _referenceFontSize,
              fontSize: scaler.scale(style.fontSize ?? _referenceFontSize),
            ),
          );
        },
      ),
    );
  }
}

bool _isRtl(String text) {
  for (final unit in text.codeUnits) {
    if ((unit >= 0x0590 && unit <= 0x08FF) ||
        (unit >= 0xFB1D && unit <= 0xFEFC)) {
      return true;
    }
    if ((unit >= 0x41 && unit <= 0x5A) || (unit >= 0x61 && unit <= 0x7A)) {
      return false;
    }
  }
  return false;
}

/// One visual row of the laid-out line.
class _Row {
  _Row(this.start, this.endAll, this.endVisible, this.left, this.right,
      this.top, this.bottom);

  final int start;
  final int endAll;
  final int endVisible;
  final double left;
  final double right;
  final double top;
  final double bottom;
}

/// The line's text laid out, with where every character and row sits. Kept
/// per text, style and width, so frames never lay anything out again.
class _LineLayout {
  _LineLayout._(this.painter, this.text, this.rtl, this.rows, this.charRow,
      this.charLeft, this.charRight);

  final TextPainter painter;
  final String text;
  final bool rtl;
  final List<_Row> rows;
  final List<int> charRow;
  final List<double> charLeft;
  final List<double> charRight;

  static final Map<Object, _LineLayout> _cache = {};

  static _LineLayout build({
    required String text,
    required TextStyle style,
    required TextScaler scaler,
    required bool rtl,
    required TextAlign textAlign,
    required double maxWidth,
  }) {
    final key = Object.hash(text, style, scaler, rtl, textAlign, maxWidth);
    final cached = _cache[key];
    if (cached != null && cached.text == text) return cached;
    // Dropped rather than disposed: a painter still on screen may hold one.
    if (_cache.length > 160) _cache.clear();

    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      textAlign: textAlign,
      textScaler: scaler,
    )..layout(maxWidth: maxWidth.isFinite ? maxWidth : double.infinity);
    final metrics = painter.computeLineMetrics();
    final length = text.length;
    final charRow = List<int>.filled(length, 0);
    final charLeft = List<double>.filled(length, 0);
    final charRight = List<double>.filled(length, 0);
    final visible = List<bool>.filled(length, false);

    int rowAt(double y) {
      for (var i = 0; i < metrics.length; i++) {
        if (y <= metrics[i].baseline + metrics[i].descent) return i;
      }
      return math.max(0, metrics.length - 1);
    }

    for (var i = 0; i < length; i++) {
      final boxes = painter.getBoxesForSelection(
        TextSelection(baseOffset: i, extentOffset: i + 1),
      );
      if (boxes.isEmpty) {
        if (i > 0) {
          charRow[i] = charRow[i - 1];
          charLeft[i] = charRight[i - 1];
          charRight[i] = charRight[i - 1];
        }
        continue;
      }
      final box = boxes.first;
      charRow[i] = rowAt((box.top + box.bottom) / 2);
      charLeft[i] = box.left;
      charRight[i] = box.right;
      visible[i] = text.codeUnitAt(i) > 0x20 && box.right > box.left;
    }

    final rows = <_Row>[];
    for (var r = 0; r < metrics.length; r++) {
      var start = -1;
      var endAll = -1;
      var endVisible = -1;
      var left = double.infinity;
      var right = double.negativeInfinity;
      for (var i = 0; i < length; i++) {
        if (charRow[i] != r) continue;
        if (start < 0) start = i;
        endAll = i + 1;
        if (visible[i]) {
          endVisible = i + 1;
          left = math.min(left, charLeft[i]);
          right = math.max(right, charRight[i]);
        }
      }
      final m = metrics[r];
      if (start < 0) {
        start = rows.isEmpty ? 0 : rows.last.endAll;
        endAll = start;
      }
      if (endVisible < 0) endVisible = start;
      if (!left.isFinite) {
        left = m.left;
        right = m.left + m.width;
      }
      rows.add(
        _Row(start, endAll, endVisible, left, right, m.baseline - m.ascent,
            m.baseline + m.descent),
      );
    }

    final layout = _LineLayout._(
      painter,
      text,
      rtl,
      rows,
      charRow,
      charLeft,
      charRight,
    );
    _cache[key] = layout;
    return layout;
  }

  int rowOf(int offset) =>
      offset < charRow.length ? charRow[offset] : rows.length - 1;

  /// Where a character offset sits across [row], in pixels, row-aware at
  /// both ends (BitChord's `xOn`).
  double xOn(int offset, _Row row) {
    if (offset <= row.start) return rtl ? row.right : row.left;
    if (offset >= row.endVisible) return rtl ? row.left : row.right;
    final x = rtl ? charRight[offset] : charLeft[offset];
    return x.clamp(row.left, row.right);
  }

  /// Where a fractional character index sits across [row]: inside a timed
  /// word that sits whole on the row, read as a share of the word and laid
  /// across its width at a steady rate; otherwise letter by letter.
  double horizontalAt(double chars, _Row row, List<(int, int)> spans) {
    for (final (start, end) in spans) {
      if (chars >= start && chars < end) {
        if (start >= row.start && end <= row.endVisible) {
          final from = xOn(start, row);
          final to = xOn(end, row);
          return from + (to - from) * (chars - start) / (end - start);
        }
        break;
      }
    }
    final index = chars.floor().clamp(row.start, row.endAll);
    final here = xOn(index, row);
    final rawNext = index + 1;
    final spills = rawNext >= text.length || rowOf(rawNext) != rows.indexOf(row);
    final double next;
    if (spills) {
      next = rawNext > row.endVisible
          ? (rtl ? row.left : row.right)
          : xOn(math.min(rawNext, row.endVisible), row);
    } else {
      next = xOn(rawNext, row);
    }
    return here + (next - here) * (chars - index);
  }
}

class _SweptPainter extends CustomPainter {
  _SweptPainter({
    required this.layout,
    required this.timing,
    required this.drawnAt,
    required this.dimAlpha,
    required this.glowAlpha,
    required this.feather,
    required this.rise,
    required this.scale,
    required this.fontSize,
  }) : super(repaint: drawnAt);

  final _LineLayout layout;
  final SweptTiming timing;
  final ValueListenable<int> drawnAt;
  final double dimAlpha;
  final double glowAlpha;
  final bool feather;
  final bool rise;
  final double scale;
  final double fontSize;

  /// Shared by every letter of a frame; there is only ever one in hand.
  static final CharGrowth _growth = CharGrowth();

  /// Desktop Skia lays text on whole pixels, so a fraction of a pixel of
  /// lift is moved as a picture instead (BitChord's desktop clipShiftedDown).
  static final bool _subpixelShift = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);

  double get _peak => _wordRise * scale;

  Rect _bounds(Size size) {
    final room = _peak * (_growHeadroom + 2) + _glowRadius * scale * 3;
    return Rect.fromLTRB(
      -room,
      -room,
      math.max(size.width, layout.painter.width) + room,
      layout.painter.height + room,
    );
  }

  void _drawText(Canvas canvas) => layout.painter.paint(canvas, Offset.zero);

  @override
  void paint(Canvas canvas, Size size) {
    final position = drawnAt.value;
    final bounds = _bounds(size);

    // The unsung copy.
    if (dimAlpha >= 0.999) {
      _riseWith(canvas, position, _drawText);
    } else if (dimAlpha > 0.001) {
      canvas.saveLayer(
        bounds,
        Paint()..color = Color.fromRGBO(255, 255, 255, dimAlpha),
      );
      _riseWith(canvas, position, _drawText);
      canvas.restore();
    }

    // The bloom on held words, behind the lit copy.
    if (glowAlpha > 0.01 && timing.isGrowing(position)) {
      final sigma = _glowRadius * scale * 0.57735 + 0.5;
      canvas.saveLayer(
        bounds,
        Paint()
          ..color = Color.fromRGBO(255, 255, 255, glowAlpha)
          ..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      );
      _glowGrown(canvas, position);
      canvas.restore();
    }

    // The lit copy, swept to what has been sung.
    _riseWith(canvas, position, (c) => _drawSwept(c, position, bounds));
  }

  void _drawSwept(Canvas canvas, int position, Rect bounds) {
    if (position >= timing.endMs) {
      _drawText(canvas);
      return;
    }
    if (position <= timing.timeMs) return;
    final revealed = timing.revealedChars(position);
    if (feather) {
      canvas.saveLayer(bounds, Paint());
      _sweepTo(canvas, revealed);
      canvas.restore();
    } else {
      _sweepTo(canvas, revealed);
    }
  }

  /// Draws the text clipped to its first [revealed] characters, the boundary
  /// feathered ahead of it into what is still to be sung.
  void _sweepTo(Canvas canvas, double revealed) {
    if (revealed <= 0) return;
    if (revealed >= layout.text.length) {
      _drawText(canvas);
      return;
    }
    final rtl = layout.rtl;
    for (final row in layout.rows) {
      if (revealed <= row.start) return;
      final cut = revealed < row.endAll;
      final charPos = cut
          ? layout.horizontalAt(revealed, row, timing.wordSpans)
          : (rtl ? row.left : row.right);
      final safe = charPos.clamp(row.left, row.right);
      final featherPx = feather && cut
          ? math.min(
              _wipeFeather * scale,
              rtl ? row.right - safe : safe - row.left,
            )
          : 0.0;
      final lead = rtl
          ? math.max(safe - featherPx, row.left)
          : math.min(safe + featherPx, row.right);
      final clipLeft = rtl ? lead : row.left;
      final clipRight = rtl ? row.right : lead;
      if (clipLeft >= clipRight) continue;

      canvas.save();
      canvas.clipRect(Rect.fromLTRB(clipLeft, row.top, clipRight, row.bottom));
      _drawText(canvas);
      canvas.restore();

      if (featherPx < 0.5) continue;
      final band = Rect.fromLTRB(
        -1e5,
        row.top,
        1e5,
        row.bottom,
      );
      canvas.drawRect(
        band,
        Paint()
          ..blendMode = BlendMode.dstIn
          ..shader = ui.Gradient.linear(
            Offset(safe, 0),
            Offset(rtl ? safe - featherPx : safe + featherPx, 0),
            const [Colors.white, Colors.transparent],
          ),
      );
    }
  }

  /// Redraws each row with the word being sung lifted off the line and the
  /// ones behind it settling, cut at word boundaries; held words a letter at
  /// a time. Costs one draw while nothing is off the floor.
  void _riseWith(
    Canvas canvas,
    int position,
    void Function(Canvas) drawContent,
  ) {
    if (!rise || !timing.isLifted(position)) {
      drawContent(canvas);
      return;
    }
    final peak = _peak;
    for (final row in layout.rows) {
      final top = row.top;
      final bottom = row.bottom;
      var at = row.start;
      var edge = row.left;
      for (var index = 0; index < timing.words.length; index++) {
        final (spanStart, spanEnd) = timing.wordSpans[index];
        final start = math.max(spanStart, row.start);
        final end = math.min(spanEnd, row.endVisible);
        if (start >= end) continue;
        final grown = timing.growingAt(index);
        final held = grown != null &&
                position >= grown.startMs &&
                position <= grown.restsAtMs
            ? grown
            : null;
        final lift = timing.wordLift(index, position);
        if (held == null && lift <= 0.01) continue;
        final from = layout.xOn(start, row);
        final to = layout.xOn(end, row);
        if (to <= from) continue;
        if (start > at) {
          _slice(canvas, drawContent, edge, top, from, bottom, 0);
        }
        if (held != null) {
          _growEach(canvas, drawContent, held, position, row, start, end, peak);
        } else {
          _slice(canvas, drawContent, from, top - peak, to, bottom, -lift * peak);
        }
        at = end;
        edge = to;
      }
      if (at < row.endVisible) {
        _slice(canvas, drawContent, edge, top, row.right, bottom, 0);
      }
    }
  }

  /// Redraws one held word a letter at a time, each at its own swell and
  /// height, clipped to where the letter is going rather than where it sits.
  void _growEach(
    Canvas canvas,
    void Function(Canvas) drawContent,
    GrowingWord word,
    int position,
    _Row row,
    int start,
    int end,
    double peak,
  ) {
    final fall = timing.wordFall(word.index, position);
    final first = timing.wordSpans[word.index].$1;
    final ceiling = row.top - peak * _growHeadroom;
    final middle = (row.top + row.bottom) / 2;
    for (var char = start; char < end; char++) {
      word.sampleInto(char - first, position, _growth);
      final from = layout.xOn(char, row);
      final to = layout.xOn(char + 1, row);
      if (to <= from) continue;
      final dx = _growth.shift * fontSize;
      final dy = -_growth.rise * peak * fall;
      final growScale = _growth.scale;
      final overhang = (to - from) * (growScale - 1) / 2;
      final centre = Offset((from + to) / 2, middle);
      _slice(
        canvas,
        (c) {
          c.translate(dx, 0);
          c.translate(centre.dx, centre.dy);
          c.scale(growScale, growScale);
          c.translate(-centre.dx, -centre.dy);
          drawContent(c);
        },
        from - overhang + dx,
        ceiling,
        to + overhang + dx,
        row.bottom,
        dy,
      );
    }
  }

  /// The held words' letters, each masked to its own bloom, for the blurred
  /// copy behind the line. Nothing at all on a line of ordinary syllables.
  void _glowGrown(Canvas canvas, int position) {
    final peak = _peak;
    final length = layout.text.length;
    for (final word in timing.growingWords) {
      if (position < word.startMs || position > word.restsAtMs) continue;
      final (spanStart, spanEnd) = timing.wordSpans[word.index];
      final fall = timing.wordFall(word.index, position);
      for (var char = spanStart; char < math.min(spanEnd, length); char++) {
        word.sampleInto(char - spanStart, position, _growth);
        if (_growth.bloom <= 0.01) continue;
        final row = layout.rows[layout.rowOf(char)];
        final from = layout.xOn(char, row);
        final to = layout.xOn(char + 1, row);
        if (to <= from) continue;
        final dx = _growth.shift * fontSize;
        final dy = -_growth.rise * peak * fall;
        final overhang = (to - from) * (_growth.scale - 1) / 2;
        final clip = Rect.fromLTRB(
          from - overhang + dx,
          row.top - peak * _growHeadroom,
          to + overhang + dx,
          row.bottom,
        );
        final centre = Offset((from + to) / 2, (row.top + row.bottom) / 2);
        canvas.save();
        canvas.clipRect(clip);
        canvas.save();
        canvas.translate(dx, dy);
        canvas.translate(centre.dx, centre.dy);
        canvas.scale(_growth.scale, _growth.scale);
        canvas.translate(-centre.dx, -centre.dy);
        _drawText(canvas);
        canvas.restore();
        canvas.drawRect(
          clip,
          Paint()
            ..color = Color.fromRGBO(255, 255, 255, _growth.bloom.clamp(0.0, 1.0))
            ..blendMode = BlendMode.dstIn,
        );
        canvas.restore();
      }
    }
  }

  /// One piece of the line, clipped to its own box and drawn [dy] lower.
  void _slice(
    Canvas canvas,
    void Function(Canvas) drawContent,
    double left,
    double top,
    double right,
    double bottom,
    double dy,
  ) {
    if (right <= left) return;
    final whole = dy.floorToDouble();
    final fraction = dy - whole;
    if (!_subpixelShift || fraction < 0.02 || fraction > 0.98) {
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(left, top, right, bottom));
      canvas.translate(0, _subpixelShift ? dy.roundToDouble() : dy);
      drawContent(canvas);
      canvas.restore();
      return;
    }
    // Drawn on whole pixels into a layer, and the layer moved by the
    // fraction, so the lift glides instead of stepping a pixel at a time.
    canvas.saveLayer(
      Rect.fromLTRB(left, top - 1, right, bottom + 1),
      Paint()
        ..imageFilter = ui.ImageFilter.matrix(
          Matrix4.translationValues(0, fraction, 0).storage,
          filterQuality: FilterQuality.low,
        ),
    );
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(left, top - fraction, right, bottom - fraction));
    canvas.translate(0, whole);
    drawContent(canvas);
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SweptPainter old) =>
      !identical(old.layout, layout) ||
      !identical(old.timing, timing) ||
      old.drawnAt != drawnAt ||
      old.dimAlpha != dimAlpha ||
      old.glowAlpha != glowAlpha ||
      old.feather != feather ||
      old.rise != rise ||
      old.scale != scale;
}
