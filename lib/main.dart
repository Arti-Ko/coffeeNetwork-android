import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _vpn = MethodChannel('coffeenetwork/vpn');
const _mono = 'monospace';
final rootKey = GlobalKey<_CoffeeAppState>();
SharedPreferences? _prefs;

/// Runtime palette: dark/light + custom accent. Changing it and rebuilding the
/// root (rootKey) re-themes the whole UI.
class Pal {
  static bool dark = true;
  static Color accent = const Color(0xFFE8A33D);
  static const accentInk = Color(0xFF1A1206);

  static Color get bg => dark ? const Color(0xFF121010) : const Color(0xFFF4F1EC);
  static Color get card => dark ? const Color(0x16FFFFFF) : const Color(0x0D000000);
  static Color get card2 => dark ? const Color(0x10FFFFFF) : const Color(0x08000000);
  static Color get edge => dark ? const Color(0x24FFFFFF) : const Color(0x1F000000);
  static Color get ink => dark ? const Color(0xFFF3F0EA) : const Color(0xFF201C18);
  static Color get inkDim => dark ? const Color(0xFFB6AFA4) : const Color(0xFF55504A);
  static Color get inkFaint => dark ? const Color(0xFF837C72) : const Color(0xFF8A857C);
  static Color get hair => dark ? const Color(0x18FFFFFF) : const Color(0x14000000);
  static Color get glassShadow => dark ? const Color(0x66000000) : const Color(0x22000000);
}

const accentPresets = <Color>[
  Color(0xFFE8A33D), Color(0xFFB5742B), Color(0xFF55C26B), Color(0xFF3FB6B0),
  Color(0xFF4F8DF0), Color(0xFF9B7BE8), Color(0xFFE05A9C), Color(0xFFE0573C),
];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  _prefs = await SharedPreferences.getInstance();
  Pal.dark = _prefs!.getBool('dark') ?? true;
  Pal.accent = Color(_prefs!.getInt('accent') ?? 0xFFE8A33D);
  _applyOverlay();
  runApp(CoffeeApp(key: rootKey));
}

void _applyOverlay() {
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Pal.dark ? Brightness.light : Brightness.dark,
  ));
}

class CoffeeApp extends StatefulWidget {
  const CoffeeApp({super.key});
  @override
  State<CoffeeApp> createState() => _CoffeeAppState();
}

class _CoffeeAppState extends State<CoffeeApp> {
  void refresh() {
    _applyOverlay();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'coffeeNetwork',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Pal.dark ? Brightness.dark : Brightness.light,
        scaffoldBackgroundColor: Pal.bg,
        colorScheme: ColorScheme.fromSeed(seedColor: Pal.accent, brightness: Pal.dark ? Brightness.dark : Brightness.light),
      ),
      home: const HomeShell(),
    );
  }
}

class Server {
  final String id;
  String name;
  final String protocol;
  final String address;
  final int port;
  final String raw;
  Server(this.id, this.name, this.protocol, this.address, this.port, this.raw);

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'protocol': protocol, 'address': address, 'port': port, 'raw': raw};
  static Server fromJson(Map<String, dynamic> j) =>
      Server(j['id'], j['name'], j['protocol'], j['address'], j['port'], j['raw']);
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final _pager = PageController();
  bool connected = false;
  bool busy = false;
  String mode = 'tun';
  bool bypassRu = true;
  final List<Server> servers = [];
  String? selectedId;
  Set<String> excluded = {}; // package names that bypass the VPN
  List<Map<String, dynamic>> apps = []; // installed apps cache (for ИГНОР)
  Timer? _poll;
  // live speed (bytes/sec) derived from clash_api traffic totals
  int upSpeed = 0, downSpeed = 0;
  int _upT = 0, _downT = 0;
  DateTime? _tT;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 1), (_) => _refreshStatus());
    const seed = String.fromEnvironment('SEED');
    if (seed.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => importLinks(seed));
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _pager.dispose();
    super.dispose();
  }

  void _load() {
    final p = _prefs!;
    bypassRu = p.getBool('bypassRu') ?? true;
    mode = p.getString('mode') ?? 'tun';
    selectedId = p.getString('selectedId');
    excluded = (p.getStringList('exclude') ?? const <String>[]).toSet();
    final raw = p.getString('servers');
    if (raw != null) {
      try {
        for (final e in (jsonDecode(raw) as List)) {
          servers.add(Server.fromJson(e as Map<String, dynamic>));
        }
      } catch (_) {}
    }
    if (selectedId == null && servers.isNotEmpty) selectedId = servers.first.id;
  }

  void _save() {
    final p = _prefs!;
    p.setBool('bypassRu', bypassRu);
    p.setString('mode', mode);
    if (selectedId != null) p.setString('selectedId', selectedId!);
    p.setString('servers', jsonEncode(servers.map((s) => s.toJson()).toList()));
    p.setStringList('exclude', excluded.toList());
  }

  Server? get active {
    for (final s in servers) {
      if (s.id == selectedId) return s;
    }
    return null;
  }

  String get heroCode {
    if (busy) return connected ? 'BYE' : '...';
    if (!connected) return 'OFF';
    final a = active;
    if (a == null) return 'ON';
    final m = RegExp(r'[A-Za-zА-Яа-я0-9]+').allMatches(a.name).map((e) => e.group(0)).join();
    final code = m.isNotEmpty ? m.substring(0, m.length < 3 ? m.length : 3) : a.protocol;
    return code.toUpperCase();
  }

  Future<void> _refreshStatus() async {
    try {
      final raw = await _vpn.invokeMethod<String>('status');
      if (raw == null) return;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final running = j['running'] == true;
      var ds = downSpeed, us = upSpeed;
      if (running) {
        try {
          final t = jsonDecode(await _vpn.invokeMethod('traffic')) as Map<String, dynamic>;
          final down = (t['down'] as num).toInt(), up = (t['up'] as num).toInt();
          final now = DateTime.now();
          if (_tT != null) {
            final dt = now.difference(_tT!).inMilliseconds / 1000.0;
            if (dt > 0.1) {
              final d = ((down - _downT) / dt).round();
              final u = ((up - _upT) / dt).round();
              ds = d < 0 ? 0 : d;
              us = u < 0 ? 0 : u;
            }
          }
          _downT = down; _upT = up; _tT = now;
        } catch (_) {}
      } else {
        ds = 0; us = 0; _tT = null;
      }
      if (mounted && (running != connected || busy || ds != downSpeed || us != upSpeed)) {
        setState(() {
          connected = running;
          busy = false;
          downSpeed = ds;
          upSpeed = us;
        });
      }
    } catch (_) {}
  }

  static String fmtSpeed(int bps) {
    if (bps < 1024) return '$bps B/s';
    if (bps < 1024 * 1024) return '${(bps / 1024).round()} KB/s';
    return '${(bps / 1048576).toStringAsFixed(1)} MB/s';
  }

  Future<void> toggle() async {
    if (busy) return;
    if (!connected && active == null) {
      snack('Сначала добавьте и выберите сервер', err: true);
      _pager.animateToPage(1, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
      return;
    }
    setState(() => busy = true);
    try {
      if (connected) {
        await _vpn.invokeMethod('disconnect');
      } else {
        await _vpn.invokeMethod('connect', {'link': active!.raw, 'bypassRu': bypassRu, 'exclude': excluded.toList()});
      }
    } on PlatformException catch (e) {
      if (mounted) setState(() => busy = false);
      snack(e.message ?? 'Ошибка', err: true);
      return;
    }
  }

  void snack(String msg, {bool err = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: _mono, fontSize: 12)),
      backgroundColor: err ? const Color(0xFF2A1410) : const Color(0xFF1E1B18),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
    ));
  }

  Future<int> importLinks(String text) async {
    final links = text.split(RegExp(r'\s+')).where((l) => l.contains('://')).toList();
    int added = 0;
    for (final l in links) {
      try {
        final raw = await _vpn.invokeMethod<String>('parse', {'link': l});
        if (raw == null) continue;
        final j = jsonDecode(raw) as Map<String, dynamic>;
        final id = '${DateTime.now().microsecondsSinceEpoch}$added';
        servers.add(Server(id, j['name'] as String, j['protocol'] as String, j['host'] as String, j['port'] as int, l));
        added++;
      } catch (_) {}
    }
    if (added > 0) {
      setState(() => selectedId ??= servers.last.id);
      _save();
    }
    return added;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          _Backdrop(),
          SafeArea(
            minimum: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: PageView(
              controller: _pager,
              children: [
                _TicketPage(state: this),
                _ServersPage(state: this),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Backdrop extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(-0.7, -1.0),
          radius: 1.4,
          colors: [Pal.dark ? const Color(0xFF1E1813) : const Color(0xFFFBF7F0), Pal.bg],
          stops: const [0.0, 0.7],
        ),
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _Glass extends StatelessWidget {
  final Widget child;
  final Color color;
  const _Glass({required this.child, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Pal.edge, width: 1),
        boxShadow: [BoxShadow(color: Pal.glassShadow, blurRadius: 40, offset: const Offset(0, 24))],
      ),
      child: child,
    );
  }
}

Widget _label(String t) => Text(t, style: TextStyle(fontFamily: _mono, fontSize: 9, letterSpacing: 2.2, color: Pal.inkFaint));

// ===================== PAGE 1 =====================
class _TicketPage extends StatelessWidget {
  final _HomeShellState state;
  const _TicketPage({required this.state});
  @override
  Widget build(BuildContext context) {
    final on = state.connected && !state.busy;
    final a = state.active;
    return _Glass(
      color: Pal.card,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text.rich(TextSpan(children: [
              TextSpan(text: 'COFFEE\n', style: TextStyle(fontFamily: _mono, fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: 3, color: Pal.ink, height: 1.25)),
              TextSpan(text: 'NETWORK', style: TextStyle(fontFamily: _mono, fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: 3, color: Pal.accent)),
            ])),
            Icon(Icons.flight, color: Pal.accent, size: 26),
          ]),
          const SizedBox(height: 18),
          Container(
            decoration: BoxDecoration(border: Border(top: BorderSide(color: Pal.hair), bottom: BorderSide(color: Pal.hair))),
            child: IntrinsicHeight(child: Row(children: [
              Expanded(child: _cell('STATUS', state.busy ? '···' : (state.connected ? 'ONLINE' : 'OFFLINE'))),
              VerticalDivider(width: 1, color: Pal.hair),
              Expanded(child: Padding(padding: const EdgeInsets.only(left: 14), child: _cell('MODE', state.mode == 'tun' ? 'TUN · ALL' : 'SYS PROXY'))),
            ])),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(state.heroCode, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 150, height: 0.82, letterSpacing: -6, color: on ? Pal.accent : Pal.ink)),
            ),
          ),
          const SizedBox(height: 10),
          Text(a?.name ?? 'сервер не выбран', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 26, color: Pal.ink)),
          const SizedBox(height: 8),
          Divider(height: 1, color: Pal.hair),
          const SizedBox(height: 10),
          _meta('NODE', a == null ? '—' : '${a.address}:${a.port}'),
          _meta('PROTOCOL', a?.protocol.toUpperCase() ?? '—'),
          _meta('ROUTING', state.bypassRu ? 'RU-BYPASS' : 'FULL TUNNEL'),
          if (state.connected && !state.busy)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(children: [
                SizedBox(width: 96, child: _label('SPEED')),
                Icon(Icons.south, size: 13, color: Pal.accent),
                Text(' ${_HomeShellState.fmtSpeed(state.downSpeed)}   ', style: TextStyle(fontFamily: _mono, fontSize: 13, color: Pal.ink)),
                Icon(Icons.north, size: 13, color: Pal.accent),
                Text(' ${_HomeShellState.fmtSpeed(state.upSpeed)}', style: TextStyle(fontFamily: _mono, fontSize: 13, color: Pal.ink)),
              ]),
            ),
          const Spacer(),
          _ConnectButton(state: state),
          const SizedBox(height: 12),
          _ModeSeg(state: state),
          const SizedBox(height: 12),
          _BypassRow(state: state),
        ]),
      ),
    );
  }

  Widget _cell(String l, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _label(l),
          const SizedBox(height: 5),
          Text(v, style: TextStyle(fontFamily: _mono, fontSize: 13, letterSpacing: 1, color: Pal.ink)),
        ]),
      );

  Widget _meta(String l, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Row(children: [
          SizedBox(width: 96, child: _label(l)),
          Expanded(child: Text(v, style: TextStyle(fontFamily: _mono, fontSize: 13, color: Pal.inkDim), overflow: TextOverflow.ellipsis)),
        ]),
      );
}

class _ConnectButton extends StatelessWidget {
  final _HomeShellState state;
  const _ConnectButton({required this.state});
  @override
  Widget build(BuildContext context) {
    final on = state.connected && !state.busy;
    final label = state.busy ? (state.connected ? 'DISCONNECTING' : 'CONNECTING') : (state.connected ? 'DISCONNECT' : 'CONNECT');
    return GestureDetector(
      onTap: state.toggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 22),
        decoration: BoxDecoration(color: on ? Pal.accent : Pal.card2, borderRadius: BorderRadius.circular(18), border: Border.all(color: on ? Pal.accent : Pal.edge)),
        child: Row(children: [
          Container(width: 11, height: 11, decoration: BoxDecoration(shape: BoxShape.circle, color: on ? Pal.accentInk : (state.busy ? Pal.accent : Pal.inkFaint))),
          const SizedBox(width: 14),
          Text(label, style: TextStyle(fontFamily: _mono, fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 2, color: on ? Pal.accentInk : Pal.ink)),
          const Spacer(),
          Icon(Icons.arrow_forward, size: 20, color: on ? Pal.accentInk : Pal.ink),
        ]),
      ),
    );
  }
}

class _ModeSeg extends StatelessWidget {
  final _HomeShellState state;
  const _ModeSeg({required this.state});
  @override
  Widget build(BuildContext context) {
    Widget seg(String id, String text) {
      final sel = state.mode == id;
      return Expanded(
        child: GestureDetector(
          onTap: () { state.setState(() => state.mode = id); state._save(); },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 18),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: sel ? (Pal.dark ? const Color(0x1FFFFFFF) : const Color(0x14000000)) : Colors.transparent, borderRadius: BorderRadius.circular(13)),
            child: Text(text, style: TextStyle(fontFamily: _mono, fontSize: 13, letterSpacing: 1.5, color: sel ? Pal.ink : Pal.inkFaint)),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: Pal.hair, borderRadius: BorderRadius.circular(16)),
      child: Row(children: [seg('sys', 'SYS PROXY'), seg('tun', 'TUN · ALL')]),
    );
  }
}

class _BypassRow extends StatelessWidget {
  final _HomeShellState state;
  const _BypassRow({required this.state});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(border: Border.all(color: Pal.hair), borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('RU-BYPASS', style: TextStyle(fontFamily: _mono, fontSize: 13, letterSpacing: 1.4, fontWeight: FontWeight.w700, color: Pal.ink)),
          const SizedBox(height: 3),
          Text('РФ-домены и IP — мимо VPN', style: TextStyle(fontSize: 12, color: Pal.inkFaint)),
        ])),
        Switch(
          value: state.bypassRu,
          activeColor: Pal.accentInk,
          activeTrackColor: Pal.accent,
          onChanged: (v) { state.setState(() => state.bypassRu = v); state._save(); },
        ),
      ]),
    );
  }
}

// ===================== PAGE 2 =====================
class _ServersPage extends StatelessWidget {
  final _HomeShellState state;
  const _ServersPage({required this.state});
  @override
  Widget build(BuildContext context) {
    return _Glass(
      color: Pal.card2,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text.rich(TextSpan(children: [
              TextSpan(text: 'SERVERS ', style: TextStyle(fontFamily: _mono, fontSize: 13, letterSpacing: 2.4, color: Pal.inkDim)),
              TextSpan(text: state.servers.length.toString().padLeft(2, '0'), style: TextStyle(fontFamily: _mono, fontSize: 12, color: Pal.accent)),
            ])),
            _ghost('+ ДОБАВИТЬ', () => _addSheet(context)),
          ]),
          const SizedBox(height: 16),
          Expanded(
            child: state.servers.isEmpty
                ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('NO NODES YET', style: TextStyle(fontFamily: _mono, fontSize: 12, letterSpacing: 2, color: Pal.inkDim)),
                    const SizedBox(height: 8),
                    Text('нажми «+ ДОБАВИТЬ» и вставь ссылку', style: TextStyle(fontSize: 12, color: Pal.inkFaint)),
                  ]))
                : ListView.separated(
                    itemCount: state.servers.length,
                    separatorBuilder: (_, __) => Divider(height: 1, color: Pal.hair),
                    itemBuilder: (_, i) => _srvTile(context, state.servers[i]),
                  ),
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: Pal.hair),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _ghost('ИГНОР', () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Pal.dark ? const Color(0xFF1A1714) : Colors.white,
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
              builder: (_) => _ExclSheet(state: state),
            ))),
            const SizedBox(width: 8),
            Expanded(child: _ghost('LOG', () => state.snack('Лог ядра — позже'))),
            const SizedBox(width: 8),
            Expanded(child: _ghost('НАСТР', () => _settingsSheet(context))),
          ]),
        ]),
      ),
    );
  }

  Widget _srvTile(BuildContext context, Server s) {
    final sel = state.selectedId == s.id;
    return InkWell(
      onTap: () { state.setState(() => state.selectedId = s.id); state._save(); },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
        child: Row(children: [
          Container(
            constraints: const BoxConstraints(minWidth: 66),
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            decoration: BoxDecoration(border: Border.all(color: sel ? Pal.accent : Pal.hair), borderRadius: BorderRadius.circular(6)),
            child: Text(s.protocol.toUpperCase(), textAlign: TextAlign.center, style: TextStyle(fontFamily: _mono, fontSize: 10, color: sel ? Pal.accent : Pal.inkFaint)),
          ),
          const SizedBox(width: 13),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: sel ? Pal.accent : Pal.ink)),
            const SizedBox(height: 3),
            Text('${s.address}:${s.port}', style: TextStyle(fontFamily: _mono, fontSize: 11, color: Pal.inkFaint)),
          ])),
          IconButton(icon: Icon(Icons.close, size: 18, color: Pal.inkFaint), onPressed: () {
            state.setState(() {
              state.servers.removeWhere((x) => x.id == s.id);
              if (state.selectedId == s.id) state.selectedId = state.servers.isNotEmpty ? state.servers.first.id : null;
            });
            state._save();
          }),
        ]),
      ),
    );
  }

  void _addSheet(BuildContext context) {
    final ctrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      backgroundColor: Pal.dark ? const Color(0xFF1A1714) : const Color(0xFFFFFFFF),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(left: 18, right: 18, top: 18, bottom: 18 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          _label('ДОБАВИТЬ СЕРВЕР'),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            maxLines: 3,
            style: TextStyle(fontFamily: _mono, fontSize: 13, color: Pal.ink),
            decoration: InputDecoration(
              hintText: 'vless:// · hysteria2:// · vmess:// · ss:// · trojan:// · tuic://',
              hintStyle: TextStyle(fontFamily: _mono, fontSize: 11, color: Pal.inkFaint),
              filled: true,
              fillColor: Pal.dark ? const Color(0x66000000) : const Color(0x0D000000),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Pal.hair)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Pal.hair)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Pal.accent)),
            ),
          ),
          const SizedBox(height: 12),
          _solid('IMPORT', () async {
            final n = await state.importLinks(ctrl.text);
            if (ctx.mounted) Navigator.pop(ctx);
            if (n > 0) state.snack('+$n сервер(ов)'); else state.snack('Не распознал ссылку', err: true);
          }),
        ]),
      ),
    );
  }

  void _settingsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Pal.dark ? const Color(0xFF1A1714) : const Color(0xFFFFFFFF),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        void apply(VoidCallback f) {
          setSheet(f);
          _prefs!.setBool('dark', Pal.dark);
          _prefs!.setInt('accent', Pal.accent.value);
          rootKey.currentState?.refresh(); // MaterialApp theme + status bar
          state.setState(() {}); // rebuild the home pages (they read Pal directly)
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            _label('НАСТРОЙКИ'),
            const SizedBox(height: 16),
            _label('ТЕМА'),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: Pal.hair, borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                _themeSeg('ТЁМНАЯ', true, () => apply(() => Pal.dark = true)),
                _themeSeg('СВЕТЛАЯ', false, () => apply(() => Pal.dark = false)),
              ]),
            ),
            const SizedBox(height: 20),
            _label('АКЦЕНТ'),
            const SizedBox(height: 12),
            Wrap(spacing: 14, runSpacing: 14, children: [
              for (final c in accentPresets)
                GestureDetector(
                  onTap: () => apply(() => Pal.accent = c),
                  child: Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: c, shape: BoxShape.circle,
                      border: Border.all(color: Pal.accent.value == c.value ? Pal.ink : Colors.transparent, width: 3),
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 22),
            Text('coffeeNetwork v0.1.0', style: TextStyle(fontFamily: _mono, fontSize: 12, color: Pal.inkDim)),
          ]),
        );
      }),
    );
  }

  Widget _themeSeg(String t, bool wantDark, VoidCallback onTap) {
    final sel = Pal.dark == wantDark;
    return Expanded(child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: sel ? Pal.accent : Colors.transparent, borderRadius: BorderRadius.circular(11)),
        child: Text(t, style: TextStyle(fontFamily: _mono, fontSize: 12, letterSpacing: 1.2, color: sel ? Pal.accentInk : Pal.inkFaint)),
      ),
    ));
  }

  Widget _ghost(String t, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(border: Border.all(color: Pal.hair), borderRadius: BorderRadius.circular(12)),
          child: Text(t, style: TextStyle(fontFamily: _mono, fontSize: 12, letterSpacing: 1.2, color: Pal.inkDim)),
        ),
      );

  Widget _solid(String t, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 24),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: Pal.accent, borderRadius: BorderRadius.circular(12)),
          child: Text(t, style: TextStyle(fontFamily: _mono, fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: Pal.accentInk)),
        ),
      );
}

// ===================== exclusions (ИГНОР) =====================
class _ExclSheet extends StatefulWidget {
  final _HomeShellState state;
  const _ExclSheet({required this.state});
  @override
  State<_ExclSheet> createState() => _ExclSheetState();
}

class _ExclSheetState extends State<_ExclSheet> {
  late Set<String> working;
  String query = '';
  bool loading = false;

  @override
  void initState() {
    super.initState();
    working = Set<String>.from(widget.state.excluded);
    if (widget.state.apps.isEmpty) _loadApps();
  }

  Future<void> _loadApps() async {
    setState(() => loading = true);
    try {
      final raw = await _vpn.invokeMethod<String>('listApps');
      widget.state.apps = (jsonDecode(raw ?? '[]') as List).cast<Map<String, dynamic>>();
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  Future<void> _save() async {
    final st = widget.state;
    st.excluded = working;
    st.setState(() {});
    st._save();
    Navigator.pop(context);
    if (st.connected && st.active != null) {
      st.snack('Применяю исключения…');
      try {
        await _vpn.invokeMethod('disconnect');
        await Future.delayed(const Duration(milliseconds: 500));
        await _vpn.invokeMethod('connect', {'link': st.active!.raw, 'bypassRu': st.bypassRu, 'exclude': working.toList()});
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = query.toLowerCase();
    final apps = q.isEmpty ? widget.state.apps : widget.state.apps.where((a) => (a['name'] as String).toLowerCase().contains(q)).toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.78,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _label('ИГНОРИРОВАНИЕ VPN'),
            const SizedBox(height: 6),
            Text('отмеченные приложения идут мимо VPN (напрямую)', style: TextStyle(fontSize: 12, color: Pal.inkFaint)),
            const SizedBox(height: 12),
            TextField(
              onChanged: (v) => setState(() => query = v),
              style: TextStyle(fontFamily: _mono, fontSize: 13, color: Pal.ink),
              decoration: InputDecoration(
                hintText: 'Поиск приложения…',
                hintStyle: TextStyle(fontFamily: _mono, fontSize: 12, color: Pal.inkFaint),
                filled: true,
                fillColor: Pal.dark ? const Color(0x66000000) : const Color(0x0D000000),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Pal.hair)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Pal.hair)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Pal.accent)),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: loading
                  ? Center(child: CircularProgressIndicator(color: Pal.accent))
                  : (apps.isEmpty
                      ? Center(child: Text('Нет приложений', style: TextStyle(color: Pal.inkFaint, fontFamily: _mono, fontSize: 12)))
                      : ListView.builder(
                          itemCount: apps.length,
                          itemBuilder: (_, i) {
                            final a = apps[i];
                            final pkg = a['package'] as String;
                            final on = working.contains(pkg);
                            final icon = a['icon'] as String?;
                            return InkWell(
                              onTap: () => setState(() => on ? working.remove(pkg) : working.add(pkg)),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
                                child: Row(children: [
                                  if (icon != null)
                                    ClipRRect(borderRadius: BorderRadius.circular(7), child: Image.memory(base64Decode(icon.split(',').last), width: 34, height: 34, gaplessPlayback: true))
                                  else
                                    Container(width: 34, height: 34, decoration: BoxDecoration(color: Pal.hair, borderRadius: BorderRadius.circular(7))),
                                  const SizedBox(width: 13),
                                  Expanded(child: Text(a['name'] as String, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, color: on ? Pal.accent : Pal.ink, fontWeight: on ? FontWeight.w600 : FontWeight.w400))),
                                  Container(
                                    width: 22, height: 22,
                                    decoration: BoxDecoration(
                                      color: on ? Pal.accent : Colors.transparent,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: on ? Pal.accent : Pal.inkFaint, width: 1.5),
                                    ),
                                    child: on ? Icon(Icons.check, size: 15, color: Pal.accentInk) : null,
                                  ),
                                ]),
                              ),
                            );
                          },
                        )),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _save,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 15),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: Pal.accent, borderRadius: BorderRadius.circular(12)),
                child: Text('СОХРАНИТЬ (${working.length})', style: TextStyle(fontFamily: _mono, fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 1, color: Pal.accentInk)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
