import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/design_system/design_system.dart';
import '../providers/providers.dart';
import '../services/auto_eq_service.dart';

/// AutoEQ (ported from LastWave): pick your headphones and Inzx corrects
/// them to a target curve, using the AutoEQ database's measurements.
class AutoEqScreen extends ConsumerStatefulWidget {
  const AutoEqScreen({super.key});

  @override
  ConsumerState<AutoEqScreen> createState() => _AutoEqScreenState();
}

class _AutoEqScreenState extends ConsumerState<AutoEqScreen> {
  AutoEqState? _state;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run(AutoEqService.state);
  }

  Future<void> _run(Future<AutoEqState?> Function() action) async {
    try {
      final s = await action();
      if (mounted) {
        setState(() {
          _state = s ?? _state;
          _error = null;
        });
      }
    } on PlatformException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
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
    final primary = isDark ? Colors.white : InzxColors.textPrimary;
    final secondary = isDark ? Colors.white54 : InzxColors.textSecondary;
    final s = _state;

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        title: const Text('AutoEQ'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (s != null)
            Switch(
              value: s.enabled,
              onChanged: s.headphone == null && !s.isCustom
                  ? null
                  : (v) => _run(() => AutoEqService.setEnabled(v)),
              activeThumbColor: Colors.white,
              activeTrackColor: accent,
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: s == null
          ? Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: [
                _card(
                  isDark,
                  accent,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.headphone?.name ?? 'No headphone selected',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: primary,
                        ),
                      ),
                      if (s.headphone != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          '${s.headphone!.subtitle}${s.isCustom ? ' • Custom' : ''}',
                          style: TextStyle(fontSize: 13, color: secondary),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          FilledButton(
                            onPressed: s.busy ? null : () => _choose(isDark, accent),
                            style: FilledButton.styleFrom(
                              backgroundColor: accent,
                              foregroundColor: accent.computeLuminance() > 0.45
                                  ? Colors.black
                                  : Colors.white,
                            ),
                            child: const Text('Choose headphones'),
                          ),
                          const SizedBox(width: 10),
                          if (s.headphone != null &&
                              (s.isCustom || s.bassDb != 0 || s.tiltDb != 0 ||
                                  s.targetId != 'default'))
                            TextButton(
                              onPressed: () => _run(AutoEqService.reset),
                              child: const Text('Back to profile'),
                            ),
                        ],
                      ),
                      if (s.busy) ...[
                        const SizedBox(height: 10),
                        const LinearProgressIndicator(minHeight: 2),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        Text(_error!, style: TextStyle(color: Colors.red.shade300)),
                      ],
                    ],
                  ),
                ),
                if (s.headphone != null || s.isCustom) ...[
                  const SizedBox(height: 14),
                  _section('FREQUENCY RESPONSE', secondary),
                  _card(
                    isDark,
                    accent,
                    SizedBox(
                      height: 170,
                      child: CustomPaint(
                        painter: _CurvePainter(
                          hz: s.curveHz,
                          db: s.curveDb,
                          color: accent,
                          grid: secondary.withValues(alpha: 0.25),
                          label: secondary,
                        ),
                        size: Size.infinite,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 4),
                    child: Text(
                      '${s.filterCount} filters • Preamp ${s.preampDb.toStringAsFixed(1)} dB',
                      style: TextStyle(fontSize: 12, color: secondary),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _section('TARGET', secondary),
                  _card(
                    isDark,
                    accent,
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DropdownButton<String>(
                          isExpanded: true,
                          value: s.targets.any((t) => t.id == s.targetId)
                              ? s.targetId
                              : null,
                          hint: const Text('Lab target (AutoEQ default)'),
                          dropdownColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                          underline: const SizedBox.shrink(),
                          items: [
                            for (final t in s.targets)
                              DropdownMenuItem(
                                value: t.id,
                                child: Text(
                                  t.id == 'default' ? 'Lab target (AutoEQ default)' : t.name,
                                  style: TextStyle(color: primary),
                                ),
                              ),
                          ],
                          onChanged: s.busy
                              ? null
                              : (id) {
                                  if (id != null) _run(() => AutoEqService.setTarget(id));
                                },
                        ),
                        Text(
                          'Other targets are applied as a difference from the lab\'s '
                          'Harman-style target, then refitted.',
                          style: TextStyle(fontSize: 12, color: secondary, height: 1.35),
                        ),
                        const SizedBox(height: 12),
                        _slider('Bass', '${s.bassDb.toStringAsFixed(1)} dB', s.bassDb, -12,
                            12, 48, accent, primary, s.busy,
                            (v) => _run(() => AutoEqService.setBass(v))),
                        _slider('Tilt', '${s.tiltDb.toStringAsFixed(2)} dB/oct', s.tiltDb,
                            -1.5, 1.5, 30, accent, primary, s.busy,
                            (v) => _run(() => AutoEqService.setTilt(v))),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                _section('PER DEVICE', secondary),
                _card(
                  isDark,
                  accent,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'Load each device\'s profile when it connects',
                          style: TextStyle(color: primary, fontSize: 14),
                        ),
                        value: s.autoPerDevice,
                        activeThumbColor: Colors.white,
                        activeTrackColor: accent,
                        onChanged: (v) => _run(() => AutoEqService.setAutoPerDevice(v)),
                      ),
                      if (s.device != null && (s.headphone != null || s.isCustom))
                        OutlinedButton(
                          onPressed: () => _run(AutoEqService.saveForDevice),
                          child: Text('Use for ${s.device!.label}'),
                        ),
                      for (final d in s.savedDevices)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text(d.label, style: TextStyle(color: primary)),
                          subtitle: d.headphone == null
                              ? null
                              : Text(d.headphone!, style: TextStyle(color: secondary)),
                          trailing: TextButton(
                            onPressed: () => _run(() => AutoEqService.forgetDevice(d.key)),
                            child: const Text('Forget device'),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Profiles: AutoEQ by Jaakko Pasanen (MIT)'
                  '${s.headphone != null ? ', measurements: ${s.headphone!.subtitle}' : ''}. '
                  'Downloaded from GitHub and kept offline.',
                  style: TextStyle(fontSize: 11.5, color: secondary, height: 1.35),
                ),
              ],
            ),
    );
  }

  Widget _section(String title, Color color) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 8),
    child: Text(
      title,
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
        color: color,
      ),
    ),
  );

  Widget _card(bool isDark, Color accent, Widget child) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade100,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: isDark ? Colors.white12 : accent.withValues(alpha: 0.2)),
    ),
    child: child,
  );

  Widget _slider(
    String label,
    String valueText,
    double value,
    double min,
    double max,
    int divisions,
    Color accent,
    Color primary,
    bool busy,
    ValueChanged<double> onEnd,
  ) {
    return _DeferredSlider(
      label: label,
      valueText: valueText,
      value: value.clamp(min, max),
      min: min,
      max: max,
      divisions: divisions,
      accent: accent,
      primary: primary,
      enabled: !busy,
      onChangeEnd: onEnd,
    );
  }

  Future<void> _choose(bool isDark, Color accent) async {
    final picked = await showModalBottomSheet<AutoEqHeadphone>(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF161616) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _SearchSheet(isDark: isDark),
    );
    if (picked != null) await _run(() => AutoEqService.select(picked));
  }
}

/// A slider that refits once, when the drag ends (refitting is a fit, not a
/// knob), showing the value live while dragging.
class _DeferredSlider extends StatefulWidget {
  const _DeferredSlider({
    required this.label,
    required this.valueText,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.accent,
    required this.primary,
    required this.enabled,
    required this.onChangeEnd,
  });

  final String label;
  final String valueText;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final Color accent;
  final Color primary;
  final bool enabled;
  final ValueChanged<double> onChangeEnd;

  @override
  State<_DeferredSlider> createState() => _DeferredSliderState();
}

class _DeferredSliderState extends State<_DeferredSlider> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final v = _dragging ?? widget.value;
    return Row(
      children: [
        SizedBox(
          width: 44,
          child: Text(widget.label, style: TextStyle(color: widget.primary)),
        ),
        Expanded(
          child: Slider(
            value: v,
            min: widget.min,
            max: widget.max,
            divisions: widget.divisions,
            activeColor: widget.accent,
            onChanged: widget.enabled ? (x) => setState(() => _dragging = x) : null,
            onChangeEnd: (x) {
              setState(() => _dragging = null);
              widget.onChangeEnd(x);
            },
          ),
        ),
        SizedBox(
          width: 78,
          child: Text(
            _dragging == null
                ? widget.valueText
                : (widget.label == 'Tilt'
                      ? '${v.toStringAsFixed(2)} dB/oct'
                      : '${v.toStringAsFixed(1)} dB'),
            textAlign: TextAlign.end,
            style: TextStyle(fontSize: 12, color: widget.primary),
          ),
        ),
      ],
    );
  }
}

class _SearchSheet extends StatefulWidget {
  const _SearchSheet({required this.isDark});
  final bool isDark;

  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<AutoEqHeadphone> _results = const [];
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(q));
  }

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) {
      setState(() => _results = const []);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await AutoEqService.search(q);
      if (mounted) setState(() => _results = rows);
    } on PlatformException {
      if (mounted) setState(() => _error = 'Couldn\'t download the AutoEQ list.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = widget.isDark ? Colors.white : InzxColors.textPrimary;
    final secondary = widget.isDark ? Colors.white54 : InzxColors.textSecondary;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Choose your headphones',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: primary),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _controller,
                    autofocus: true,
                    onChanged: _onChanged,
                    style: TextStyle(color: primary),
                    decoration: InputDecoration(
                      hintText: 'Model, brand or reviewer',
                      hintStyle: TextStyle(color: secondary),
                      filled: true,
                      fillColor: widget.isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : Colors.grey.shade100,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      prefixIcon: Icon(Icons.search, color: secondary),
                    ),
                  ),
                  if (_loading)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text('Downloading the AutoEQ list…',
                          style: TextStyle(color: secondary, fontSize: 12.5)),
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(_error!, style: TextStyle(color: Colors.red.shade300)),
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _results.length,
                itemBuilder: (context, i) {
                  final h = _results[i];
                  return ListTile(
                    title: Text(h.name, style: TextStyle(color: primary)),
                    subtitle: Text(
                      '${h.subtitle}${h.inEar ? ' • IEM' : ''}',
                      style: TextStyle(color: secondary, fontSize: 12.5),
                    ),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      Navigator.pop(context, h);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The correction's response, 20 Hz–20 kHz on a log axis, ±15 dB.
class _CurvePainter extends CustomPainter {
  _CurvePainter({
    required this.hz,
    required this.db,
    required this.color,
    required this.grid,
    required this.label,
  });

  final List<double> hz;
  final List<double> db;
  final Color color;
  final Color grid;
  final Color label;

  static const double _range = 15;

  double _x(double f, double w) =>
      w * (math.log(f / 20) / math.log(20000 / 20)).clamp(0.0, 1.0);
  double _y(double d, double h) => h / 2 - (d / _range).clamp(-1.0, 1.0) * h / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final d in [-10.0, 0.0, 10.0]) {
      final y = _y(d, size.height);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint..strokeWidth = d == 0 ? 1.4 : 1);
    }
    for (final f in [100.0, 1000.0, 10000.0]) {
      final x = _x(f, size.width);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint..strokeWidth = 1);
      final tp = TextPainter(
        text: TextSpan(
          text: f >= 1000 ? '${(f / 1000).round()}k' : '${f.round()}',
          style: TextStyle(color: label, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x + 3, size.height - tp.height));
    }
    if (hz.length < 2 || hz.length != db.length) return;
    final path = Path();
    for (var i = 0; i < hz.length; i++) {
      final p = Offset(_x(hz[i], size.width), _y(db[i], size.height));
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _CurvePainter old) =>
      old.db != db || old.color != color;
}
