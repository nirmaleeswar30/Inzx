import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'core/design_system/design_system.dart';
import 'core/l10n/app_localizations_x.dart';
import 'core/providers/locale_provider.dart';
import 'core/providers/theme_provider.dart';
import 'core/services/cache/hive_service.dart';
import 'core/utils/app_logger.dart';
import 'core/utils/app_restart.dart';
import 'core/utils/platform_utils.dart';
import 'l10n/generated/app_localizations.dart';
import 'services/audio_handler.dart';
import 'services/desktop/desktop_bootstrap.dart';
import 'services/ios/ios_bootstrap.dart';
import 'services/widget_sync_service.dart';
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
import 'screens/widgets/update_dialog.dart';
import 'screens/widgets/desktop_shell.dart';
import 'services/scrobbling/scrobble_service.dart';
import 'services/desktop/desktop_updater.dart';
import 'services/inzx_connect_remote.dart';
import 'services/listening_stats_service.dart';
import 'services/dynamic_font_service.dart';
import 'services/inzx_connect_service.dart';

InzxAudioHandler? audioHandler;
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();
final GlobalKey<NavigatorState> rootNavigatorKey =
    GlobalKey<NavigatorState>();
VoidCallback? requestAppRestart;

/// True on a fresh install until onboarding finishes.
bool showOnboarding = false;

void main([List<String> args = const []]) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Desktop single-instance check: if another instance is already running,
  // forward args / focus signal to it and exit immediately before doing any
  // expensive initialization.
  if (isDesktop) {
    try {
      final isSecondary = await handleDesktopSingleInstance(args);
      if (isSecondary) return;
    } catch (e) {
      debugPrint('Single-instance check error: $e');
    }

    for (final arg in args) {
      if (arg.startsWith('inzx://') ||
          arg.startsWith('https://${DeepLinkHandler.shareHost}/')) {
        final uri = Uri.tryParse(arg);
        if (uri != null) {
          DeepLinkHandler.instance.handleExternalUrl(uri);
        }
        break;
      }
    }
  }

  // Initialize rolling application logger and crash tracing
  await AppLogger.init();

  // Initialize dynamic font fallback loader (loads cached fonts into engine)
  try {
    await DynamicFontService.instance.init();
  } catch (e) {
    AppLogger.e('FontService', 'DynamicFontService init error', e);
  }

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

  if (isDesktop) {
    try {
      await initDesktopPlatform();
    } catch (e, stack) {
      AppLogger.e('Desktop', 'Desktop startup failed', e, stack);
    }
  }

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

  // iOS: reopen picked music folders, start the audio tap's equaliser.
  if (isIOS) {
    try {
      await initIosPlatform();
    } catch (e, stack) {
      AppLogger.e('iOS', 'iOS startup failed', e, stack);
    }
  }

  // Listening statistics: follows the player from here on.
  unawaited(ListeningStatsService.instance.start());

  try {
    final prefs = await SharedPreferences.getInstance();
    // Existing installs (they have already seen a changelog) skip onboarding.
    showOnboarding =
        !(prefs.getBool(OnboardingScreen.completedPrefKey) ?? false) &&
        prefs.getString('last_seen_changelog_version') == null;
    desktopShellVisible.value = !showOnboarding;
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

  // iOS Home Screen widget buttons (App Intents running in this process).
  final handler = audioHandler;
  if (isIOS && handler != null) {
    WidgetSyncService.attachActionHandler((action) async {
      switch (action) {
        case 'playPause':
          handler.playbackState.value.playing ? await handler.pause() : await handler.play();
        case 'next':
          await handler.skipToNext();
        case 'previous':
          await handler.skipToPrevious();
        case 'like':
          await handler.customAction('toggle_like');
        case 'shuffle':
          await handler.toggleShuffle();
      }
    });
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

  // Inzx Connect: listens for paired devices' commands (play here, play on,
  // remote controls). A no-op on installs that never opened Connect.
  if (InzxConnectService.isSupported) {
    unawaited(InzxConnectRemote.instance.start());
  }

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
    await _checkFirstLaunchChangelog();

    final didPatchUpdate = await ShorebirdUpdateService.instance
        .checkForUpdates();
    if (!mounted) return;

    if (didPatchUpdate) {
      _showPatchUpdateBanner();
      return;
    }

    // Desktop: the updater downloads it in the background and the top bar
    // shows it; no dialog.
    if (isDesktop) {
      unawaited(DesktopUpdater.instance.check());
      return;
    }

    final releaseInfo = await GithubReleaseUpdateService.instance
        .checkForNewRelease(ignoreReleaseMode: true);
    if (!mounted || releaseInfo == null) return;

    final navContext = rootNavigatorKey.currentContext ?? context;
    if (!navContext.mounted) return;

    await UpdateAvailableDialog.show(navContext, releaseInfo: releaseInfo);
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
    desktopShellVisible.value = true;
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
              closeAppForUpdate(context);
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
      scrollBehavior: isDesktop ? const DesktopScrollBehavior() : null,
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
          child: isDesktop
              ? DesktopShortcuts(
                  child: DesktopAppFrame(
                    child: child ?? const SizedBox.shrink(),
                  ),
                )
              : child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
