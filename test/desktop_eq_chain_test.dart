import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:inzx/services/autoeq/peq.dart';
import 'package:inzx/services/desktop/eq_chain.dart';

void main() {
  group('EqChain', () {
    test('flat equaliser means no filter at all', () {
      expect(EqChain.equalizer(List.filled(7, 0)).toMpv(shelves: false), const MpvEq('', 0));
    });

    test('bells map one to one onto lavfi equalizer, with the preamp', () {
      final m = EqChain.equalizer([0, 4, 0, 0, -2, 0, 0]).toMpv(shelves: false);
      expect(
        m.af,
        'format=format=floatp,'
        '@inzxeq:lavfi=[equalizer=f=150:t=q:w=1:g=4,equalizer=f=2500:t=q:w=1:g=-2]',
      );
      expect(m.gainDb, -2);
    });

    test('shelves use lowshelf / highshelf when the libmpv has them', () {
      final af = EqChain.equalizer([3, 0, 0, 0, 0, 0, -3]).toMpv(shelves: true).af;
      expect(af, contains('lowshelf=f=60:t=q:w=0.7071:g=3'));
      expect(af, contains('highshelf=f=14000:t=q:w=0.7071:g=-3'));
    });

    test('without shelves they become volume + equalizer bells', () {
      final af = EqChain.equalizer([6, 0, 0, 0, 0, 0, 0]).toMpv(shelves: false).af;
      expect(af, isNot(contains('shelf')));
      expect(af, isNot(contains('volume')));
      expect(RegExp('equalizer=').allMatches(af).length, greaterThanOrEqualTo(1));
    });
  });

  group('ShelfApprox', () {
    // The equaliser's shelves (60 Hz / 14 kHz, slope 1) over their whole
    // range, and AutoEQ's usual 105 Hz / 10 kHz Q 0.7 shelves.
    final cases = <PeqFilter>[
      for (final g in [-12.0, -6.0, -3.0, 3.0, 6.0, 12.0]) ...[
        PeqFilter(PeqFilterType.lowShelf, 60, g, math.sqrt1_2),
        PeqFilter(PeqFilterType.highShelf, 14000, g, math.sqrt1_2),
        PeqFilter(PeqFilterType.lowShelf, 105, g, 0.7),
        PeqFilter(PeqFilterType.highShelf, 10000, g, 0.7),
      ],
    ];
    for (final shelf in cases) {
      test('${shelf.type.code} ${shelf.frequencyHz} Hz ${shelf.gainDb} dB', () {
        final a = ShelfApprox.of(shelf);
        // ignore: avoid_print
        print('${shelf.type.code} ${shelf.frequencyHz.round()} Hz ${shelf.gainDb} dB: '
            'max error ${a.maxErrorDb.toStringAsFixed(2)} dB (20 Hz - 16 kHz)');
        expect(a.maxErrorDb, lessThan(1.5));
        expect(a.peaks.length, lessThanOrEqualTo(3));
      });
    }
  });

  group('ParametricEqText', () {
    test('reads an AutoEQ profile', () {
      final s = ParametricEqText.parse('''
Preamp: -6.4 dB
Filter 1: ON LSC Fc 105 Hz Gain 5.7 dB Q 0.70
Filter 2: ON PK Fc 154 Hz Gain -2.6 dB Q 0.45
Filter 3: ON HSC Fc 10000 Hz Gain -3.1 dB Q 0.70
''')!;
      expect(s.preampDb, -6.4);
      expect(s.filters.length, 3);
      expect(s.filters[0].type, PeqFilterType.lowShelf);
      expect(s.filters[1].q, 0.45);
      expect(s.filters[2].gainDb, -3.1);
    });
  });

  group('PeqFitter', () {
    test('refits a curve closely', () {
      final base = [
        const PeqFilter(PeqFilterType.lowShelf, 105, 4, 0.7),
        const PeqFilter(PeqFilterType.peaking, 3000, -3, 2),
        const PeqFilter(PeqFilterType.highShelf, 8000, 2, 0.7),
      ];
      final grid = PeqMath.logGrid;
      final desired = [for (final f in grid) PeqMath.filtersDb(base, f)];
      final fit = PeqFitter.fit(desired, grid);
      var worst = 0.0;
      for (var i = 0; i < grid.length; i++) {
        if (grid[i] > 10000) continue;
        worst = math.max(worst, (PeqMath.filtersDb(fit.filters, grid[i]) - desired[i]).abs());
      }
      expect(worst, lessThan(0.5));
    });
  });
}
