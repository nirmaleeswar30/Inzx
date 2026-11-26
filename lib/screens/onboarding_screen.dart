import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:iconsax/iconsax.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/design_system/design_system.dart';
import '../core/providers/theme_provider.dart';
import '../core/utils/platform_utils.dart';
import 'inzx_connect_screen.dart';
import 'playlist_transfer_screen.dart';
import 'ytmusic_login_screen.dart';

/// First-launch onboarding with optional sign-in and setup guides.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onFinished});

  /// Called when the user finishes setup.
  final VoidCallback onFinished;

  static const String completedPrefKey = 'inzx_onboarding_complete';

  static Future<void> markComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(completedPrefKey, true);
  }

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _aurora;
  final PageController _pages = PageController();
  int _page = 0;
  bool _finishing = false;

  static const int _signInPage = 2;
  static const int _transferPage = 3;
  static const int _losslessPage = 4;
  static const int _connectPage = 5;
  static const int _pageCount = _connectPage + 1;
  static final _losslessGuide = Uri.parse(
    'https://inzx.nirmaleeswar.dev/docs/audio#lossless-addons',
  );
  bool get _hasInlineControls => _page >= _transferPage;

  @override
  void initState() {
    super.initState();
    _aurora = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    )..repeat();
  }

  @override
  void dispose() {
    _aurora.dispose();
    _pages.dispose();
    super.dispose();
  }

  void _next() {
    HapticFeedback.selectionClick();
    _pages.nextPage(
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;
    await OnboardingScreen.markComplete();
    if (mounted) widget.onFinished();
  }

  Future<void> _signIn() async {
    HapticFeedback.mediumImpact();
    final signedIn = await openSignIn(context);
    if (mounted && signedIn) _next();
  }

  Future<void> _openLosslessGuide() async {
    try {
      if (await launchUrl(
        _losslessGuide,
        mode: LaunchMode.externalApplication,
      )) {
        return;
      }
    } catch (_) {
      // Some platforms throw when no browser is available.
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Couldn’t open the lossless guide.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF06060A),
        body: Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(
              child: CustomPaint(painter: _AuroraPainter(_aurora)),
            ),
            // Soft vignette so text stays readable over the brightest blobs.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x00000000),
                    Color(0x33000000),
                    Color(0xCC000000),
                  ],
                  stops: [0.0, 0.55, 1.0],
                ),
              ),
            ),
            if (isDesktop) ...[
              // Centred in the whole window, with the controls laid over it,
              // rather than in the space left between them.
              Padding(
                padding: EdgeInsets.only(
                  // Sits a little above true centre, balancing the buttons.
                  bottom: _hasInlineControls
                      ? 0
                      : (MediaQuery.sizeOf(context).height < 680 ? 150 : 90),
                ),
                child: _buildPages(),
              ),
              SafeArea(
                child: Stack(
                  children: [
                    Align(alignment: Alignment.topRight, child: _buildSkip()),
                    if (!_hasInlineControls)
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: _buildBottomControls(padding),
                      ),
                  ],
                ),
              ),
            ] else
              SafeArea(
                child: Column(
                  children: [
                    Align(alignment: Alignment.topRight, child: _buildSkip()),
                    Expanded(child: _buildPages()),
                    if (!_hasInlineControls) _buildBottomControls(padding),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkip() {
    return AnimatedOpacity(
      opacity: _page < _signInPage ? 1 : 0,
      duration: const Duration(milliseconds: 250),
      child: TextButton(
        onPressed: _page < _signInPage
            ? () => _pages.animateToPage(
                _signInPage,
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOutCubic,
              )
            : null,
        child: const Text('Skip', style: TextStyle(color: Colors.white70)),
      ),
    );
  }

  Widget _buildPages() {
    final theme = Theme.of(context);
    return PageView(
      controller: _pages,
      onPageChanged: (i) => setState(() => _page = i),
      children: [
        // The mascot image has empty space above it, which makes this page
        // look low when its box is centred.
        Transform.translate(
          offset: Offset(0, isDesktop ? -13 : 0),
          child: const _WelcomePage(),
        ),
        const _FeaturesPage(),
        const _SignInPage(),
        Theme(
          data: theme.brightness == Brightness.dark
              ? theme
              : InzxTheme.darkWithAccent(theme.colorScheme.primary),
          child: PlaylistTransferPage(
            footer: _buildInlineControls(_transferPage, 'Continue', _next),
          ),
        ),
        _OnboardingInfoPage(
          icon: Iconsax.music_square,
          title: 'Lossless add-ons',
          description:
              'Add a community source to play lossless FLAC '
              'when a matching track is available.',
          instructions:
              'Open Settings → Audio, then choose Add under Lossless addon.',
          linkLabel: 'Read the lossless guide',
          onOpenLink: _openLosslessGuide,
          footer: _buildInlineControls(_losslessPage, 'Continue', _next),
        ),
        _OnboardingInfoPage(
          icon: InzxConnectScreen.icon,
          title: InzxConnectScreen.title,
          description:
              'Inzx is also available for Windows and Linux. '
              'Use Inzx Connect to pair your Android phone and computer with a QR code.',
          instructions:
              'Pair anytime from Settings → Inzx Connect, '
              'or use the devices icon in the desktop player bar.',
          footer: _buildInlineControls(_connectPage, 'Finish setup', _finish),
        ),
      ],
    );
  }

  Widget _buildInlineControls(int index, String label, VoidCallback onPressed) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PageDots(count: _pageCount, index: index),
        const SizedBox(height: 14),
        _DesktopWidth(
          child: _PrimaryButton(label: label, onPressed: onPressed),
        ),
      ],
    );
  }

  Widget _buildBottomControls(EdgeInsets padding) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PageDots(count: _pageCount, index: _page),
        const SizedBox(height: 24),
        Padding(
          padding: EdgeInsets.fromLTRB(24, 0, 24, padding.bottom > 0 ? 8 : 24),
          child: _DesktopWidth(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _page == _signInPage
                  ? Column(
                      key: const ValueKey('auth'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _PrimaryButton(
                          label: 'Continue with Google',
                          leading: const _GoogleMark(),
                          onPressed: _signIn,
                        ),
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: _next,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white70,
                            minimumSize: const Size.fromHeight(48),
                          ),
                          child: const Text(
                            'Continue without signing in',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    )
                  : _PrimaryButton(
                      key: const ValueKey('next'),
                      label: 'Continue',
                      onPressed: _next,
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class _OnboardingInfoPage extends StatelessWidget {
  const _OnboardingInfoPage({
    required this.icon,
    required this.title,
    required this.description,
    required this.instructions,
    required this.footer,
    this.linkLabel,
    this.onOpenLink,
  });

  final IconData icon;
  final String title;
  final String description;
  final String instructions;
  final Widget footer;
  final String? linkLabel;
  final VoidCallback? onOpenLink;

  @override
  Widget build(BuildContext context) {
    final red = getAccentColor(InzxAccentColor.red);
    final accent = Color.lerp(red, Colors.white, 0.4)!;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 20,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: red.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: red.withValues(alpha: 0.35)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Icon(icon, size: 48, color: accent),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: accent,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      description,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, height: 1.5),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      instructions,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        height: 1.5,
                      ),
                    ),
                    if (linkLabel case final label?)
                      TextButton.icon(
                        onPressed: onOpenLink,
                        style: TextButton.styleFrom(foregroundColor: accent),
                        icon: const Icon(Icons.open_in_new_rounded, size: 16),
                        label: Text(label),
                      ),
                    const SizedBox(height: 20),
                    footer,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WelcomePage extends StatelessWidget {
  const _WelcomePage();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 168,
            height: 168,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.12),
                  blurRadius: 70,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Image.asset(
              'assets/logo_transparent.png',
              fit: BoxFit.contain,
              cacheWidth: 480,
            ),
          ),
          const SizedBox(height: 40),
          const Text(
            'Welcome to Inzx',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Your music, beautifully unbound.\nNo ads. No limits. Open source.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 16,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeaturesPage extends StatelessWidget {
  const _FeaturesPage();

  static const _features = <(IconData, String, String)>[
    (
      Iconsax.music_square,
      'Hi-fi streaming',
      'Up to 320 kbps with smart crossfade',
    ),
    (
      Iconsax.document_text,
      'Living lyrics',
      'Word-synced, translated, beautifully animated',
    ),
    (
      Iconsax.profile_2user,
      'Jams',
      'Listen together with friends in real time',
    ),
    (
      Iconsax.document_download,
      'Offline',
      'Download anything and take it everywhere',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'Everything you love,\nnothing you don\'t.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.w800,
                height: 1.15,
                letterSpacing: -0.6,
              ),
            ),
          ),
          const SizedBox(height: 28),
          for (final (icon, title, subtitle) in _features)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.65),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SignInPage extends StatelessWidget {
  const _SignInPage();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
            ),
            child: const Icon(Iconsax.user_tick, color: Colors.white, size: 38),
          ),
          const SizedBox(height: 32),
          const Text(
            'Make it yours',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Sign in once with Google to bring your YouTube Music library, '
            'likes and listening history — and to start Jams with friends.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 15,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'You can always sign in later from Settings.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.leading,
  });

  final String label;
  final VoidCallback onPressed;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: isDesktop ? 46 : 56,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          shape: const StadiumBorder(),
          textStyle: TextStyle(
            fontFamily: desktopFontFamily,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
            Flexible(
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}

/// Keeps full-width phone buttons to a sensible size in a desktop window.
class _DesktopWidth extends StatelessWidget {
  const _DesktopWidth({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!isDesktop) return child;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: child,
      ),
    );
  }
}

/// Four-colour Google "G" drawn as arcs, so no network image is needed.
class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 20,
      height: 20,
      child: CustomPaint(painter: _GoogleMarkPainter()),
    );
  }
}

class _GoogleMarkPainter extends CustomPainter {
  const _GoogleMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.2;
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );
    Paint arc(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    const deg = math.pi / 180;
    canvas.drawArc(
      rect,
      -40 * deg,
      -95 * deg,
      false,
      arc(const Color(0xFFEA4335)),
    );
    canvas.drawArc(
      rect,
      -135 * deg,
      -90 * deg,
      false,
      arc(const Color(0xFFFBBC05)),
    );
    canvas.drawArc(
      rect,
      135 * deg,
      -95 * deg,
      false,
      arc(const Color(0xFF34A853)),
    );
    canvas.drawArc(
      rect,
      40 * deg,
      -40 * deg,
      false,
      arc(const Color(0xFF4285F4)),
    );
    canvas.drawLine(
      Offset(size.width / 2, size.height / 2),
      Offset(size.width - stroke / 2, size.height / 2),
      arc(const Color(0xFF4285F4)),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: i == index ? 26 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: i == index ? 0.95 : 0.3),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
    );
  }
}

/// Slowly drifting, hue-shifting colour blobs. Each blob is a single radial
/// gradient (soft by construction), so there is no blur pass and the whole
/// thing is a handful of draw calls per frame.
class _AuroraPainter extends CustomPainter {
  _AuroraPainter(this.animation) : super(repaint: animation);

  final Animation<double> animation;

  static const _blobs =
      <({double hue, double r, double sx, double sy, double phase})>[
        (hue: 265, r: 0.95, sx: 1, sy: 2, phase: 0.0),
        (hue: 320, r: 0.80, sx: 2, sy: 1, phase: 1.7),
        (hue: 200, r: 0.85, sx: 1, sy: 1, phase: 3.1),
        (hue: 25, r: 0.65, sx: 3, sy: 2, phase: 4.4),
      ];

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value * 2 * math.pi;
    final maxSide = math.max(size.width, size.height);

    for (final b in _blobs) {
      final cx = size.width * (0.5 + 0.38 * math.sin(t * b.sx + b.phase));
      final cy = size.height * (0.42 + 0.32 * math.cos(t * b.sy + b.phase));
      final hue = (b.hue + 40 * math.sin(t + b.phase)) % 360;
      final color = HSVColor.fromAHSV(1, hue, 0.75, 0.95).toColor();
      final radius = maxSide * b.r * (0.85 + 0.15 * math.sin(t * 2 + b.phase));
      final center = Offset(cx, cy);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: 0.42),
              color.withValues(alpha: 0.12),
              color.withValues(alpha: 0),
            ],
            stops: const [0, 0.45, 1],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AuroraPainter oldDelegate) => false;
}
