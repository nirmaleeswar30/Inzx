// Parametric EQ model, math, fitter and ParametricEQ.txt parser: a Dart port
// of LastWave's PeqModel.kt and PeqFitter.kt (android/.../lastwave/app/data/
// autoeq), for desktop AutoEQ. Android keeps running the Kotlin originals.
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version.

import 'dart:math' as math;

/// Filter shapes (ids match ParametricEqProcessor / ParametricEq.h).
enum PeqFilterType {
  peaking(0, 'PK', true),
  lowShelf(1, 'LSC', true),
  highShelf(2, 'HSC', true),
  lowPass(3, 'LPQ', false),
  highPass(4, 'HPQ', false);

  const PeqFilterType(this.nativeId, this.code, this.hasGain);
  final int nativeId;
  final String code;
  final bool hasGain;

  static PeqFilterType? fromCode(String code) => switch (code.toUpperCase()) {
    'PK' || 'PEQ' || 'PEAK' || 'PEAKING' => peaking,
    'LSC' || 'LS' || 'LSQ' || 'LOWSHELF' => lowShelf,
    'HSC' || 'HS' || 'HSQ' || 'HIGHSHELF' => highShelf,
    'LP' || 'LPQ' || 'LOWPASS' => lowPass,
    'HP' || 'HPQ' || 'HIGHPASS' => highPass,
    _ => null,
  };

  /// Kotlin's enum name, kept in the stored JSON.
  String get storedName => switch (this) {
    peaking => 'PEAKING',
    lowShelf => 'LOW_SHELF',
    highShelf => 'HIGH_SHELF',
    lowPass => 'LOW_PASS',
    highPass => 'HIGH_PASS',
  };

  static PeqFilterType fromStored(String? name) =>
      values.firstWhere((t) => t.storedName == name, orElse: () => peaking);
}

class PeqFilter {
  const PeqFilter(
    this.type,
    this.frequencyHz,
    this.gainDb,
    this.q, {
    this.enabled = true,
  });

  final PeqFilterType type;
  final double frequencyHz;
  final double gainDb;
  final double q;
  final bool enabled;

  Map<String, Object?> toJson() => {
    'type': type.storedName,
    'frequencyHz': frequencyHz,
    'gainDb': gainDb,
    'q': q,
    'enabled': enabled,
  };

  factory PeqFilter.fromJson(Map m) => PeqFilter(
    PeqFilterType.fromStored(m['type'] as String?),
    (m['frequencyHz'] as num?)?.toDouble() ?? 1000,
    (m['gainDb'] as num?)?.toDouble() ?? 0,
    (m['q'] as num?)?.toDouble() ?? 0.7,
    enabled: m['enabled'] != false,
  );
}

class PeqSettings {
  const PeqSettings({this.preampDb = 0, this.filters = const []});

  final double preampDb;
  final List<PeqFilter> filters;

  static const maxFilters = 20;

  bool get isFlat =>
      preampDb.abs() < 0.001 &&
      !filters.any((f) => f.enabled && (!f.type.hasGain || f.gainDb.abs() >= 0.001));

  Map<String, Object?> toJson() => {
    'preampDb': preampDb,
    'filters': [for (final f in filters) f.toJson()],
  };

  factory PeqSettings.fromJson(Map m) => PeqSettings(
    preampDb: (m['preampDb'] as num?)?.toDouble() ?? 0,
    filters: [
      for (final f in (m['filters'] as List? ?? const [])) PeqFilter.fromJson(f as Map),
    ],
  );
}

/// Biquad magnitude math, identical to the RBJ designs the processors run.
abstract final class PeqMath {
  static const defaultSampleRate = 48000.0;

  /// 1/12-octave grid, 20 Hz .. 20.48 kHz (same as the bundled target deltas).
  static final List<double> logGrid = List.unmodifiable(
    List.generate(121, (i) => 20.0 * math.pow(2.0, i / 12.0)),
  );

  static double filterDb(
    PeqFilter filter,
    double frequency, [
    double sampleRate = defaultSampleRate,
  ]) {
    if (!filter.enabled) return 0;
    if (filter.type.hasGain && filter.gainDb.abs() < 0.001) return 0;
    if (filter.frequencyHz >= sampleRate * 0.49) return 0;
    final c = coefficients(filter, sampleRate);
    return _magnitudeDb(c, frequency, sampleRate);
  }

  static double _magnitudeDb(List<double> c, double frequency, double sampleRate) {
    final w = 2.0 * math.pi * frequency.clamp(1.0, sampleRate * 0.49) / sampleRate;
    final cos1 = math.cos(w), sin1 = math.sin(w);
    final cos2 = math.cos(2 * w), sin2 = math.sin(2 * w);
    final nr = c[0] + c[1] * cos1 + c[2] * cos2;
    final ni = -c[1] * sin1 - c[2] * sin2;
    final dr = 1.0 + c[3] * cos1 + c[4] * cos2;
    final di = -c[3] * sin1 - c[4] * sin2;
    final mag = math.sqrt((nr * nr + ni * ni) / math.max(dr * dr + di * di, 1e-24));
    return 20.0 * math.log(math.max(mag, 1e-12)) / math.ln10;
  }

  /// Total response in dB (preamp included).
  static double responseDb(
    PeqSettings settings,
    double frequency, [
    double sampleRate = defaultSampleRate,
  ]) =>
      settings.preampDb + filtersDb(settings.filters, frequency, sampleRate);

  static double filtersDb(
    List<PeqFilter> filters,
    double frequency, [
    double sampleRate = defaultSampleRate,
  ]) {
    var sum = 0.0;
    for (final f in filters) {
      sum += filterDb(f, frequency, sampleRate);
    }
    return sum;
  }

  /// AutoEQ's rule: negative preamp equal to the largest boost, rounded down
  /// to 0.1 dB.
  static double autoPreampDb(List<PeqFilter> filters, [List<double>? grid]) {
    var maxBoost = double.negativeInfinity;
    for (final f in grid ?? logGrid) {
      maxBoost = math.max(maxBoost, filtersDb(filters, f));
    }
    if (maxBoost <= 0) return 0;
    return -((maxBoost * 10.0).ceil() / 10.0);
  }

  /// b0, b1, b2, a1, a2 normalised by a0.
  static List<double> coefficients(PeqFilter filter, double sampleRate) {
    final f = filter.frequencyHz.clamp(10.0, sampleRate * 0.49);
    final w = 2.0 * math.pi * f / sampleRate;
    final cs = math.cos(w);
    final alpha = math.sin(w) / (2.0 * math.max(filter.q, 0.05));
    final a = math.pow(10.0, filter.gainDb / 40.0).toDouble();
    double b0, b1, b2, a0, a1, a2;
    switch (filter.type) {
      case PeqFilterType.lowShelf:
        final k = 2 * math.sqrt(a) * alpha;
        b0 = a * ((a + 1) - (a - 1) * cs + k);
        b1 = 2 * a * ((a - 1) - (a + 1) * cs);
        b2 = a * ((a + 1) - (a - 1) * cs - k);
        a0 = (a + 1) + (a - 1) * cs + k;
        a1 = -2 * ((a - 1) + (a + 1) * cs);
        a2 = (a + 1) + (a - 1) * cs - k;
      case PeqFilterType.highShelf:
        final k = 2 * math.sqrt(a) * alpha;
        b0 = a * ((a + 1) + (a - 1) * cs + k);
        b1 = -2 * a * ((a - 1) + (a + 1) * cs);
        b2 = a * ((a + 1) + (a - 1) * cs - k);
        a0 = (a + 1) - (a - 1) * cs + k;
        a1 = 2 * ((a - 1) - (a + 1) * cs);
        a2 = (a + 1) - (a - 1) * cs - k;
      case PeqFilterType.lowPass:
        b0 = (1 - cs) / 2;
        b1 = 1 - cs;
        b2 = (1 - cs) / 2;
        a0 = 1 + alpha;
        a1 = -2 * cs;
        a2 = 1 - alpha;
      case PeqFilterType.highPass:
        b0 = (1 + cs) / 2;
        b1 = -(1 + cs);
        b2 = (1 + cs) / 2;
        a0 = 1 + alpha;
        a1 = -2 * cs;
        a2 = 1 - alpha;
      case PeqFilterType.peaking:
        b0 = 1 + alpha * a;
        b1 = -2 * cs;
        b2 = 1 - alpha * a;
        a0 = 1 + alpha / a;
        a1 = -2 * cs;
        a2 = 1 - alpha / a;
    }
    return [b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0];
  }

  /// Low shelf used for the bass adjustment (AutoEQ's 105 Hz shelf shape).
  static double bassShelfDb(double gainDb, double frequency) =>
      filterDb(PeqFilter(PeqFilterType.lowShelf, 105.0, gainDb, 0.7), frequency);

  /// Tilt around 1 kHz in dB per octave.
  static double tiltDb(double dbPerOctave, double frequency) =>
      dbPerOctave * math.log(frequency / 1000.0) / math.ln2;

  /// Kotlin's floor(v / step + 0.5) * step.
  static double roundTo(double value, double step) => (value / step + 0.5).floorToDouble() * step;
}

/// Reads the AutoEQ / Equalizer APO "ParametricEQ.txt" format.
abstract final class ParametricEqText {
  static final _preamp = RegExp(r'^\s*Preamp:\s*([-+]?\d+(?:\.\d+)?)\s*dB', caseSensitive: false);
  static final _filter = RegExp(
    r'^\s*Filter\s*\d*\s*:\s*(ON|OFF)\s+([A-Z]+)\s+Fc\s+([-+]?\d+(?:\.\d+)?)\s*Hz'
    r'(?:\s+Gain\s+([-+]?\d+(?:\.\d+)?)\s*dB)?(?:\s+Q\s+([-+]?\d+(?:\.\d+)?))?',
    caseSensitive: false,
  );

  static PeqSettings? parse(String text) {
    var preamp = 0.0;
    final filters = <PeqFilter>[];
    for (final line in text.split(RegExp(r'\r?\n'))) {
      final p = _preamp.firstMatch(line);
      if (p != null) preamp = double.parse(p.group(1)!);
      final m = _filter.firstMatch(line);
      if (m == null) continue;
      final type = PeqFilterType.fromCode(m.group(2)!);
      if (type == null) continue;
      final fc = double.tryParse(m.group(3)!);
      if (fc == null) continue;
      filters.add(PeqFilter(
        type,
        fc,
        double.tryParse(m.group(4) ?? '') ?? 0.0,
        double.tryParse(m.group(5) ?? '') ?? 0.7071,
        enabled: m.group(1)!.toUpperCase() == 'ON',
      ));
      if (filters.length >= PeqSettings.maxFilters) break;
    }
    if (filters.isEmpty) return null;
    return PeqSettings(preampDb: preamp, filters: filters);
  }
}

/// Fits a parametric EQ to a desired correction curve with AutoEQ's default
/// layout: a fixed 105 Hz / Q 0.7 low shelf, eight peaking filters
/// (20 Hz - 10 kHz) and a high shelf (5 - 12 kHz, Q 0.4 - 0.7).
/// Levenberg-Marquardt on log-frequency / log-Q / gain parameters, greedy
/// initialisation on the largest residuals. Port of PeqFitter.kt.
abstract final class PeqFitter {
  static const _peaks = 8;
  static const _minPkFc = 20.0;
  static const _maxPkFc = 10000.0;
  static const _minQ = 0.18248;
  static const _maxQ = 6.0;
  static const _maxGain = 20.0;
  static const _shelfFc = 105.0;
  static const _shelfQ = 0.7;
  static const _hsMinFc = 5000.0;
  static const _hsMaxFc = 12000.0;
  static const _hsMinQ = 0.4;
  static const _hsMaxQ = 0.7;

  static PeqSettings fit(List<double> desiredDb, [List<double>? grid, int iterations = 80]) {
    final g = grid ?? PeqMath.logGrid;
    assert(desiredDb.length == g.length);
    final weights = [
      for (final f in g)
        f > 16000.0 ? 0.0 : (f > _maxPkFc ? 0.35 : 1.0),
    ];
    var params = _initialGuess(desiredDb, g);
    var lambda = 1e-2;
    var error = _cost(params, desiredDb, g, weights);
    for (var it = 0; it < iterations; it++) {
      final residual = _residuals(params, desiredDb, g, weights);
      final jacobian = _jacobian(params, desiredDb, g, weights, residual);
      final n = params.length;
      final jtj = List.generate(n, (_) => List<double>.filled(n, 0));
      final jtr = List<double>.filled(n, 0);
      for (var k = 0; k < g.length; k++) {
        for (var a = 0; a < n; a++) {
          final ja = jacobian[k][a];
          if (ja == 0.0) continue;
          jtr[a] += ja * residual[k];
          for (var b = 0; b < n; b++) {
            jtj[a][b] += ja * jacobian[k][b];
          }
        }
      }
      var improved = false;
      var attempts = 0;
      while (!improved && attempts < 6) {
        final system = List.generate(
          n,
          (a) => List.generate(
            n,
            (b) => jtj[a][b] + (a == b ? lambda * (jtj[a][a] + 1e-6) : 0.0),
          ),
        );
        final step = _solve(system, [for (final v in jtr) -v]);
        if (step == null) break;
        final candidate = _clampParams([for (var i = 0; i < n; i++) params[i] + step[i]]);
        final candidateError = _cost(candidate, desiredDb, g, weights);
        if (candidateError < error) {
          params = candidate;
          error = candidateError;
          lambda = math.max(lambda * 0.4, 1e-7);
          improved = true;
        } else {
          lambda = math.min(lambda * 4.0, 1e6);
        }
        attempts++;
      }
    }
    final filters = _toFilters(params);
    return PeqSettings(preampDb: PeqMath.autoPreampDb(filters, g), filters: filters);
  }

  // Parameter layout: [0] low-shelf gain, [1..3] high shelf (ln fc, ln q,
  // gain), then per peak (ln fc, ln q, gain).
  static List<PeqFilter> _toFilters(List<double> p) => [
    PeqFilter(PeqFilterType.lowShelf, _shelfFc, _round1(p[0]), _shelfQ),
    for (var i = 0; i < _peaks; i++)
      PeqFilter(
        PeqFilterType.peaking,
        _roundFc(math.exp(p[4 + i * 3])),
        _round1(p[4 + i * 3 + 2]),
        _round2(math.exp(p[4 + i * 3 + 1])),
      ),
    PeqFilter(PeqFilterType.highShelf, _roundFc(math.exp(p[1])), _round1(p[3]), _round2(math.exp(p[2]))),
  ];

  static double _responseAt(List<double> p, double f) {
    var total = PeqMath.filterDb(PeqFilter(PeqFilterType.lowShelf, _shelfFc, p[0], _shelfQ), f);
    total += PeqMath.filterDb(
      PeqFilter(PeqFilterType.highShelf, math.exp(p[1]), p[3], math.exp(p[2])),
      f,
    );
    for (var i = 0; i < _peaks; i++) {
      final b = 4 + i * 3;
      total += PeqMath.filterDb(
        PeqFilter(PeqFilterType.peaking, math.exp(p[b]), p[b + 2], math.exp(p[b + 1])),
        f,
      );
    }
    return total;
  }

  static List<double> _residuals(List<double> p, List<double> desired, List<double> g, List<double> w) => [
    for (var i = 0; i < g.length; i++)
      w[i] == 0.0 ? 0.0 : (_responseAt(p, g[i]) - desired[i]) * w[i],
  ];

  static double _cost(List<double> p, List<double> desired, List<double> g, List<double> w) {
    var s = 0.0;
    for (final r in _residuals(p, desired, g, w)) {
      s += r * r;
    }
    return s;
  }

  static List<List<double>> _jacobian(
    List<double> p,
    List<double> desired,
    List<double> g,
    List<double> w,
    List<double> base,
  ) {
    final n = p.length;
    final j = List.generate(g.length, (_) => List<double>.filled(n, 0));
    for (var a = 0; a < n; a++) {
      final h = _isGain(a) ? 1e-3 : 1e-4;
      final shifted = List.of(p);
      shifted[a] += h;
      final r = _residuals(shifted, desired, g, w);
      for (var k = 0; k < g.length; k++) {
        j[k][a] = (r[k] - base[k]) / h;
      }
    }
    return j;
  }

  static bool _isGain(int i) => i == 0 || i == 3 || (i >= 4 && (i - 4) % 3 == 2);

  static List<double> _clampParams(List<double> p) {
    final out = List.of(p);
    out[0] = out[0].clamp(-_maxGain, _maxGain);
    out[1] = out[1].clamp(math.log(_hsMinFc), math.log(_hsMaxFc));
    out[2] = out[2].clamp(math.log(_hsMinQ), math.log(_hsMaxQ));
    out[3] = out[3].clamp(-_maxGain, _maxGain);
    for (var i = 0; i < _peaks; i++) {
      final b = 4 + i * 3;
      out[b] = out[b].clamp(math.log(_minPkFc), math.log(_maxPkFc));
      out[b + 1] = out[b + 1].clamp(math.log(_minQ), math.log(_maxQ));
      out[b + 2] = out[b + 2].clamp(-_maxGain, _maxGain);
    }
    return out;
  }

  static List<double> _initialGuess(List<double> desired, List<double> g) {
    final p = List<double>.filled(4 + _peaks * 3, 0);
    double avg(Iterable<int> idx) {
      final l = idx.toList();
      if (l.isEmpty) return 0;
      final a = l.map((i) => desired[i]).reduce((x, y) => x + y) / l.length;
      return a.isFinite ? a : 0;
    }

    p[0] = avg([for (var i = 0; i < g.length; i++) if (g[i] <= 60.0) i]).clamp(-12.0, 12.0);
    p[1] = math.log(10000.0);
    p[2] = math.log(0.7);
    p[3] = avg([for (var i = 0; i < g.length; i++) if (g[i] >= 11000.0 && g[i] <= 16000.0) i])
        .clamp(-12.0, 12.0);
    final current = [for (final f in g) _responseAt(p, f)];
    for (var i = 0; i < _peaks; i++) {
      var bestIndex = -1;
      var bestValue = 0.0;
      for (var k = 0; k < g.length; k++) {
        if (g[k] < _minPkFc || g[k] > _maxPkFc) continue;
        final r = desired[k] - current[k];
        if (r.abs() > bestValue.abs()) {
          bestValue = r;
          bestIndex = k;
        }
      }
      final b = 4 + i * 3;
      if (bestIndex < 0 || bestValue.abs() < 0.05) {
        p[b] = math.log(1000.0 * (i + 1));
        p[b + 1] = math.log(1.0);
        p[b + 2] = 0.0;
        continue;
      }
      p[b] = math.log(g[bestIndex]);
      p[b + 1] = math.log(1.4);
      p[b + 2] = bestValue.clamp(-_maxGain, _maxGain);
      final added = PeqFilter(PeqFilterType.peaking, g[bestIndex], p[b + 2], 1.4);
      for (var k = 0; k < g.length; k++) {
        current[k] += PeqMath.filterDb(added, g[k]);
      }
    }
    return _clampParams(p);
  }

  /// Gaussian elimination with partial pivoting; null when singular.
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
        if (factor == 0.0) continue;
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

  static double _round1(double v) => PeqMath.roundTo(v, 0.1);
  static double _round2(double v) => PeqMath.roundTo(v, 0.01);
  static double _roundFc(double v) => PeqMath.roundTo(v, 1.0);
}
