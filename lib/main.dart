import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:url_launcher/url_launcher.dart';
import 'core/design_system/design_system.dart';
import 'core/l10n/app_localizations_x.dart';
import 'core/providers/locale_provider.dart';
import 'core/providers/theme_provider.dart';
import 'core/services/cache/hive_service.dart';
import 'l10n/generated/app_localizations.dart';
import 'services/audio_handler.dart';
import 'services/github_release_update_service.dart';
import 'services/jams/jams_background_service_native.dart';
import 'services/notification_service.dart';
import 'services/shorebird_update_service.dart';
import 'services/supabase_config.dart';
import 'providers/providers.dart';
import 'providers/repository_providers.dart';
import 'screens/music_app.dart';

InzxAudioHandler? audioHandler;
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();
VoidCallback? requestAppRestart;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize environment variables
  try {
    await dotenv.load(fileName: ".env");
    debugPrint('✅ Dotenv initialized successfully');
  } catch (e) {
    debugPrint('⚠️ Dotenv initialization failed: $e');
  }

  // Initialize Hive for caching
  try {
    await HiveService.init();
    debugPrint('✅ Hive initialized successfully');
  } catch (e) {
    debugPrint('⚠️ Hive initialization failed: $e');
  }

  // Initialize Supabase for Jams feature
  try {
    await SupabaseConfig.initialize();
  } catch (e) {
    debugPrint('⚠️ Supabase initialization failed: $e');
  }

  // Initialize audio service for background playback
  try {
    audioHandler = await initAudioService();
  } catch (e) {
    debugPrint('Audio service initialization failed: $e');
  }

  // Initialize notification service for download progress
  try {
    await DownloadNotificationService.instance.initialize();
    debugPrint('✅ Notification service initialized successfully');
  } catch (e) {
    debugPrint('⚠️ Notification service initialization failed: $e');
  }
  // Initialize native bridge for Jams foreground service (Android)
  try {
    await JamsBackgroundService.instance.initialize();
  } catch (e) {
    debugPrint('Jams background service initialization failed: $e');
  }
  // Set preferred orientations
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  runApp(RestartableApp(audioHandler: audioHandler));
}

class RestartableApp extends StatefulWidget {
  final InzxAudioHandler? audioHandler;

  const RestartableApp({super.key, required this.audioHandler});

  static void restart(BuildContext context) {
    final state = context.findAncestorStateOfType<_RestartableAppState>();
    state?.restart();
  }

  @override
  State<RestartableApp> createState() => _RestartableAppState();
}

class _RestartableAppState extends State<RestartableApp> {
  Key _providerScopeKey = UniqueKey();

  @override
  void initState() {
    super.initState();
    requestAppRestart = restart;
  }

  @override
  void dispose() {
    if (identical(requestAppRestart, restart)) {
      requestAppRestart = null;
    }
    super.dispose();
  }

  void restart() {
    setState(() {
      _providerScopeKey = UniqueKey();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      key: _providerScopeKey,
      overrides: [
        if (widget.audioHandler != null)
          audioHandlerProvider.overrideWithValue(widget.audioHandler),
      ],
      child: const InzxApp(),
    );
  }
}

/// The root widget of the Inzx music app
class InzxApp extends ConsumerStatefulWidget {
  const InzxApp({super.key});

  @override
  ConsumerState<InzxApp> createState() => _InzxAppState();
}

class _InzxAppState extends ConsumerState<InzxApp> {
  @override
  void initState() {
    super.initState();

    // Warm cache on startup (background task)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cacheWarmer = ref.read(cacheWarmingServiceProvider);
      cacheWarmer.warmCache(preTrendingMusic: true, prelikedSongs: true);
      _runUpdateChecks();
    });
  }

  Future<void> _runUpdateChecks() async {
    final didPatchUpdate = await ShorebirdUpdateService.instance
        .checkForUpdates();
    if (!mounted) return;

    if (didPatchUpdate) {
      _showPatchUpdateBanner();
      return;
    }

    final releaseInfo = await GithubReleaseUpdateService.instance
        .checkForNewRelease();
    if (!mounted || releaseInfo == null) return;

    _showNewReleaseBanner(releaseInfo);
  }

  void _showPatchUpdateBanner() {
    final messenger = rootScaffoldMessengerKey.currentState;
    if (messenger == null) return;
    final l10n = context.l10n;
    messenger.clearMaterialBanners();
    messenger.showMaterialBanner(
      MaterialBanner(
        content: Text(l10n.updateDownloadedBanner),
        actions: [
          TextButton(
            onPressed: () {
              // Close the app so the update applies on next launch.
              SystemNavigator.pop();
            },
            child: Text(l10n.restart),
          ),
          TextButton(
            onPressed: () => messenger.hideCurrentMaterialBanner(),
            child: Text(l10n.dismiss),
          ),
        ],
      ),
    );
  }

  void _showNewReleaseBanner(GithubReleaseInfo releaseInfo) {
    final messenger = rootScaffoldMessengerKey.currentState;
    if (messenger == null) return;
    final l10n = context.l10n;

    messenger.clearMaterialBanners();
    messenger.showMaterialBanner(
      MaterialBanner(
        content: Text(
          l10n.newVersionAvailableBanner(releaseInfo.latestVersion),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final uri = Uri.parse(releaseInfo.downloadUrl);
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            },
            child: Text(l10n.download),
          ),
          TextButton(
            onPressed: () => messenger.hideCurrentMaterialBanner(),
            child: Text(l10n.later),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(appLocaleProvider);

    // Get accent color
    final accentColorEnum = ref.watch(accentColorProvider);
    final lightAccent = getAccentColor(accentColorEnum, isDark: false);
    final darkAccent = getAccentColor(accentColorEnum, isDark: true);

    ThemeData lightTheme = InzxTheme.lightWithAccent(lightAccent);
    ThemeData darkTheme = InzxTheme.darkWithAccent(darkAccent);

    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      locale: locale,
      supportedLocales: supportedAppLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: toFlutterThemeMode(themeMode),
      home: const MusicApp(),
      builder: (context, child) {
        // Update system UI
        final brightness = Theme.of(context).brightness;
        SystemChrome.setSystemUIOverlayStyle(
          SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: brightness == Brightness.light
                ? Brightness.dark
                : Brightness.light,
            statusBarBrightness: brightness,
            systemNavigationBarColor: brightness == Brightness.light
                ? InzxColors.background
                : InzxColors.darkBackground,
            systemNavigationBarIconBrightness: brightness == Brightness.light
                ? Brightness.dark
                : Brightness.light,
          ),
        );

        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(
              MediaQuery.of(context).textScaler.scale(1.0).clamp(0.8, 1.2),
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
