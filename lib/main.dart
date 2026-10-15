import 'dart:async';

import 'package:vibration/vibration.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PurpleTimerApp());
}

const _bg = Color(0xFF090711);
const _panel = Color(0xFF151020);
const _panel2 = Color(0xFF1D1530);
const _purple = Color(0xFF9B5CFF);
const _purpleBright = Color(0xFFBB86FC);
const _muted = Color(0xFFAAA0BC);

class TimerButtonConfig {
  const TimerButtonConfig({required this.label, required this.seconds});
  final String label;
  final int seconds;

  TimerButtonConfig copyWith({String? label, int? seconds}) =>
      TimerButtonConfig(
        label: label ?? this.label,
        seconds: seconds ?? this.seconds,
      );
}

class PurpleTimerApp extends StatelessWidget {
  const PurpleTimerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Violet Timer',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _bg,
        colorScheme: const ColorScheme.dark(
          primary: _purpleBright,
          secondary: _purple,
          surface: _panel,
        ),
        fontFamily: 'Roboto',
        useMaterial3: true,
      ),
      home: const TimerHomePage(),
    );
  }
}

class TimerHomePage extends StatefulWidget {
  const TimerHomePage({super.key});

  @override
  State<TimerHomePage> createState() => _TimerHomePageState();
}

class _TimerHomePageState extends State<TimerHomePage>
    with WidgetsBindingObserver {
  static const _defaults = <TimerButtonConfig>[
    TimerButtonConfig(label: '+1 min', seconds: 60),
    TimerButtonConfig(label: '+5 min', seconds: 300),
    TimerButtonConfig(label: '+10 min', seconds: 600),
  ];

  final AudioPlayer _alarmPlayer = AudioPlayer();
  List<TimerButtonConfig> _buttons = List.of(_defaults);
  Timer? _ticker;
  int _remainingMs = 0;
  int _totalMs = 0;
  int _endTimestampMs = 0;
  bool _running = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _alarmPlayer.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _running) {
      _syncRemaining();
    }
  }

  Future<void> _playAlarm() async {
    final canVibrate = await Vibration.hasVibrator();

    if (canVibrate) {
      Vibration.vibrate(
        pattern: [0, 1000, 250, 1000, 250, 1000, 500],
        intensities: [255, 0, 255, 0, 255, 0, 255],
        repeat: 0,
      );
    }

    await _alarmPlayer.setReleaseMode(ReleaseMode.loop);
    await _alarmPlayer.play(AssetSource('audio/alarm.mp3'));
  }

  Future<void> _stopAlarm() async {
    await Vibration.cancel();
    await _alarmPlayer.stop();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final loaded = <TimerButtonConfig>[];
    for (var i = 0; i < 3; i++) {
      final seconds =
          prefs.getInt('button_${i}_seconds') ?? _defaults[i].seconds;
      final label = prefs.getString('button_${i}_label') ?? _defaults[i].label;
      loaded.add(
        TimerButtonConfig(
          label: label,
          seconds: seconds.clamp(1, 359999).toInt(),
        ),
      );
    }
    if (!mounted) return;
    setState(() {
      _buttons = loaded;
      _loading = false;
    });
  }

  Future<void> _saveSettings(List<TimerButtonConfig> buttons) async {
    final prefs = await SharedPreferences.getInstance();
    for (var i = 0; i < buttons.length; i++) {
      await prefs.setInt('button_${i}_seconds', buttons[i].seconds);
      await prefs.setString('button_${i}_label', buttons[i].label);
    }
    if (!mounted) return;
    setState(() => _buttons = List.of(buttons));
  }

  void _addTime(TimerButtonConfig button) {
    HapticFeedback.selectionClick();
    final addMs = button.seconds * 1000;
    setState(() {
      _remainingMs += addMs;
      _totalMs += addMs;
      if (_running) _endTimestampMs += addMs;
    });
  }

  void _startPause() {
    HapticFeedback.lightImpact();
    if (_running) {
      _syncRemaining();
      _ticker?.cancel();
      setState(() => _running = false);
      return;
    }
    if (_remainingMs <= 0) return;
    setState(() {
      _running = true;
      _endTimestampMs = DateTime.now().millisecondsSinceEpoch + _remainingMs;
    });
    _ticker?.cancel();
    _ticker = Timer.periodic(
      const Duration(milliseconds: 50),
      (_) => _syncRemaining(),
    );
  }

  void _syncRemaining() {
    if (!_running) return;
    final left = _endTimestampMs - DateTime.now().millisecondsSinceEpoch;
    if (left <= 0) {
      _ticker?.cancel();

      setState(() {
        _remainingMs = 0;
        _running = false;
      });

      _playAlarm();
    } else {
      setState(() => _remainingMs = left);
    }
  }

  void _reset() {
    HapticFeedback.selectionClick();
    _ticker?.cancel();
    setState(() {
      _running = false;
      _remainingMs = 0;
      _totalMs = 0;
      _endTimestampMs = 0;
    });
  }

  String _formatTime(int ms) {
    final totalSeconds = (ms / 1000).ceil();
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _openSettings() async {
    final result = await Navigator.of(context).push<List<TimerButtonConfig>>(
      MaterialPageRoute(
        builder: (_) => TimerSettingsPage(initialButtons: List.of(_buttons)),
      ),
    );
    if (result != null) await _saveSettings(result);
  }

  @override
  Widget build(BuildContext context) {
    final progress = _totalMs == 0
        ? 0.0
        : (_remainingMs / _totalMs).clamp(0.0, 1.0);
    final hasTime = _remainingMs > 0;
    return Scaffold(
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: _purpleBright),
              )
            : Padding(
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 18),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Violet',
                          style: TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.8,
                          ),
                        ),
                        const SizedBox(width: 7),
                        const Text(
                          'TIMER',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2.5,
                            color: _muted,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Settings',
                          onPressed: _openSettings,
                          icon: const Icon(Icons.tune_rounded),
                          style: IconButton.styleFrom(
                            foregroundColor: _purpleBright,
                            backgroundColor: _panel,
                            fixedSize: const Size(46, 46),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Expanded(
                      child: Center(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final diameter =
                                (constraints.maxWidth < constraints.maxHeight
                                        ? constraints.maxWidth
                                        : constraints.maxHeight)
                                    .clamp(220.0, 340.0);
                            return SizedBox(
                              width: diameter,
                              height: diameter,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: _purple.withValues(
                                            alpha: _running ? 0.17 : 0.08,
                                          ),
                                          blurRadius: _running ? 42 : 25,
                                          spreadRadius: _running ? 5 : 0,
                                        ),
                                      ],
                                    ),
                                  ),
                                  SizedBox.expand(
                                    child: CircularProgressIndicator(
                                      value: progress,
                                      strokeWidth: 7,
                                      strokeCap: StrokeCap.round,
                                      backgroundColor: const Color(0xFF292038),
                                      valueColor:
                                          const AlwaysStoppedAnimation<Color>(
                                            _purpleBright,
                                          ),
                                    ),
                                  ),
                                  Container(
                                    margin: const EdgeInsets.all(17),
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: RadialGradient(
                                        colors: [
                                          Color(0xFF211433),
                                          Color(0xFF100C19),
                                          _bg,
                                        ],
                                        stops: [0, 0.58, 1],
                                      ),
                                    ),
                                  ),
                                  Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _formatTime(_remainingMs),
                                        style: TextStyle(
                                          fontSize: diameter * 0.17,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: -1.4,
                                          fontFeatures: const [
                                            FontFeature.tabularFigures(),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 9),
                                      Text(
                                        _running
                                            ? 'COUNTING DOWN'
                                            : (hasTime
                                                  ? 'READY WHEN YOU ARE'
                                                  : 'ADD TIME TO BEGIN'),
                                        style: const TextStyle(
                                          fontSize: 10,
                                          letterSpacing: 1.7,
                                          color: _muted,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: hasTime ? _startPause : null,
                            icon: Icon(
                              _running
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                            ),
                            label: Text(_running ? 'Pause' : 'Start'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              disabledForegroundColor: _muted.withValues(
                                alpha: 0.45,
                              ),
                              side: const BorderSide(color: Color(0xFF493365)),
                              backgroundColor: _panel,
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(17),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: hasTime || _running
                                ? () {
                                    _stopAlarm();
                                    _reset();
                                  }
                                : _stopAlarm,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Reset'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _muted,
                              disabledForegroundColor: _muted.withValues(
                                alpha: 0.35,
                              ),
                              side: const BorderSide(color: Color(0xFF30253F)),
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(17),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        const Text(
                          'QUICK ADD',
                          style: TextStyle(
                            fontSize: 10,
                            letterSpacing: 2,
                            color: _muted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        const Icon(
                          Icons.bolt_rounded,
                          size: 15,
                          color: _purpleBright,
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          'Tap to add time',
                          style: TextStyle(fontSize: 11, color: _muted),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: List.generate(3, (index) {
                        final button = _buttons[index];
                        return Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(
                              right: index == 2 ? 0 : 10,
                            ),
                            child: _QuickAddButton(
                              label: button.label,
                              onTap: () => _addTime(button),
                              emphasized: index == 1,
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 7),
                  ],
                ),
              ),
      ),
    );
  }
}

class _QuickAddButton extends StatelessWidget {
  const _QuickAddButton({
    required this.label,
    required this.onTap,
    required this.emphasized,
  });
  final String label;
  final VoidCallback onTap;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.symmetric(vertical: 19, horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: emphasized
                ? const LinearGradient(
                    colors: [Color(0xFF9B5CFF), Color(0xFF7137D8)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : const LinearGradient(
                    colors: [Color(0xFF29174A), Color(0xFF1B112C)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
            border: Border.all(
              color: emphasized
                  ? _purpleBright.withValues(alpha: 0.7)
                  : const Color(0xFF493064),
            ),
            boxShadow: emphasized
                ? [
                    BoxShadow(
                      color: _purple.withValues(alpha: 0.18),
                      blurRadius: 18,
                      offset: const Offset(0, 5),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class TimerSettingsPage extends StatefulWidget {
  const TimerSettingsPage({super.key, required this.initialButtons});
  final List<TimerButtonConfig> initialButtons;

  @override
  State<TimerSettingsPage> createState() => _TimerSettingsPageState();
}

class _TimerSettingsPageState extends State<TimerSettingsPage> {
  late List<TimerButtonConfig> _buttons;

  @override
  void initState() {
    super.initState();
    _buttons = List.of(widget.initialButtons);
  }

  String _formatDuration(int seconds) {
    if (seconds % 3600 == 0) return '${seconds ~/ 3600}h';
    if (seconds % 60 == 0) return '${seconds ~/ 60}m';
    return '${seconds}s';
  }

  Future<void> _editButton(int index) async {
    final result = await showModalBottomSheet<TimerButtonConfig>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _panel,
      showDragHandle: true,
      builder: (_) => _EditTimerButtonSheet(initial: _buttons[index]),
    );
    if (result != null && mounted) {
      setState(() => _buttons[index] = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _bg,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        children: [
          const Text(
            'QUICK ADD BUTTONS',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 1.8,
              color: _purpleBright,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 7),
          const Text(
            'Customize the three buttons on your timer screen.',
            style: TextStyle(color: _muted, height: 1.5),
          ),
          const SizedBox(height: 18),
          ...List.generate(3, (index) {
            final button = _buttons[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: _panel,
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  onTap: () => _editButton(index),
                  borderRadius: BorderRadius.circular(18),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          width: 43,
                          height: 43,
                          decoration: BoxDecoration(
                            color: _panel2,
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: Center(
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(
                                color: _purpleBright,
                                fontWeight: FontWeight.w800,
                                fontSize: 17,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                button.label,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Adds ${_formatDuration(button.seconds)}',
                                style: const TextStyle(
                                  color: _muted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded, color: _muted),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _panel,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.tips_and_updates_outlined, color: _purpleBright),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Choose a duration and an optional label for each button. Your settings are saved on this device.',
                    style: TextStyle(color: _muted, height: 1.5, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: () => Navigator.pop(context, _buttons),
            style: FilledButton.styleFrom(
              backgroundColor: _purple,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 17),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text(
              'Save settings',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditTimerButtonSheet extends StatefulWidget {
  const _EditTimerButtonSheet({required this.initial});
  final TimerButtonConfig initial;

  @override
  State<_EditTimerButtonSheet> createState() => _EditTimerButtonSheetState();
}

class _EditTimerButtonSheetState extends State<_EditTimerButtonSheet> {
  late final TextEditingController _labelController;
  late int _hours;
  late int _minutes;
  late int _seconds;
  String? _error;

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(text: widget.initial.label);
    _hours = widget.initial.seconds ~/ 3600;
    _minutes = (widget.initial.seconds % 3600) ~/ 60;
    _seconds = widget.initial.seconds % 60;
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  Widget _numberPicker(
    String label,
    int value,
    int max,
    ValueChanged<int> onChanged,
  ) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: const TextStyle(color: _muted, fontSize: 12)),
          const SizedBox(height: 7),
          Container(
            decoration: BoxDecoration(
              color: _bg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF38264D)),
            ),
            child: Column(
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => onChanged(value == max ? 0 : value + 1),
                  icon: const Icon(
                    Icons.keyboard_arrow_up_rounded,
                    color: _purpleBright,
                  ),
                ),
                Text(
                  value.toString().padLeft(2, '0'),
                  style: const TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w700,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => onChanged(value == 0 ? max : value - 1),
                  icon: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: _purpleBright,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _save() {
    final total = _hours * 3600 + _minutes * 60 + _seconds;
    if (total == 0) {
      setState(() => _error = 'Duration must be at least one second.');
      return;
    }
    final label = _labelController.text.trim();
    Navigator.pop(
      context,
      TimerButtonConfig(
        label: label.isEmpty ? '+${total}s' : label,
        seconds: total,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(22, 4, 22, bottomInset + 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Customize button',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const Text(
              'Set the amount of time this button adds.',
              style: TextStyle(color: _muted),
            ),
            const SizedBox(height: 23),
            Row(
              children: [
                _numberPicker(
                  'Hours',
                  _hours,
                  99,
                  (v) => setState(() {
                    _hours = v;
                    _error = null;
                  }),
                ),
                const SizedBox(width: 9),
                _numberPicker(
                  'Minutes',
                  _minutes,
                  59,
                  (v) => setState(() {
                    _minutes = v;
                    _error = null;
                  }),
                ),
                const SizedBox(width: 9),
                _numberPicker(
                  'Seconds',
                  _seconds,
                  59,
                  (v) => setState(() {
                    _seconds = v;
                    _error = null;
                  }),
                ),
              ],
            ),
            const SizedBox(height: 22),
            const Text(
              'BUTTON LABEL',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 1.6,
                color: _purpleBright,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _labelController,
              maxLength: 14,
              decoration: InputDecoration(
                hintText: 'e.g. +5 min',
                counterStyle: const TextStyle(color: _muted),
                filled: true,
                fillColor: _bg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFF38264D)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFF38264D)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: _purpleBright),
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Color(0xFFFF7D9D)),
                ),
              ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _save,
                style: FilledButton.styleFrom(
                  backgroundColor: _purple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                child: const Text(
                  'Save button',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
