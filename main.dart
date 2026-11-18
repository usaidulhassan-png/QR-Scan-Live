import 'dart:convert';
import 'dart:io' show InternetAddressType, NetworkInterface, Socket;
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String kAppName = 'UH Wireless QR Scanner';
const String kVersion = '1.1.0';
const String kCompany = 'UH DATA TECH SOLUTION';
const String kDeveloper = 'Usaid ul Hassan';
const String kPhone = '0304-0307828';
const String kEmail = 'usaidulhassan@gmail.com';
const String kAddress = 'Hyderabad, Sindh, Pakistan';
const String kIntro =
    'UH DATA TECH SOLUTION designs and builds custom software solutions '
    '(desktop, mobile and database applications) tailored to the needs of '
    'each client.';

void main() => runApp(const UHApp());

class UHApp extends StatelessWidget {
  const UHApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const ScannerPage(),
    );
  }
}

// ---------------------------------------------------------------------------
// Main scanner screen
// ---------------------------------------------------------------------------

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage>
    with WidgetsBindingObserver {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );

  String _ip = '';
  String _port = '8765';
  String _pin = '1234';
  int _cooldown = 3;

  String _lastValue = '';
  DateTime _lastTime = DateTime.fromMillisecondsSinceEpoch(0);
  String _status = 'Ready to scan';
  bool? _statusOk;
  int _sent = 0;
  bool _autoOpened = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_controller.value.hasCameraPermission) return;
    if (state == AppLifecycleState.resumed) {
      if (!_controller.value.isRunning) _safeStart();
    } else if (state == AppLifecycleState.paused) {
      if (_controller.value.isRunning) _safeStop();
    }
  }

  Future<void> _safeStop() async {
    try {
      await _controller.stop();
    } catch (_) {}
  }

  Future<void> _safeStart() async {
    try {
      await _controller.start();
    } catch (_) {}
  }

  Future<void> _restartCamera() async {
    await _safeStop();
    await _safeStart();
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
      _setStatus('Not connected to a PC. Open Settings to connect.', false);
      if (!_autoOpened) {
        _autoOpened = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _openSettings();
        });
      }
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
        return; // same QR again within the cooldown time - ignore
      }
      _lastValue = raw;
      _lastTime = now;
      _send(raw);
      return;
    }
  }

  Future<void> _send(String value) async {
    if (_ip.isEmpty) {
      _setStatus('Not connected to a PC. Open Settings to connect.', false);
      return;
    }
    _setStatus('Sending: $value', null);
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
        _setStatus('Sent  \u2713  $value', true);
      } else if (res.statusCode == 403) {
        HapticFeedback.heavyImpact();
        _setStatus('Wrong PIN. It must match the PIN of the PC receiver.', false);
      } else {
        HapticFeedback.heavyImpact();
        _setStatus('The PC returned an error (${res.statusCode}).', false);
      }
    } catch (e) {
      HapticFeedback.heavyImpact();
      _setStatus(
          'Cannot reach the PC. Check the network, the IP address and that the receiver is running.',
          false);
    }
  }

  Future<void> _openSettings() async {
    await _safeStop();
    if (!mounted) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const SettingsPage()),
    );
    await _safeStart();
    if (!mounted) return;
    if (saved == true) {
      await _loadSettings();
      _setStatus('Settings saved', true);
    }
  }

  Future<void> _openAbout() async {
    await _safeStop();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AboutPage()),
    );
    await _safeStart();
  }

  @override
  Widget build(BuildContext context) {
    final Color statusColor = _statusOk == null
        ? Colors.blueGrey
        : (_statusOk! ? Colors.green.shade700 : Colors.red.shade700);

    return Scaffold(
      appBar: AppBar(
        title: const Text(kAppName),
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
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'About',
            onPressed: _openAbout,
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error, [child]) {
              final details = error.errorDetails?.message ?? '';
              return Container(
                color: Colors.black,
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline,
                          color: Colors.white, size: 48),
                      const SizedBox(height: 12),
                      const Text(
                        'The camera could not be started',
                        style: TextStyle(color: Colors.white, fontSize: 18),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Code: ${error.errorCode.name}\n$details',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _restartCamera,
                        child: const Text('Try again'),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
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
                      'Sent: $_sent   |   PC: ${_ip.isEmpty ? "-" : "$_ip:$_port"}',
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

// ---------------------------------------------------------------------------
// Settings (Manual / Scan QR / Find PC automatically)
// ---------------------------------------------------------------------------

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
  int _mode = 0; // 0 = Manual, 1 = Scan QR
  String _testMsg = '';
  bool? _testOk;
  bool _finding = false;

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
    final savedIp = p.getString('ip') ?? '';
    setState(() {
      _ip.text = savedIp;
      _port.text = p.getString('port') ?? '8765';
      _pin.text = p.getString('pin') ?? '1234';
      _cool.text = (p.getInt('cooldown') ?? 3).toString();
      _mode = p.getInt('mode') ?? (savedIp.isEmpty ? 1 : 0);
    });
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('ip', _ip.text.trim());
    await p.setString(
        'port', _port.text.trim().isEmpty ? '8765' : _port.text.trim());
    await p.setString('pin', _pin.text.trim());
    await p.setInt('cooldown', int.tryParse(_cool.text.trim()) ?? 3);
    await p.setInt('mode', _mode);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _test() async {
    setState(() {
      _testMsg = 'Testing the connection...';
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
          _testMsg = 'Connected \u2713  Tap Save to keep these settings.';
          _testOk = true;
        });
      } else if (res.statusCode == 403) {
        setState(() {
          _testMsg = 'PC found, but the PIN is wrong.';
          _testOk = false;
        });
      } else {
        setState(() {
          _testMsg = 'The PC returned an error (${res.statusCode}).';
          _testOk = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testMsg =
            'Cannot reach the PC. Check the IP address, the network and that the receiver is running.';
        _testOk = false;
      });
    }
  }

  Future<void> _scanPair() async {
    final raw = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const PairScanPage()),
    );
    if (raw == null || !mounted) return;
    final parts = raw.split('|');
    if (parts.length < 5 || parts[0] != 'UHQR') {
      setState(() {
        _testMsg = 'This is not a UH Receiver QR code.';
        _testOk = false;
      });
      return;
    }
    setState(() {
      _ip.text = parts[2];
      _port.text = parts[3];
      _pin.text = parts[4];
    });
    await _test();
  }

  // Looks for the receiver on every local network of this phone
  // (Wi-Fi, hotspot, USB tethering). No internet is needed.
  Future<List<String>> _discoverReceivers() async {
    final int port = int.tryParse(_port.text.trim()) ?? 8765;
    final Set<String> prefixes = {};
    final Set<String> own = {};
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final ni in interfaces) {
        final name = ni.name.toLowerCase();
        // skip mobile-data and virtual interfaces
        if (name.contains('rmnet') ||
            name.contains('ccmni') ||
            name.contains('tun') ||
            name.contains('dummy')) {
          continue;
        }
        for (final a in ni.addresses) {
          final parts = a.address.split('.');
          if (parts.length == 4) {
            prefixes.add('${parts[0]}.${parts[1]}.${parts[2]}.');
            own.add(a.address);
          }
        }
      }
    } catch (_) {}

    final List<String> candidates = [];
    for (final prefix in prefixes) {
      for (var i = 1; i < 255; i++) {
        final ip = '$prefix$i';
        if (!own.contains(ip)) candidates.add(ip);
      }
    }

    final List<String> found = [];
    for (var i = 0; i < candidates.length; i += 60) {
      final batch = candidates.skip(i).take(60);
      await Future.wait(batch.map((ip) => _probe(ip, port, found)));
    }
    found.sort();
    return found;
  }

  Future<void> _probe(String ip, int port, List<String> found) async {
    try {
      final s = await Socket.connect(
        ip,
        port,
        timeout: const Duration(milliseconds: 700),
      );
      s.destroy();
      final res = await http
          .get(Uri.parse('http://$ip:$port/ping'))
          .timeout(const Duration(seconds: 2));
      if (res.statusCode == 200 && res.body.contains('UH QR Receiver')) {
        found.add(ip);
      }
    } catch (_) {}
  }

  Future<String?> _pickIp(List<String> ips) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Select PC'),
        children: [
          for (final ip in ips)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, ip),
              child: Text(ip, style: const TextStyle(fontSize: 18)),
            ),
        ],
      ),
    );
  }

  Future<void> _findPc() async {
    if (_finding) return;
    setState(() {
      _finding = true;
      _testMsg = 'Searching for the PC on the network...';
      _testOk = null;
    });
    final found = await _discoverReceivers();
    if (!mounted) return;
    setState(() => _finding = false);
    if (found.isEmpty) {
      setState(() {
        _testMsg =
            'No PC found. Make sure the receiver is running and both devices are on the same network (see Connection help).';
        _testOk = false;
      });
      return;
    }
    final String chosen =
        found.length == 1 ? found.first : (await _pickIp(found) ?? '');
    if (chosen.isEmpty || !mounted) return;
    setState(() {
      _ip.text = chosen;
    });
    await _test();
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> children = [
      SegmentedButton<int>(
        segments: const [
          ButtonSegment<int>(
            value: 0,
            label: Text('Manual'),
            icon: Icon(Icons.edit),
          ),
          ButtonSegment<int>(
            value: 1,
            label: Text('Scan QR'),
            icon: Icon(Icons.qr_code_scanner),
          ),
        ],
        selected: {_mode},
        onSelectionChanged: (s) => setState(() => _mode = s.first),
      ),
      const SizedBox(height: 16),
    ];

    if (_mode == 1) {
      children.addAll([
        const Text(
          '1. Start UH QR Receiver on the PC. The pairing QR opens in the browser.\n'
          '2. Tap the button below and scan the QR shown on the PC screen.',
          style: TextStyle(fontSize: 14, height: 1.4),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _scanPair,
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('Scan PC QR'),
        ),
        const SizedBox(height: 12),
        Text(
          _ip.text.trim().isEmpty
              ? 'No PC connected yet'
              : 'PC: ${_ip.text.trim()}:${_port.text.trim()}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ]);
    } else {
      children.addAll([
        TextField(
          controller: _ip,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'PC IP address',
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
      ]);
    }

    children.addAll([
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: _finding ? null : _findPc,
        icon: const Icon(Icons.search),
        label: Text(_finding ? 'Searching...' : 'Find PC automatically'),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const HelpPage()),
          ),
          icon: const Icon(Icons.help_outline),
          label: const Text('No Wi-Fi? Connection help'),
        ),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _cool,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: 'Ignore the same QR code for (seconds)',
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
    ]);

    if (_testMsg.isNotEmpty) {
      children.add(
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
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: children,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Scan the pairing QR shown by the PC receiver
// ---------------------------------------------------------------------------

class PairScanPage extends StatefulWidget {
  const PairScanPage({super.key});

  @override
  State<PairScanPage> createState() => _PairScanPageState();
}

class _PairScanPageState extends State<PairScanPage> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  bool _done = false;
  String _hint = 'Point the camera at the QR code shown on the PC screen';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final b in capture.barcodes) {
      final raw = b.rawValue;
      if (raw == null || raw.isEmpty) continue;
      if (raw.startsWith('UHQR|')) {
        _done = true;
        HapticFeedback.mediumImpact();
        if (mounted) Navigator.of(context).pop(raw);
        return;
      }
      if (mounted) {
        setState(() {
          _hint = 'This is not a UH Receiver QR code. Scan the one on the PC screen.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan PC QR')),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error, [child]) {
              return Container(
                color: Colors.black,
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    'The camera could not be started\nCode: ${error.errorCode.name}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              );
            },
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 16,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(_hint, style: const TextStyle(fontSize: 16)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Connection help
// ---------------------------------------------------------------------------

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  Widget _section(String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(body, style: const TextStyle(fontSize: 14.5, height: 1.45)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Connection help')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section(
            'Same Wi-Fi (internet not required)',
            'Connect the phone and the PC to the same Wi-Fi network. '
                'The router does not need an internet connection.',
          ),
          _section(
            'No Wi-Fi available?',
            'Use one of the options below, then tap "Find PC automatically" in Settings.',
          ),
          _section(
            'Option 1: Phone hotspot',
            'Turn on the hotspot on the phone and connect the PC to it. '
                'The PC needs a Wi-Fi adapter. Mobile data is not required.',
          ),
          _section(
            'Option 2: USB tethering',
            'Connect the phone to the PC with a USB cable, then turn on '
                'USB tethering in the phone hotspot / tethering settings. '
                'This also works on desktop PCs without Wi-Fi.',
          ),
          _section(
            'Good to know',
            '- The PC IP address can change when the network changes. '
                'Scanning the QR or using "Find PC automatically" always picks up the current one.\n'
                '- On the first run, allow the receiver in Windows Firewall (Private networks).\n'
                '- The phone and the PC must be on the same network.',
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// About
// ---------------------------------------------------------------------------

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  void _copy(BuildContext context, String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied to clipboard'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  Widget _row(BuildContext context, IconData icon, String label, String value,
      {bool copy = true}) {
    return ListTile(
      leading: Icon(icon),
      title: Text(
        label,
        style: const TextStyle(fontSize: 12, color: Colors.black54),
      ),
      subtitle: Text(
        value,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      trailing: copy
          ? IconButton(
              icon: const Icon(Icons.copy, size: 20),
              tooltip: 'Copy',
              onPressed: () => _copy(context, value),
            )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 8),
          const Icon(Icons.qr_code_scanner, size: 64, color: Colors.indigo),
          const SizedBox(height: 8),
          const Text(
            kAppName,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          Text(
            'Version $kVersion',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Colors.black54),
          ),
          const SizedBox(height: 16),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    kCompany,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(kIntro, style: TextStyle(fontSize: 14, height: 1.4)),
                ],
              ),
            ),
          ),
          Card(
            child: Column(
              children: [
                _row(context, Icons.person, 'Developer', kDeveloper,
                    copy: false),
                _row(context, Icons.phone, 'Phone', kPhone),
                _row(context, Icons.email, 'Email', kEmail),
                _row(context, Icons.location_on, 'Address', kAddress,
                    copy: false),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '\u00a9 2026 $kCompany. All rights reserved.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
    );
  }
}
