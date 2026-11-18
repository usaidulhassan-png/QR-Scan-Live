import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const UHApp());

class UHApp extends StatelessWidget {
  const UHApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UH Wireless QR Scanner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const ScannerPage(),
    );
  }
}

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );

  String _ip = '';
  String _port = '8765';
  String _pin = '1234';
  int _cooldown = 3;

  String _lastValue = '';
  DateTime _lastTime = DateTime.fromMillisecondsSinceEpoch(0);
  String _status = 'QR scan karne ke liye tayyar';
  bool? _statusOk;
  int _sent = 0;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _ip = p.getString('ip') ?? '';
      _port = p.getString('port') ?? '8765';
      _pin = p.getString('pin') ?? '1234';
      _cooldown = p.getInt('cooldown') ?? 3;
    });
    if (_ip.isEmpty) {
      _setStatus('Pehle Settings mein PC ka IP daalen', false);
    }
  }

  void _setStatus(String text, bool? ok) {
    if (!mounted) return;
    setState(() {
      _status = text;
      _statusOk = ok;
    });
  }

  void _onDetect(BarcodeCapture capture) {
    for (final b in capture.barcodes) {
      final raw = b.rawValue;
      if (raw == null || raw.isEmpty) continue;
      final now = DateTime.now();
      if (raw == _lastValue &&
          now.difference(_lastTime).inSeconds < _cooldown) {
        return; // same QR dobara, cooldown ke andar - ignore
      }
      _lastValue = raw;
      _lastTime = now;
      _send(raw);
      return;
    }
  }

  Future<void> _send(String value) async {
    if (_ip.isEmpty) {
      _setStatus('Pehle Settings mein PC ka IP daalen', false);
      return;
    }
    _setStatus('Bhej raha hoon: $value', null);
    final id =
        '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 31)}';
    try {
      final res = await http
          .post(
            Uri.parse('http://$_ip:$_port/scan'),
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode({'pin': _pin, 'id': id, 'value': value}),
          )
          .timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        _sent++;
        HapticFeedback.mediumImpact();
        SystemSound.play(SystemSoundType.click);
        _setStatus('Bhej diya  \u2713  $value', true);
      } else if (res.statusCode == 403) {
        HapticFeedback.heavyImpact();
        _setStatus('PIN ghalat hai (phone aur PC ka PIN same hona chahiye)', false);
      } else {
        HapticFeedback.heavyImpact();
        _setStatus('PC ne error diya (${res.statusCode})', false);
      }
    } catch (e) {
      HapticFeedback.heavyImpact();
      _setStatus(
          'PC tak nahin pahunch saka. Wi-Fi, IP aur Receiver check karein.',
          false);
    }
  }

  Future<void> _openSettings() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const SettingsPage()),
    );
    if (saved == true) {
      await _loadSettings();
      _setStatus('Settings save ho gayin', true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color statusColor = _statusOk == null
        ? Colors.blueGrey
        : (_statusOk! ? Colors.green.shade700 : Colors.red.shade700);

    return Scaffold(
      appBar: AppBar(
        title: const Text('UH Wireless QR Scanner'),
        actions: [
          IconButton(
            icon: const Icon(Icons.flashlight_on),
            tooltip: 'Torch',
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: _openSettings,
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Positioned(
            left: 12,
            right: 12,
            bottom: 16,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _status,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Bheje gaye: $_sent   |   PC: ${_ip.isEmpty ? "-" : "$_ip:$_port"}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _ip = TextEditingController();
  final _port = TextEditingController(text: '8765');
  final _pin = TextEditingController(text: '1234');
  final _cool = TextEditingController(text: '3');
  String _testMsg = '';
  bool? _testOk;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ip.dispose();
    _port.dispose();
    _pin.dispose();
    _cool.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _ip.text = p.getString('ip') ?? '';
      _port.text = p.getString('port') ?? '8765';
      _pin.text = p.getString('pin') ?? '1234';
      _cool.text = (p.getInt('cooldown') ?? 3).toString();
    });
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('ip', _ip.text.trim());
    await p.setString('port', _port.text.trim().isEmpty ? '8765' : _port.text.trim());
    await p.setString('pin', _pin.text.trim());
    await p.setInt('cooldown', int.tryParse(_cool.text.trim()) ?? 3);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _test() async {
    setState(() {
      _testMsg = 'Test ho raha hai...';
      _testOk = null;
    });
    try {
      final res = await http
          .post(
            Uri.parse('http://${_ip.text.trim()}:${_port.text.trim()}/ping'),
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode({'pin': _pin.text.trim()}),
          )
          .timeout(const Duration(seconds: 4));
      if (!mounted) return;
      if (res.statusCode == 200) {
        setState(() {
          _testMsg = 'Connection theek hai \u2713';
          _testOk = true;
        });
      } else if (res.statusCode == 403) {
        setState(() {
          _testMsg = 'PC mil gaya lekin PIN ghalat hai';
          _testOk = false;
        });
      } else {
        setState(() {
          _testMsg = 'PC ne error diya (${res.statusCode})';
          _testOk = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testMsg = 'PC tak nahin pahunch saka. IP / Wi-Fi / Receiver check karein.';
        _testOk = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _ip,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'PC ka IP (Receiver window mein likha hota hai)',
              hintText: '192.168.1.10',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _port,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Port',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pin,
            decoration: const InputDecoration(
              labelText: 'PIN',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _cool,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Same QR dobara ignore karne ka waqt (seconds)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _test,
                  child: const Text('Test Connection'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _save,
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_testMsg.isNotEmpty)
            Text(
              _testMsg,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: _testOk == null
                    ? Colors.blueGrey
                    : (_testOk! ? Colors.green.shade700 : Colors.red.shade700),
              ),
            ),
        ],
      ),
    );
  }
}
