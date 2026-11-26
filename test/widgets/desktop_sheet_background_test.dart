import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inzx/core/utils/platform_utils.dart';
import 'package:inzx/providers/music_providers.dart';
import 'package:inzx/screens/widgets/ai_lyrics_settings_sheet.dart';
import 'package:inzx/screens/widgets/color_picker_dialog.dart';
import 'package:inzx/screens/widgets/lyrics_menu_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('desktop sheets are opaque in ${brightness.name} mode', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final theme = ThemeData(
        brightness: brightness,
        scaffoldBackgroundColor: Colors.transparent,
      );
      const sheets = {
        'AI Translation Settings': AiLyricsSettingsSheet(),
        'Lyrics Options': LyricsMenuSheet(),
      };
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [showNerdStatsProvider.overrideWithValue(false)],
          child: MaterialApp(
            theme: theme,
            navigatorKey: navigator,
            home: const Scaffold(),
          ),
        ),
      );

      for (final entry in sheets.entries) {
        showModalBottomSheet<void>(
          context: navigator.currentContext!,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => entry.value,
        );
        await tester.pumpAndSettle();
        final title = find.text(entry.key);
        expect(title, findsOneWidget);
        expect(
          find.ancestor(
            of: title,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Material &&
                  widget.color == theme.colorScheme.surface,
            ),
          ),
          findsOneWidget,
        );
        navigator.currentState!.pop();
        await tester.pumpAndSettle();
      }

      ColorPickerDialog.show(
        navigator.currentContext!,
        initialColor: Colors.red,
      );
      await tester.pumpAndSettle();
      final picker = find.byType(ColorPickerDialog);
      final filter = find.descendant(
        of: picker,
        matching: find.byType(BackdropFilter),
      );
      expect(tester.widget<BackdropFilter>(filter).enabled, isFalse);
      final surface = brightness == Brightness.dark
          ? const Color(0xFF141414)
          : Colors.white;
      expect(
        find.descendant(
          of: picker,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is DecoratedBox &&
                widget.decoration is BoxDecoration &&
                (widget.decoration as BoxDecoration).color == surface,
          ),
        ),
        findsWidgets,
      );
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
    }, skip: !isDesktop);
  }
}
