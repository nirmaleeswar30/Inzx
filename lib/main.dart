import 'dart:async';
import 'dart:ui';
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
import 'core/utils/app_logger.dart';
import 'l10n/generated/app_localizations.dart';
import 'services/audio_handler.dart';
import 'services/github_release_update_service.dart';
import 'services/jams/jams_background_service_native.dart';
import 'services/notification_service.dart';
import 'services/shorebird_update_service.dart';
import 'services/supabase_config.dart';
import 'services/discord/discord_rpc_service.dart';
import 'providers/providers.dart';
import 'providers/repository_providers.dart';
import 'screens/music_app.dart';
import 'screens/onboarding_screen.dart';
import 'core/liquid_glass/liquid_glass_kit.dart' show GlassShaders;
import 'services/deep_link_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'screens/widgets/whats_new_dialog.dart';
import 'services/scrobbling/scrobble_service.dart';

InzxAudioHandler? audioHandler;
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();
final GlobalKey<NavigatorState> rootNavigatorKey =
    GlobalKey<NavigatorState>();
VoidCallback? requestAppRestart;

/// True on a fresh install until onboarding finishes.
bool showOnboarding = false;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize rolling application logger and crash tracing
  await AppLogger.init();

  // Global Flutter UI crash interceptor
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    AppLogger.e(
      'FlutterError',
      details.exceptionAsString(),
      details.exception,
      details.stack,
    );
  };

  // Global asynchronous & platform error interceptor
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    AppLogger.e('PlatformError', error.toString(), error, stack);
    return true;
  };

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

  // Load the "share native YouTube Music links" preference so shares honor it
  // even before the settings screen is opened.
  try {
    final prefs = await SharedPreferences.getInstance();
    DeepLinkHandler.useNativeYtMusicLinks =
        prefs.getBool(DeepLinkHandler.shareNativeLinksPrefKey) ?? false;
    // Existing installs (they have already seen a changelog) skip onboarding.
    showOnboarding =
        !(prefs.getBool(OnboardingScreen.completedPrefKey) ?? false) &&
        prefs.getString('last_seen_changelog_version') == null;
  } catch (_) {}

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

  // Initialize Discord Rich Presence service
  try {
    await DiscordRpcService.instance.init();
    debugPrint('✅ Discord RPC service initialized');
  } catch (e) {
    debugPrint('⚠️ Discord RPC service initialization failed: $e');
  }

  // Liquid glass lens + highlight shaders (glass falls back to blur + tint
  // without a lens if they can't load).
  await GlassShaders.ensureLoaded();

  // Last.fm / ListenBrainz: follows the player from here on (no-op until an
  // account is connected).
  unawaited(ScrobbleService.instance.start());

  // Set preferred orientations & enable edge-to-edge
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Consume OAuth callback deep links (e.g. inzxdiscord://oauth2/callback)
  // before Flutter's default router tries to navigate to them and throws
  // "Could not find a generator for route /callback". These are handled by
  // app_links inside the Discord OAuth flow, not by named routes.
  WidgetsBinding.instance.addObserver(_OAuthDeepLinkGuard());

  runApp(RestartableApp(audioHandler: audioHandler));
}

/// Swallows platform route pushes for our OAuth redirect so they don't reach
/// the Navigator (the app uses imperative navigation + app_links, not named
/// routes). Returning true marks the route information as handled.
class _OAuthDeepLinkGuard with WidgetsBindingObserver {
  @override
  Future<bool> didPushRouteInformation(RouteInformation routeInformation) async {
    final uri = routeInformation.uri;
    if (uri.scheme == 'inzxdiscord' ||
        uri.path == '/callback' ||
        uri.path.endsWith('/oauth2/callback')) {
      return true;
    }
    return false;
  }
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

    // Register like callbacks with audioHandler
    audioHandler?.registerLikeCallbacks(
      checkIsLiked: (trackId) => ref.read(isTrackLikedProvider(trackId)),
      toggleLike: (track) => toggleTrackLike(ref: ref, track: track),
    );

    // Warm cache on startup (background task)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cacheWarmer = ref.read(cacheWarmingServiceProvider);
      cacheWarmer.warmCache(preTrendingMusic: true, prelikedSongs: true);
      _runUpdateChecks();
      DeepLinkHandler.instance.initialize(context, ref);
    });
  }

  Future<void> _runUpdateChecks() async {
    _checkFirstLaunchChangelog();

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

  Future<void> _checkFirstLaunchChangelog() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      final lastSeenVersion = prefs.getString('last_seen_changelog_version');

      if (showOnboarding) {
        // Fresh install: onboarding is the introduction, not a changelog.
        await prefs.setString('last_seen_changelog_version', currentVersion);
        return;
      }

      if (lastSeenVersion != currentVersion) {
        final releaseInfo = await GithubReleaseUpdateService.instance.fetchLatestReleaseInfo();
        if (!mounted) return;
        final navContext = rootNavigatorKey.currentContext ?? context;
        if (!navContext.mounted) return;
        await WhatsNewDialog.show(navContext, releaseInfo: releaseInfo, currentVersion: currentVersion);
        await prefs.setString('last_seen_changelog_version', currentVersion);
      }
    } catch (e) {
      debugPrint('Error showing changelog dialog: $e');
    }
  }

  void _finishOnboarding() {
    showOnboarding = false;
    rootNavigatorKey.currentState?.pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 600),
        pageBuilder: (_, _, _) => const MusicApp(),
        transitionsBuilder: (_, animation, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        ),
      ),
    );
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
    ref.listen(likedSongsProvider, (previous, next) {
      audioHandler?.refreshPlaybackControls();
    });

    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(appLocaleProvider);

    // Get accent color
    final accentColorEnum = ref.watch(accentColorProvider);
    final customAccent = ref.watch(customAccentColorProvider);
    final lightAccent = getAccentColor(accentColorEnum, isDark: false, customColor: customAccent);
    final darkAccent = getAccentColor(accentColorEnum, isDark: true, customColor: customAccent);

    ThemeData lightTheme = InzxTheme.lightWithAccent(lightAccent);
    ThemeData darkTheme = InzxTheme.darkWithAccent(darkAccent);

    return MaterialApp(
      navigatorKey: rootNavigatorKey,
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
      home: showOnboarding
          ? OnboardingScreen(onFinished: _finishOnboarding)
          : const MusicApp(),
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
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarDividerColor: Colors.transparent,
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
