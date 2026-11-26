import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/l10n/app_localizations_x.dart';
import '../../core/utils/platform_utils.dart';
import '../../services/addons/addon_service.dart';
import '../../services/audio_output_service.dart';
import '../../services/desktop/desktop_audio_dsp.dart';

class AtmosSettingsCard extends StatefulWidget {
  const AtmosSettingsCard({super.key});

  @override
  State<AtmosSettingsCard> createState() => _AtmosSettingsCardState();
}

class _AtmosSettingsCardState extends State<AtmosSettingsCard> {
  bool _prefer = AudioOutputService.preferAtmosDefault;
  bool _passthrough = false;
  bool? _atmosSupported;
  bool _checkingSupport = false;
  Timer? _outputPoll;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _outputPoll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _prefer =
          prefs.getBool(AudioOutputService.preferAtmosKey) ??
          AudioOutputService.preferAtmosDefault;
      _passthrough =
          prefs.getBool(AudioOutputService.atmosPassthroughKey) ?? false;
    });
    await _refreshSupport();
    if (!mounted) return;
    // Some platforms expose no route event, and system spatial settings can
    // change without a device disconnecting.
    _outputPoll = Timer.periodic(const Duration(seconds: 3), (_) {
      if (ModalRoute.isCurrentOf(context) != false) {
        unawaited(_refreshSupport());
      }
    });
  }

  Future<void> _refreshSupport() async {
    if (_checkingSupport) return;
    _checkingSupport = true;
    final supported =
        (await AudioOutputService.describe())?.atmosSupported == true;
    _checkingSupport = false;
    if (mounted && _atmosSupported != supported) {
      setState(() => _atmosSupported = supported);
    }
  }

  String get _atmosSubtitle => switch (_atmosSupported) {
    null => context.l10n.checkingAudioOutput,
    false => context.l10n.dolbyAtmosOutputUnavailable,
    true => context.l10n.preferDolbyAtmosMixesDescription,
  };

  @override
  Widget build(BuildContext context) => Column(
    children: [
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: Text(context.l10n.preferDolbyAtmosMixes),
        subtitle: Text(_atmosSubtitle),
        value: _atmosSupported == true && _prefer,
        onChanged: _atmosSupported == true
            ? (value) async {
                setState(() => _prefer = value);
                await AddonService.instance.setPreferAtmos(value);
              }
            : null,
      ),
      if (isDesktop) ...[
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: Text(context.l10n.hdmiAtmosPassthrough),
          subtitle: Text(context.l10n.hdmiAtmosPassthroughDescription),
          value: _passthrough,
          onChanged: (value) async {
            setState(() => _passthrough = value);
            await DesktopAudioDsp.instance.setAtmosPassthrough(value);
          },
        ),
        Text(context.l10n.desktopAtmosHeadphoneDescription),
      ],
    ],
  );
}
