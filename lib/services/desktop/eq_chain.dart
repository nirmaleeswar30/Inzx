import 'dart:math' as math;

import '../autoeq/peq.dart';
import '../equalizer_service.dart';

/// The desktop equaliser + AutoEQ correction as one libmpv audio filter
/// chain (FFmpeg's lavfi filters), the same RBJ filters Android runs in
/// EqualizerProcessor and ParametricEqProcessor.
///
/// Peaking filters map one to one onto FFmpeg's `equalizer`. Shelves and
/// low/high passes use `lowshelf` / `highshelf` / `lowpass` / `highpass`
/// when the libmpv has them (Linux's system libmpv does). The trimmed
/// libmpv that media_kit bundles on Windows has only `equalizer` among them
/// (and no `volume` filter at all), so there a shelf becomes a gain plus
/// three peaking filters fitted to its curve (within 0.35 dB from 20 Hz to
/// 16 kHz at 48 kHz; measured through the real libmpv against Android's
/// curve, a full EQ + AutoEQ chain stays within 0.65 dB); passes, which no AutoEQ profile in the database uses, are
/// skipped. The chain's overall gain (preamps, and the shelves' fitted
/// gains) isn't a filter: it rides on mpv's volume (see [MpvEq.gainDb]).
class EqChain {
  const EqChain(this.volumeDb, this.filters);

  /// Overall gain (preamps), dB.
  final double volumeDb;

  /// Filters to run, in order.
  final List<PeqFilter> filters;

  static const empty = EqChain(0, []);

  bool get isFlat =>
      volumeDb.abs() < 0.01 &&
      !filters.any((f) => f.enabled && (!f.type.hasGain || f.gainDb.abs() >= 0.01));

  /// The Android equaliser's filters for [gains] (one per
  /// [EqualizerService.bandsHz]): slope-1 shelves at the two ends, Q 1 bells
  /// between, and a preamp of half the largest boost.
  static EqChain equalizer(List<double> gains) {
    const bands = EqualizerService.bandsHz;
    final filters = <PeqFilter>[];
    for (var i = 0; i < bands.length && i < gains.length; i++) {
      if (gains[i].abs() < 0.01) continue;
      final type = i == 0
          ? PeqFilterType.lowShelf
          : i == bands.length - 1
          ? PeqFilterType.highShelf
          : PeqFilterType.peaking;
      // RBJ "slope 1" shelves are Q = 1/sqrt(2).
      final q = type == PeqFilterType.peaking ? 1.0 : math.sqrt1_2;
      filters.add(PeqFilter(type, bands[i].toDouble(), gains[i], q));
    }
    final maxBoost = gains.fold<double>(0, (m, g) => math.max(m, g));
    return EqChain(-maxBoost / 2, filters);
  }

  /// An AutoEQ correction as published by its controller.
  static EqChain autoEq(PeqSettings settings) => EqChain(
    settings.preampDb,
    [for (final f in settings.filters.take(PeqSettings.maxFilters)) if (f.enabled) f],
  );

  EqChain operator +(EqChain other) =>
      EqChain(volumeDb + other.volumeDb, [...filters, ...other.filters]);

  /// The mpv `af` value ('' for none, so the samples pass untouched) and
  /// the gain to apply with it.
  MpvEq toMpv({required bool shelves}) {
    if (isFlat) return const MpvEq('', 0);
    var volume = volumeDb;
    final stages = <String>[];
    for (final f in filters) {
      if (!f.enabled) continue;
      if (f.type.hasGain && f.gainDb.abs() < 0.01) continue;
      final fc = _num(f.frequencyHz);
      final q = _num(math.max(f.q, 0.05));
      final g = _num(f.gainDb);
      switch (f.type) {
        case PeqFilterType.peaking:
          stages.add('equalizer=f=$fc:t=q:w=$q:g=$g');
        case PeqFilterType.lowShelf || PeqFilterType.highShelf when shelves:
          final name = f.type == PeqFilterType.lowShelf ? 'lowshelf' : 'highshelf';
          stages.add('$name=f=$fc:t=q:w=$q:g=$g');
        case PeqFilterType.lowShelf || PeqFilterType.highShelf:
          final approx = ShelfApprox.of(f);
          volume += approx.volumeDb;
          for (final p in approx.peaks) {
            stages.add(
              'equalizer=f=${_num(p.frequencyHz)}:t=q:w=${_num(p.q)}:g=${_num(p.gainDb)}',
            );
          }
        case PeqFilterType.lowPass || PeqFilterType.highPass when shelves:
          final name = f.type == PeqFilterType.lowPass ? 'lowpass' : 'highpass';
          stages.add('$name=f=$fc:t=q:w=$q');
        case PeqFilterType.lowPass || PeqFilterType.highPass:
          break; // not available in this libmpv
      }
    }
    return MpvEq(
      // mpv's own converter first: FFmpeg's biquads take planar samples
      // only, and the bundled libavfilter has no aresample to convert
      // (without it a FLAC's interleaved s16 would fail the graph).
      stages.isEmpty ? '' : 'format=format=floatp,@inzxeq:lavfi=[${stages.join(',')}]',
      volume.abs() < 0.01 ? 0 : volume,
    );
  }

  static String _num(double v) {
    final s = v.toStringAsFixed(4);
    // Trim trailing zeros: "150.0000" -> "150", "0.7071" stays.
    return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
  }
}

/// What runs in mpv: the filter chain and the gain that goes with it.
class MpvEq {
  const MpvEq(this.af, this.gainDb);

  /// The `af` property ('' for none).
  final String af;

  /// Overall gain in dB, applied through mpv's volume.
  final double gainDb;

  @override
  bool operator ==(Object other) => other is MpvEq && other.af == af && other.gainDb == gainDb;

  @override
  int get hashCode => Object.hash(af, gainDb);
}

/// A shelf rebuilt from what the Windows libmpv has: an overall gain plus
/// three peaking filters, fitted (Levenberg-Marquardt, as PeqFitter) to the
/// shelf's response on AutoEQ's 1/12-octave grid. Fits are cached; the
/// equaliser's shelves only take 0.5 dB steps.
class ShelfApprox {
  const ShelfApprox(this.volumeDb, this.peaks, this.maxErrorDb);

  final double volumeDb;
  final List<PeqFilter> peaks;

  /// Largest deviation from the shelf between 20 Hz and 16 kHz.
  final double maxErrorDb;

  static const _peakCount = 3;
  static const _sampleRate = 48000.0;
  static const _maxFc = 19000.0;
  static final _cache = <String, ShelfApprox>{};

  static ShelfApprox of(PeqFilter shelf) {
    final key =
        '${shelf.type.index}|${shelf.frequencyHz.toStringAsFixed(1)}|'
        '${shelf.q.toStringAsFixed(3)}|${shelf.gainDb.toStringAsFixed(2)}';
    return _cache[key] ??= _fit(shelf);
  }

  static final List<double> _grid = PeqMath.logGrid;
  static final List<double> _cos1 = [for (final f in _grid) math.cos(_w(f))];
  static final List<double> _sin1 = [for (final f in _grid) math.sin(_w(f))];
  static final List<double> _cos2 = [for (final f in _grid) math.cos(2 * _w(f))];
  static final List<double> _sin2 = [for (final f in _grid) math.sin(2 * _w(f))];
  static final List<double> _weights = [
    for (final f in _grid) f > 16000 ? 0.3 : 1.0,
  ];
  static double _w(double f) => 2 * math.pi * f / _sampleRate;

  /// Response (dB) of a biquad at every grid point, added into [out].
  static void _addResponse(List<double> c, List<double> out) {
    for (var i = 0; i < _grid.length; i++) {
      final nr = c[0] + c[1] * _cos1[i] + c[2] * _cos2[i];
      final ni = -c[1] * _sin1[i] - c[2] * _sin2[i];
      final dr = 1.0 + c[3] * _cos1[i] + c[4] * _cos2[i];
      final di = -c[3] * _sin1[i] - c[4] * _sin2[i];
      final mag2 = (nr * nr + ni * ni) / math.max(dr * dr + di * di, 1e-24);
      out[i] += 10 * math.log(math.max(mag2, 1e-24)) / math.ln10;
    }
  }

  // Parameters: [0] volume dB, then per peak (ln fc, ln q, gain).
  static List<double> _model(List<double> p) {
    final out = List<double>.filled(_grid.length, p[0]);
    for (var k = 0; k < _peakCount; k++) {
      final b = 1 + k * 3;
      if (p[b + 2].abs() < 1e-6) continue;
      _addResponse(
        PeqMath.coefficients(
          PeqFilter(PeqFilterType.peaking, math.exp(p[b]), p[b + 2], math.exp(p[b + 1])),
          _sampleRate,
        ),
        out,
      );
    }
    return out;
  }

  static List<double> _residuals(List<double> p, List<double> target) {
    final m = _model(p);
    return [for (var i = 0; i < m.length; i++) (m[i] - target[i]) * _weights[i]];
  }

  static double _cost(List<double> r) => r.fold(0.0, (s, v) => s + v * v);

  static List<double> _clamp(List<double> p) {
    final out = List.of(p);
    out[0] = out[0].clamp(-30.0, 30.0);
    for (var k = 0; k < _peakCount; k++) {
      final b = 1 + k * 3;
      out[b] = out[b].clamp(math.log(5.0), math.log(_maxFc));
      out[b + 1] = out[b + 1].clamp(math.log(0.1), math.log(6.0));
      out[b + 2] = out[b + 2].clamp(-30.0, 30.0);
    }
    return out;
  }

  static ShelfApprox _fit(PeqFilter shelf) {
    final target = List<double>.filled(_grid.length, 0);
    _addResponse(PeqMath.coefficients(shelf, _sampleRate), target);
    final g = shelf.gainDb;
    final f = shelf.frequencyHz;
    final low = shelf.type == PeqFilterType.lowShelf;
    // Two starts: the boost as bells on the shelf's plateau side, or the
    // whole gain as volume with the other side cut back by bells.
    final starts = <List<double>>[
      [
        0,
        math.log(low ? f * 0.35 : math.min(f * 1.35, _maxFc)), math.log(0.6), g,
        math.log(low ? f * 0.12 : math.min(f * 1.7, _maxFc)), math.log(1.0), 0,
        math.log(low ? f : f * 0.8), math.log(1.0), 0,
      ],
      [
        g,
        math.log(low ? f * 6 : f / 6), math.log(0.35), -g,
        math.log(low ? f * 60 : f / 60), math.log(0.35), -g * 0.5,
        math.log(low ? f * 2.2 : f / 2.2), math.log(0.8), -g * 0.3,
      ],
    ];
    List<double>? best;
    var bestCost = double.infinity;
    for (final start in starts) {
      final p = _lm(_clamp(start), target);
      final c = _cost(_residuals(p, target));
      if (c < bestCost) {
        bestCost = c;
        best = p;
      }
    }
    final p = best!;
    final model = _model(p);
    var maxErr = 0.0;
    for (var i = 0; i < _grid.length; i++) {
      if (_grid[i] > 16000) continue;
      maxErr = math.max(maxErr, (model[i] - target[i]).abs());
    }
    return ShelfApprox(
      p[0],
      [
        for (var k = 0; k < _peakCount; k++)
          if (p[1 + k * 3 + 2].abs() >= 0.01)
            PeqFilter(
              PeqFilterType.peaking,
              math.exp(p[1 + k * 3]),
              p[1 + k * 3 + 2],
              math.exp(p[1 + k * 3 + 1]),
            ),
      ],
      maxErr,
    );
  }

  static List<double> _lm(List<double> start, List<double> target) {
    var p = start;
    var r = _residuals(p, target);
    var cost = _cost(r);
    var lambda = 1e-2;
    final n = p.length;
    for (var it = 0; it < 120; it++) {
      final jac = List.generate(_grid.length, (_) => List<double>.filled(n, 0));
      for (var a = 0; a < n; a++) {
        final h = (a == 0 || (a - 1) % 3 == 2) ? 1e-3 : 1e-4;
        final shifted = List.of(p)..[a] += h;
        final rs = _residuals(shifted, target);
        for (var k = 0; k < _grid.length; k++) {
          jac[k][a] = (rs[k] - r[k]) / h;
        }
      }
      final jtj = List.generate(n, (_) => List<double>.filled(n, 0));
      final jtr = List<double>.filled(n, 0);
      for (var k = 0; k < _grid.length; k++) {
        for (var a = 0; a < n; a++) {
          final ja = jac[k][a];
          if (ja == 0) continue;
          jtr[a] += ja * r[k];
          for (var b = 0; b < n; b++) {
            jtj[a][b] += ja * jac[k][b];
          }
        }
      }
      var improved = false;
      for (var attempt = 0; attempt < 6 && !improved; attempt++) {
        final sys = List.generate(
          n,
          (a) => List.generate(n, (b) => jtj[a][b] + (a == b ? lambda * (jtj[a][a] + 1e-6) : 0)),
        );
        final step = _solve(sys, [for (final v in jtr) -v]);
        if (step == null) break;
        final cand = _clamp([for (var i = 0; i < n; i++) p[i] + step[i]]);
        final rc = _residuals(cand, target);
        final cc = _cost(rc);
        if (cc < cost) {
          p = cand;
          r = rc;
          cost = cc;
          lambda = math.max(lambda * 0.4, 1e-7);
          improved = true;
        } else {
          lambda = math.min(lambda * 4, 1e6);
        }
      }
      if (!improved) break;
    }
    return p;
  }

  static List<double>? _solve(List<List<double>> a, List<double> b) {
    final n = b.length;
    final m = [for (final row in a) List.of(row)];
    final v = List.of(b);
    for (var col = 0; col < n; col++) {
      var pivot = col;
      for (var row = col + 1; row < n; row++) {
        if (m[row][col].abs() > m[pivot][col].abs()) pivot = row;
      }
      if (m[pivot][col].abs() < 1e-12) return null;
      if (pivot != col) {
        final t = m[pivot];
        m[pivot] = m[col];
        m[col] = t;
        final tv = v[pivot];
        v[pivot] = v[col];
        v[col] = tv;
      }
      for (var row = col + 1; row < n; row++) {
        final factor = m[row][col] / m[col][col];
        if (factor == 0) continue;
        for (var k = col; k < n; k++) {
          m[row][k] -= factor * m[col][k];
        }
        v[row] -= factor * v[col];
      }
    }
    final x = List<double>.filled(n, 0);
    for (var row = n - 1; row >= 0; row--) {
      var sum = v[row];
      for (var k = row + 1; k < n; k++) {
        sum -= m[row][k] * x[k];
      }
      x[row] = sum / m[row][row];
    }
    return x;
  }
}
