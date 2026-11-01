import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/design_system/design_system.dart';
import '../providers/providers.dart';
import '../services/scrobbling/lastfm_client.dart';
import '../services/scrobbling/scrobble_service.dart';

/// Last.fm and ListenBrainz: connect accounts and choose what's sent.
class ScrobblingScreen extends ConsumerStatefulWidget {
  const ScrobblingScreen({super.key});

  @override
  ConsumerState<ScrobblingScreen> createState() => _ScrobblingScreenState();
}

class _ScrobblingScreenState extends ConsumerState<ScrobblingScreen> {
  final _svc = ScrobbleService.instance;
  String? _pendingToken; // browser sign-in waiting for approval
  bool _busy = false;
  String? _lastFmError;
  final _lbController = TextEditingController();
  String? _lbError;

  @override
  void initState() {
    super.initState();
    _svc.start();
  }

  @override
  void dispose() {
    _lbController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final albumColors = ref.watch(albumColorsProvider);
    final accent = albumColors.isDefault
        ? Theme.of(context).colorScheme.primary
        : albumColors.accent;
    final background = (!albumColors.isDefault && isDark)
        ? albumColors.backgroundSecondary
        : (isDark ? InzxColors.darkBackground : InzxColors.background);

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        title: const Text('Scrobbling'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListenableBuilder(
        listenable: _svc,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Text(
              'A song counts once you\'ve listened to half of it or 3 minutes, '
              'whichever comes first. Songs of 30 seconds or less aren\'t sent.',
              style: TextStyle(color: _secondary(isDark), fontSize: 13.5, height: 1.35),
            ),
            const SizedBox(height: 18),
            _lastFmCard(isDark, accent),
            const SizedBox(height: 14),
            _listenBrainzCard(isDark, accent),
            const SizedBox(height: 14),
            _card(
              isDark,
              accent,
              child: _toggle(
                isDark,
                accent,
                'Primary artist only',
                'Send "Artist" instead of "Artist, Feature & Other"',
                _svc.primaryArtistOnly,
                (v) => _svc.setOption(ScrobbleService.optPrimaryArtist, v),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- Last.fm --------------------------------------------------------

  Widget _lastFmCard(bool isDark, Color accent) {
    final client = _svc.lastFm;
    final service = _svc.useLibreFm ? 'Libre.fm' : 'Last.fm';
    return _card(
      isDark,
      accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(isDark, accent, Iconsax.music_circle, service,
              _svc.lastFmSignedIn ? 'Signed in as ${_svc.lastFmUser}' : 'Not connected'),
          const SizedBox(height: 12),
          if (!client.isConfigured)
            _note(
              isDark,
              'This build has no $service API key. Add Inzx\'s key at build '
              'time, or enter your own under "API key" below.',
            ),
          if (_svc.lastFmSignedIn) ...[
            _toggle(isDark, accent, 'Scrobble', 'Send finished plays',
                _svc.lastFmEnabled, (v) => _svc.setOption(ScrobbleService.optLastFm, v)),
            _toggle(isDark, accent, 'Now playing', 'Show the current song on your profile',
                _svc.lastFmNowPlaying, (v) => _svc.setOption(ScrobbleService.optNowPlaying, v)),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _svc.signOutLastFm,
                child: const Text('Sign out'),
              ),
            ),
          ] else if (client.isConfigured) ...[
            if (_pendingToken == null)
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: _busy ? null : _startBrowserSignIn,
                      style: _filled(accent),
                      child: const Text('Sign in with browser'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    onPressed: _busy ? null : () => _passwordSignIn(isDark, accent),
                    child: const Text('Username'),
                  ),
                ],
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _note(isDark, 'Approve Inzx in the page that opened, then come back.'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: _busy ? null : _finishBrowserSignIn,
                          style: _filled(accent),
                          child: const Text('I\'ve approved it'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      TextButton(
                        onPressed: () => setState(() => _pendingToken = null),
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                ],
              ),
          ],
          if (_lastFmError != null) ...[
            const SizedBox(height: 8),
            Text(_lastFmError!, style: TextStyle(color: Colors.red.shade300, fontSize: 13)),
          ],
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('API key', style: TextStyle(fontSize: 13.5, color: _secondary(isDark))),
              children: [
                _toggle(isDark, accent, 'Use Libre.fm', 'Scrobble to libre.fm instead',
                    _svc.useLibreFm, (v) => _svc.setOption(ScrobbleService.optLibreFm, v)),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Iconsax.key, size: 18),
                    label: Text(
                      _svc.customApiKey.isEmpty ? 'Use my own API key' : 'Change my API key',
                    ),
                    onPressed: () => _editApiKey(isDark, accent),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startBrowserSignIn() async {
    setState(() {
      _busy = true;
      _lastFmError = null;
    });
    try {
      final client = _svc.lastFm;
      final token = await client.getToken();
      await launchUrl(client.authUrl(token), mode: LaunchMode.externalApplication);
      if (mounted) setState(() => _pendingToken = token);
    } catch (e) {
      if (mounted) setState(() => _lastFmError = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finishBrowserSignIn() async {
    final token = _pendingToken;
    if (token == null) return;
    setState(() {
      _busy = true;
      _lastFmError = null;
    });
    try {
      final session = await _svc.lastFm.getSession(token);
      await _svc.saveLastFmSession(session);
      if (mounted) setState(() => _pendingToken = null);
    } on LastFmException catch (e) {
      if (mounted) {
        setState(() => _lastFmError = e.code == 14
            ? 'Not approved yet — approve Inzx in the browser first.'
            : e.message);
      }
    } catch (e) {
      if (mounted) setState(() => _lastFmError = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _passwordSignIn(bool isDark, Color accent) async {
    final user = TextEditingController();
    final pass = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign in to Last.fm'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: user,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Username'),
            ),
            TextField(
              controller: pass,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
            const SizedBox(height: 8),
            const Text(
              'Your password goes straight to Last.fm and isn\'t stored; only '
              'the session it returns is kept.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sign in')),
        ],
      ),
    );
    final username = user.text.trim();
    final password = pass.text;
    user.dispose();
    pass.dispose();
    if (ok != true || username.isEmpty || password.isEmpty) return;
    setState(() {
      _busy = true;
      _lastFmError = null;
    });
    try {
      final session = await _svc.lastFm.getMobileSession(username, password);
      await _svc.saveLastFmSession(session);
    } catch (e) {
      if (mounted) setState(() => _lastFmError = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editApiKey(bool isDark, Color accent) async {
    final key = TextEditingController(text: _svc.customApiKey);
    final secret = TextEditingController(text: _svc.customApiSecret);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Your Last.fm API key'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Create one at last.fm/api/account/create. Leave empty to use '
              'Inzx\'s own.',
              style: TextStyle(fontSize: 12.5),
            ),
            TextField(controller: key, decoration: const InputDecoration(labelText: 'API key')),
            TextField(
              controller: secret,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Shared secret'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok == true) await _svc.setCustomApi(key.text, secret.text);
    key.dispose();
    secret.dispose();
  }

  // ---- ListenBrainz ---------------------------------------------------

  Widget _listenBrainzCard(bool isDark, Color accent) {
    return _card(
      isDark,
      accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(isDark, accent, Iconsax.radar, 'ListenBrainz',
              _svc.listenBrainzSignedIn ? 'Connected as ${_svc.listenBrainzUser}' : 'Not connected'),
          const SizedBox(height: 12),
          if (_svc.listenBrainzSignedIn) ...[
            _toggle(isDark, accent, 'Submit listens', 'Send plays and now playing',
                _svc.listenBrainzEnabled, (v) => _svc.setOption(ScrobbleService.optListenBrainz, v)),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _svc.disconnectListenBrainz,
                child: const Text('Disconnect'),
              ),
            ),
          ] else ...[
            TextField(
              controller: _lbController,
              autocorrect: false,
              obscureText: true,
              decoration: InputDecoration(
                hintText: 'User token from listenbrainz.org/settings',
                errorText: _lbError,
                isDense: true,
                filled: true,
                fillColor: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _busy ? null : _connectListenBrainz,
                    style: _filled(accent),
                    child: const Text('Connect'),
                  ),
                ),
                const SizedBox(width: 10),
                TextButton(
                  onPressed: () => launchUrl(
                    Uri.parse('https://listenbrainz.org/settings/'),
                    mode: LaunchMode.externalApplication,
                  ),
                  child: const Text('Get token'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _connectListenBrainz() async {
    final token = _lbController.text.trim();
    if (token.isEmpty) return;
    setState(() {
      _busy = true;
      _lbError = null;
    });
    try {
      final ok = await _svc.connectListenBrainz(token);
      if (!ok && mounted) setState(() => _lbError = 'That token isn\'t valid');
      if (ok) _lbController.clear();
    } catch (e) {
      if (mounted) setState(() => _lbError = 'Couldn\'t reach ListenBrainz');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---- Bits -----------------------------------------------------------

  Color _secondary(bool isDark) => isDark ? Colors.white54 : InzxColors.textSecondary;

  ButtonStyle _filled(Color accent) => FilledButton.styleFrom(
    backgroundColor: accent,
    foregroundColor: accent.computeLuminance() > 0.45 ? Colors.black : Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  );

  Widget _card(bool isDark, Color accent, {required Widget child}) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade100,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: isDark ? Colors.white12 : accent.withValues(alpha: 0.2)),
    ),
    child: child,
  );

  Widget _header(bool isDark, Color accent, IconData icon, String title, String subtitle) =>
      Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: accent, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : InzxColors.textPrimary,
                )),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(fontSize: 13, color: _secondary(isDark))),
              ],
            ),
          ),
        ],
      );

  Widget _note(bool isDark, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: TextStyle(fontSize: 12.5, color: _secondary(isDark), height: 1.35)),
  );

  Widget _toggle(
    bool isDark,
    Color accent,
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    dense: true,
    title: Text(title, style: TextStyle(
      fontWeight: FontWeight.w500,
      color: isDark ? Colors.white : InzxColors.textPrimary,
    )),
    subtitle: Text(subtitle, style: TextStyle(fontSize: 12.5, color: _secondary(isDark))),
    value: value,
    onChanged: onChanged,
    activeThumbColor: Colors.white,
    activeTrackColor: accent,
  );
}
