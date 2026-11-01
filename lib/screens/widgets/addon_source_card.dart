import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax/iconsax.dart';

import '../../core/design_system/design_system.dart';
import '../../services/addons/addon_client.dart';
import '../../services/addons/addon_models.dart';
import '../../services/addons/addon_service.dart';

/// Audio settings card for the lossless addon: install one by pasting its
/// URL, then turn it on/off, pick the tier, or remove it. Styled like the
/// JioSaavn card above it.
class AddonSourceCard extends StatelessWidget {
  const AddonSourceCard({
    super.key,
    required this.isDark,
    required this.accentColor,
    required this.switchBuilder,
  });

  final bool isDark;
  final Color accentColor;

  /// The settings screen's own switch, so both cards match.
  final Widget Function(bool value, ValueChanged<bool> onChanged)
  switchBuilder;

  @override
  Widget build(BuildContext context) {
    final service = AddonService.instance;
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark
                  ? Colors.white12
                  : accentColor.withValues(alpha: 0.2),
            ),
          ),
          child: service.isInstalled
              ? _installed(context, service)
              : _empty(context),
        );
      },
    );
  }

  Color get _primary => isDark ? Colors.white : InzxColors.textPrimary;
  Color get _secondary => isDark ? Colors.white54 : InzxColors.textSecondary;

  Widget _icon(bool active) => Container(
    width: 40,
    height: 40,
    decoration: BoxDecoration(
      color: active
          ? accentColor.withValues(alpha: 0.2)
          : (isDark ? Colors.white.withValues(alpha: 0.1) : Colors.grey.shade200),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Icon(
      Iconsax.music_square,
      color: active ? accentColor : _secondary,
      size: 22,
    ),
  );

  Widget _empty(BuildContext context) {
    return Row(
      children: [
        _icon(false),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Lossless addon',
                style: TextStyle(fontWeight: FontWeight.w600, color: _primary),
              ),
              const SizedBox(height: 2),
              Text(
                'Add your addon URL to stream FLAC',
                style: TextStyle(fontSize: 13, color: _secondary),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: () => _showInstallSheet(context),
          style: TextButton.styleFrom(foregroundColor: accentColor),
          child: const Text(
            'Add',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _installed(BuildContext context, AddonService service) {
    final addons = service.addons;
    final anyEnabled = service.isEnabled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            _icon(anyEnabled),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Lossless sources',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: _primary,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    addons.length == 1
                        ? '1 source installed'
                        : '${addons.length} sources · Priority fallback',
                    style: TextStyle(fontSize: 12.5, color: _secondary),
                  ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: () => _showInstallSheet(context),
              icon: const Icon(Iconsax.add, size: 16),
              label: const Text(
                'Add',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              style: TextButton.styleFrom(
                foregroundColor: accentColor,
                visualDensity: VisualDensity.compact,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // List of Addon items
        for (var i = 0; i < addons.length; i++) ...[
          _addonCard(context, service, i, addons[i], addons.length),
          if (i != addons.length - 1) const SizedBox(height: 10),
        ],

        const SizedBox(height: 12),
        Text(
          'Songs start in normal quality and switch to lossless mid-song, '
          'without a gap, as soon as a matching copy is found. If a source doesn\'t have the song, Inzx queries the next source in priority order.',
          style: TextStyle(fontSize: 12, color: _secondary, height: 1.35),
        ),
      ],
    );
  }

  Widget _addonCard(
    BuildContext context,
    AddonService service,
    int index,
    AddonEntry entry,
    int totalCount,
  ) {
    final enabled = entry.enabled;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.grey.shade300,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: enabled
                      ? accentColor.withValues(alpha: 0.2)
                      : (isDark ? Colors.white10 : Colors.grey.shade200),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '#${index + 1}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: enabled ? accentColor : _secondary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: enabled ? _primary : _secondary,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      entry.host,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: _secondary),
                    ),
                  ],
                ),
              ),
              switchBuilder(
                enabled,
                (val) => service.setAddonEnabled(index, val),
              ),
            ],
          ),
          if (entry.client.isLastWave && !addonSigningConfigured) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Iconsax.warning_2,
                  size: 15,
                  color: Colors.orange.shade400,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'This build has no addon signing key, so this addon can search but won\'t give real streams.',
                    style: TextStyle(fontSize: 11.5, color: _secondary),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final q in AddonQuality.values) ...[
                  Expanded(
                    child: _qualityChip(service, index, entry, q, enabled),
                  ),
                  if (q != AddonQuality.values.last) const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              if (totalCount > 1) ...[
                Text(
                  'Priority',
                  style: TextStyle(fontSize: 11.5, color: _secondary),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Iconsax.arrow_up_2, size: 16),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                  color: _secondary,
                  disabledColor: isDark ? Colors.white24 : Colors.black12,
                  tooltip: 'Move up in priority',
                  onPressed: index > 0
                      ? () {
                          HapticFeedback.selectionClick();
                          service.reorder(index, index - 1);
                        }
                      : null,
                ),
                IconButton(
                  icon: const Icon(Iconsax.arrow_down_1, size: 16),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                  color: _secondary,
                  disabledColor: isDark ? Colors.white24 : Colors.black12,
                  tooltip: 'Move down in priority',
                  onPressed: index < totalCount - 1
                      ? () {
                          HapticFeedback.selectionClick();
                          service.reorder(index, index + 1);
                        }
                      : null,
                ),
              ],
              const Spacer(),
              TextButton.icon(
                onPressed: () => _confirmRemove(context, service, index, entry),
                icon: Icon(
                  Iconsax.trash,
                  size: 14,
                  color: isDark ? Colors.white54 : InzxColors.textSecondary,
                ),
                label: Text(
                  'Remove',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white54 : InzxColors.textSecondary,
                  ),
                ),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _qualityChip(
    AddonService service,
    int index,
    AddonEntry entry,
    AddonQuality q,
    bool enabled,
  ) {
    final selected = entry.quality == q;
    return GestureDetector(
      onTap: enabled
          ? () {
              HapticFeedback.selectionClick();
              service.setAddonQuality(index, q);
            }
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? accentColor.withValues(alpha: enabled ? 0.18 : 0.08)
              : (isDark
                    ? Colors.white.withValues(alpha: 0.04)
                    : Colors.grey.shade50),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? accentColor.withValues(alpha: enabled ? 0.6 : 0.25)
                : (isDark ? Colors.white12 : Colors.grey.shade300),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              q.label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: selected && enabled ? accentColor : _primary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              q.description,
              style: TextStyle(fontSize: 10.5, color: _secondary),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmRemove(
    BuildContext context,
    AddonService service,
    int index,
    AddonEntry entry,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove addon?'),
        content: Text(
          'Inzx will forget "${entry.name}" (${entry.host}). '
          'You can add it again any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true) await service.removeAt(index);
  }

  void _showInstallSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF161616) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) =>
          _InstallSheet(isDark: isDark, accentColor: accentColor),
    );
  }
}

class _InstallSheet extends StatefulWidget {
  const _InstallSheet({required this.isDark, required this.accentColor});
  final bool isDark;
  final Color accentColor;

  @override
  State<_InstallSheet> createState() => _InstallSheetState();
}

class _InstallSheetState extends State<_InstallSheet> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text != null && text.isNotEmpty) {
      _controller.text = text;
      setState(() => _error = null);
    }
  }

  Future<void> _install() async {
    final url = _controller.text.trim();
    if (url.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final manifest = await AddonService.instance.install(url);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(content: Text('${manifest.displayName} added')),
      );
    } on AddonException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Couldn\'t add the addon: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final primary = isDark ? Colors.white : InzxColors.textPrimary;
    final secondary = isDark ? Colors.white54 : InzxColors.textSecondary;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: secondary.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Add a lossless addon',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
                color: primary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Paste the addon endpoint or manifest URL you got when you '
              'registered with the addon provider. It holds your personal '
              'token, so keep it private.',
              style: TextStyle(fontSize: 13.5, color: secondary, height: 1.35),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              enabled: !_busy,
              autofocus: true,
              keyboardType: TextInputType.url,
              autocorrect: false,
              style: TextStyle(color: primary, fontSize: 14),
              onSubmitted: (_) => _install(),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              decoration: InputDecoration(
                hintText: 'https://…/manifest.json',
                hintStyle: TextStyle(color: secondary),
                errorText: _error,
                errorMaxLines: 3,
                filled: true,
                fillColor: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                suffixIcon: IconButton(
                  tooltip: 'Paste',
                  icon: Icon(Iconsax.clipboard_text, color: secondary),
                  onPressed: _busy ? null : _paste,
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: _busy ? null : _install,
                style: FilledButton.styleFrom(
                  backgroundColor: widget.accentColor,
                  foregroundColor: readableOn(widget.accentColor),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(
                        'Add addon',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Black or white, whichever reads on [color] (the accent can be black).
Color readableOn(Color color) =>
    color.computeLuminance() > 0.45 ? Colors.black : Colors.white;
