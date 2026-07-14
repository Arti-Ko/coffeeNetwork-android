import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _vpn = MethodChannel('coffeenetwork/vpn');
const _import = MethodChannel('coffeenetwork/import');
const _mono = 'monospace';
const _ghRepo = 'Arti-Ko/coffeeNetwork-android'; // GitHub repo for update checks
const _updateProgress = EventChannel('coffeenetwork/update_progress'); // APK download %
final rootKey = GlobalKey<_CoffeeAppState>();
SharedPreferences? _prefs;
/// Полная перестройка приложения (смена темы) — ставится в _CoffeeAppState.
void Function()? appRefresh;

/// Runtime palette: style (visual skin) × dark/light + custom accent.
/// Changing it and rebuilding the root (rootKey) re-themes the whole UI.
/// Styles mirror the desktop client: classic | air | mag | dawn | poster | pult.
class Pal {
  // Редизайн: единственная тема — «Журнал» (бумага, графит, карамель).
  // Переключение стилей и светлой/тёмной удалено; style/dark оставлены
  // полями, т.к. по ним ветвятся виджеты, но значения фиксированы.
  static bool dark = false;
  static String style = 'mag';
  static Color accent = const Color(0xFFC9862B);
  /// Фон шторок и модалок — тёплая бумага (светлая) / графит (тёмная).
  static Color get paper => dark ? const Color(0xFF1E1E1E) : const Color(0xFFFBFAF6);
  // Text/icon color drawn ON the accent — flips with accent luminance so any
  // custom color stays readable (dark ink on light accent, light ink on dark).
  static Color get accentInk =>
      accent.computeLuminance() > 0.45 ? const Color(0xFF1A1206) : const Color(0xFFFBF3E6);

  /// Pick the (dark, light) pair for the current brightness.
  static Color _p(Color d, Color l) => dark ? d : l;

  static Color get bg {
    switch (style) {
      case 'air': return _p(const Color(0xFF1A140C), const Color(0xFFF8F4EE));
      case 'mag': return _p(const Color(0xFF161616), const Color(0xFFF4F3EF));
      case 'dawn': return _p(const Color(0xFF171A22), const Color(0xFFF1F0ED));
      case 'poster': return _p(const Color(0xFF100F13), const Color(0xFFF2F0EA));
      case 'pult': return _p(const Color(0xFF12161D), const Color(0xFFEEF0F3));
      default: return _p(const Color(0xFF121010), const Color(0xFFF4F1EC));
    }
  }

  static Color get card {
    switch (style) {
      case 'air': return _p(const Color(0xFF221C14), const Color(0xFFFFFFFF));
      case 'mag': return _p(const Color(0x00000000), const Color(0x00000000));
      case 'dawn': return _p(const Color(0x14FFFFFF), const Color(0x8CFFFFFF));
      case 'poster': return _p(const Color(0xFF201F24), const Color(0xFFFFFFFF));
      case 'pult': return _p(const Color(0xFF1D222A), const Color(0xFFFFFFFF));
      default: return _p(const Color(0x16FFFFFF), const Color(0x0D000000));
    }
  }

  static Color get card2 {
    switch (style) {
      case 'air': return _p(const Color(0xFF1D1810), const Color(0xFFFDFAF5));
      case 'mag': return _p(const Color(0x00000000), const Color(0x00000000));
      case 'dawn': return _p(const Color(0x0FFFFFFF), const Color(0x66FFFFFF));
      case 'poster': return _p(const Color(0xFF1C1B20), const Color(0xFFFAF8F3));
      case 'pult': return _p(const Color(0xFF1A1F26), const Color(0xFFFBFCFD));
      default: return _p(const Color(0x10FFFFFF), const Color(0x08000000));
    }
  }

  static Color get edge {
    switch (style) {
      case 'air': return _p(const Color(0x12FFFFFF), const Color(0x14785F37));
      case 'mag': return _p(const Color(0x00000000), const Color(0x00000000));
      case 'dawn': return _p(const Color(0x17FFFFFF), const Color(0x1A46321F));
      case 'poster': return _p(const Color(0xFFF2F0EA), const Color(0xFF141310));
      case 'pult': return _p(const Color(0xFF262C35), const Color(0xFFE2E5EA));
      default: return _p(const Color(0x24FFFFFF), const Color(0x1F000000));
    }
  }

  static Color get ink {
    switch (style) {
      case 'air': return _p(const Color(0xFFEFE8DD), const Color(0xFF2C251D));
      case 'mag': return _p(const Color(0xFFECE9E2), const Color(0xFF1C1A17));
      case 'dawn': return _p(const Color(0xFFECEAE4), const Color(0xFF29241D));
      case 'poster': return _p(const Color(0xFFF2F0EA), const Color(0xFF141310));
      case 'pult': return _p(const Color(0xFFE8EAEE), const Color(0xFF161A20));
      default: return _p(const Color(0xFFF3F0EA), const Color(0xFF201C18));
    }
  }

  static Color get inkDim {
    switch (style) {
      case 'air': return _p(const Color(0xFFA99E8D), const Color(0xFF7A7060));
      case 'mag': return _p(const Color(0xFF97938A), const Color(0xFF55524B));
      case 'dawn': return _p(const Color(0xFF9B968C), const Color(0xFF6F6A60));
      case 'poster': return _p(const Color(0xFFB9B6AD), const Color(0xFF3F3D38));
      case 'pult': return _p(const Color(0xFF9AA1AC), const Color(0xFF5C6470));
      default: return _p(const Color(0xFFB6AFA4), const Color(0xFF55504A));
    }
  }

  static Color get inkFaint {
    switch (style) {
      case 'air': return _p(const Color(0xFF7C7263), const Color(0xFF9A9184));
      case 'mag': return _p(const Color(0xFF6E6A61), const Color(0xFF8B877E));
      case 'dawn': return _p(const Color(0xFF6E6A61), const Color(0xFF9B968C));
      case 'poster': return _p(const Color(0xFF8A877E), const Color(0xFF6E6B63));
      case 'pult': return _p(const Color(0xFF6B7280), const Color(0xFF8A919C));
      default: return _p(const Color(0xFF837C72), const Color(0xFF8A857C));
    }
  }

  static Color get hair {
    switch (style) {
      case 'air': return _p(const Color(0x14FFFFFF), const Color(0x173C2D19));
      case 'mag': return _p(const Color(0x29ECE9E2), const Color(0xFFDEDBD2));
      case 'dawn': return _p(const Color(0x1AFFFFFF), const Color(0x1A46321F));
      case 'poster': return _p(const Color(0x59F2F0EA), const Color(0x8C141310));
      case 'pult': return _p(const Color(0x14FFFFFF), const Color(0x14141923));
      default: return _p(const Color(0x18FFFFFF), const Color(0x14000000));
    }
  }

  static Color get glassShadow {
    switch (style) {
      case 'air': return _p(const Color(0x59000000), const Color(0x1A543C1A));
      case 'mag': return _p(const Color(0x00000000), const Color(0x00000000));
      case 'dawn': return _p(const Color(0x40000000), const Color(0x1A3C2D14));
      case 'poster': return _p(const Color(0x00000000), const Color(0x00000000));
      case 'pult': return _p(const Color(0x4D000000), const Color(0x121A2030));
      default: return _p(const Color(0x66000000), const Color(0x22000000));
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  _prefs = await SharedPreferences.getInstance();
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

class _CoffeeAppState extends State<CoffeeApp> with WidgetsBindingObserver {
  void refresh() {
    _applyOverlay();
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    appRefresh = refresh;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (appRefresh == refresh) appRefresh = null;
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() => refresh(); // «системная» тема следует за ОС

  @override
  Widget build(BuildContext context) {
    final pick = _prefs?.getString('theme') ?? 'light';
    Pal.dark = pick == 'dark' ||
        (pick == 'system' &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark);
    return MaterialApp(
      title: 'coffeeNetwork',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Pal.dark ? Brightness.dark : Brightness.light,
        scaffoldBackgroundColor: Pal.bg,
        colorScheme: ColorScheme.fromSeed(seedColor: Pal.accent, brightness: Pal.dark ? Brightness.dark : Brightness.light),
      ),
      // дизайн с фиксированными размерами: системный масштаб текста игнорируем,
      // иначе слово-статус и кнопки «плавают» от устройства к устройству
      builder: (context, child) => MediaQuery.withNoTextScaling(child: child!),
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
  final String? mobileRaw; // optional fallback link for cellular (e.g. VLESS Reality)

  Server(this.id, this.name, this.protocol, this.address, this.port, this.raw,
      {this.mobileRaw});

  Server withMobile(String? mobile) =>
      Server(id, name, protocol, address, port, raw, mobileRaw: mobile?.isEmpty == true ? null : mobile);

  Map<String, dynamic> toJson() => {
        'id': id, 'name': name, 'protocol': protocol,
        'address': address, 'port': port, 'raw': raw,
        if (mobileRaw != null && mobileRaw!.isNotEmpty) 'mobileRaw': mobileRaw,
      };
  static Server fromJson(Map<String, dynamic> j) => Server(
        j['id'] as String, j['name'] as String, j['protocol'] as String,
        j['address'] as String, j['port'] as int, j['raw'] as String,
        mobileRaw: j['mobileRaw'] as String?,
      );
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
  DateTime? since; // session start — for the timer in air/dawn/pult/mag styles
  int _upT = 0, _downT = 0;
  DateTime? _tT;
  // active protocol/node updated by Kotlin on reconnect (e.g. WiFi→cellular switch)
  String? _liveProtocol;
  String? _liveNode;
  bool onboard = false; // first-launch visual tutorial overlay
  String appVer = '0.1.6'; // current version, refreshed from native on launch

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 1), (_) => _refreshStatus());
    _import.setMethodCallHandler((call) async {
      if (call.method == 'importBundle') {
        final url = (call.arguments as Map)['url'] as String? ?? '';
        if (url.isNotEmpty) {
          final n = await importLinks(url);
          if (mounted) snack(n > 0 ? 'Импортировано: $n' : 'Ошибка импорта');
        }
      }
    });
    const seed = String.fromEnvironment('SEED');
    if (seed.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => importLinks(seed));
    }
    _appVersion().then((v) {
      if (v != null && v.isNotEmpty && mounted) setState(() => appVer = v);
    });
    // background update check shortly after launch (skips a dismissed version)
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) checkUpdate();
    });
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
    onboard = !(p.getBool('onboarded') ?? false);
  }

  void _finishOnboarding() {
    _prefs!.setBool('onboarded', true);
    setState(() => onboard = false);
  }

  Future<String?> _appVersion() async {
    try {
      return await _vpn.invokeMethod<String>('appVersion');
    } catch (_) {
      return null;
    }
  }

  /// True if semver-ish [remote] (e.g. "0.1.3") is newer than [local] ("0.1.2").
  static bool _isNewer(String remote, String local) {
    List<int> parts(String s) =>
        s.replaceFirst(RegExp(r'^v'), '').split(RegExp(r'[.+\-]')).map((x) => int.tryParse(x) ?? 0).toList();
    final r = parts(remote), l = parts(local);
    for (var i = 0; i < 3; i++) {
      final a = i < r.length ? r[i] : 0;
      final b = i < l.length ? l[i] : 0;
      if (a != b) return a > b;
    }
    return false;
  }

  /// Check GitHub Releases for a newer APK. [manual] = triggered from settings:
  /// always reports a result and ignores the per-version skip list.
  Future<void> checkUpdate({bool manual = false}) async {
    if (manual) snack('Проверяю обновления…');
    HttpClient? client;
    try {
      final cur = await _appVersion() ?? appVer;
      client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      final req = await client.getUrl(Uri.parse('https://api.github.com/repos/$_ghRepo/releases/latest'));
      req.headers.set(HttpHeaders.userAgentHeader, 'coffeeNetwork-android');
      req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      final resp = await req.close().timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200) {
        if (manual) snack('Не удалось проверить обновления', err: true);
        return;
      }
      final body = await resp.transform(utf8.decoder).join();
      final j = jsonDecode(body) as Map<String, dynamic>;
      final ver = ((j['tag_name'] as String?) ?? '').replaceFirst(RegExp(r'^v'), '');
      final notes = (j['body'] as String?) ?? '';
      final pageUrl = (j['html_url'] as String?) ?? 'https://github.com/$_ghRepo/releases/latest';
      String? apkUrl;
      for (final a in (j['assets'] as List? ?? const [])) {
        final name = ((a as Map)['name'] as String?) ?? '';
        if (name.toLowerCase().endsWith('.apk')) {
          apkUrl = a['browser_download_url'] as String?;
          break;
        }
      }
      if (ver.isEmpty || !_isNewer(ver, cur)) {
        if (manual) snack('У вас последняя версия ($cur)');
        return;
      }
      if (!manual && _prefs!.getString('skipVersion') == ver) return;
      if (mounted) _showUpdateDialog(ver, notes, apkUrl ?? pageUrl);
    } catch (_) {
      if (manual) snack('Не удалось проверить обновления', err: true);
    } finally {
      client?.close(force: true);
    }
  }

  void _showUpdateDialog(String ver, String notes, String url) {
    showDialog(
      context: context,
      builder: (_) => _UpdateDialog(
        ver: ver,
        notes: notes,
        url: url,
        current: appVer,
        onSkip: () => _prefs!.setString('skipVersion', ver),
      ),
    );
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
      final ap = j['activeProtocol'] as String?;
      final ah = j['activeHost'] as String?;
      final aport = j['activePort'] as int?;
      final liveNode = (ah != null && aport != null && aport > 0) ? '$ah:$aport' : null;
      // `running` в условии — чтобы тикал таймер сессии, пока подключены
      if (mounted && (running != connected || busy || ds != downSpeed || us != upSpeed
          || ap != _liveProtocol || liveNode != _liveNode || running)) {
        setState(() {
          connected = running;
          since = running ? (since ?? DateTime.now()) : null;
          busy = false;
          downSpeed = ds;
          upSpeed = us;
          _liveProtocol = running ? ap : null;
          _liveNode = running ? liveNode : null;
        });
      }
    } catch (_) {}
  }

  static String fmtSpeed(int bps) {
    if (bps < 1024) return '$bps B/s';
    if (bps < 1024 * 1024) return '${(bps / 1024).round()} KB/s';
    return '${(bps / 1048576).toStringAsFixed(1)} MB/s';
  }

  /// «00 : 42 : 17» — длительность текущей сессии (или «—»).
  String get sessionStr {
    final s = since;
    if (s == null) return '—';
    final d = DateTime.now().difference(s);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inHours)} : ${two(d.inMinutes % 60)} : ${two(d.inSeconds % 60)}';
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
        await _vpn.invokeMethod('connect', {
          'link': active!.raw,
          'bypassRu': bypassRu,
          'exclude': excluded.toList(),
          if ((active!.mobileRaw ?? '').isNotEmpty) 'mobileLink': active!.mobileRaw,
        });
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
    int added = 0;

    // Handle coffee://bundle single-string format
    for (final part in text.split(RegExp(r'\s+'))) {
      if (part.startsWith('coffee://bundle')) {
        final uri = Uri.tryParse(part);
        if (uri != null) {
          final w = uri.queryParameters['w'];
          final m = uri.queryParameters['m'];
          if (w != null) {
            try {
              final wifiLink = utf8.decode(base64Url.decode(base64Url.normalize(w)));
              final mobileLink = m != null
                  ? utf8.decode(base64Url.decode(base64Url.normalize(m)))
                  : null;
              final raw = await _vpn.invokeMethod<String>('parse', {'link': wifiLink});
              if (raw != null) {
                final j = jsonDecode(raw) as Map<String, dynamic>;
                final id = '${DateTime.now().microsecondsSinceEpoch}$added';
                servers.add(Server(
                  id,
                  j['name'] as String,
                  j['protocol'] as String,
                  j['host'] as String,
                  j['port'] as int,
                  wifiLink,
                  mobileRaw: mobileLink,
                ));
                added++;
              }
            } catch (_) {}
          }
        }
      }
    }

    final links = text.split(RegExp(r'\s+')).where((l) => l.contains('://') && !l.startsWith('coffee://bundle')).toList();
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
          _Backdrop(on: connected && !busy),
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
          if (onboard) Positioned.fill(child: _Onboarding(onDone: _finishOnboarding)),
        ],
      ),
    );
  }
}

class _Backdrop extends StatelessWidget {
  /// Connected state — «Рассвет» красит весь фон по состоянию подключения.
  final bool on;
  const _Backdrop({this.on = false});

  @override
  Widget build(BuildContext context) {
    if (Pal.style == 'dawn') {
      final colors = Pal.dark
          ? (on
              ? [const Color(0xFF191410), const Color(0xFF2A1D0C), const Color(0xFF3D2A10)]
              : [const Color(0xFF191A1E), const Color(0xFF131418), const Color(0xFF131418)])
          : (on
              ? [const Color(0xFFFDF4E2), const Color(0xFFF8DFB0), const Color(0xFFF3CB8A)]
              : [const Color(0xFFF1F0ED), const Color(0xFFE6E7E7), const Color(0xFFE6E7E7)]);
      return AnimatedContainer(
        duration: const Duration(milliseconds: 600),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: colors,
          ),
        ),
        child: const SizedBox.expand(),
      );
    }
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
    switch (Pal.style) {
      case 'mag':
        // «Журнал»: без карточек — контент лежит прямо на бумаге
        return SizedBox.expand(child: child);
      case 'poster':
        // «Плакат»: жёсткая рамка + офсетная тень без размытия
        return Container(
          decoration: BoxDecoration(
            color: Pal.card,
            border: Border.all(color: Pal.edge, width: 2.5),
            boxShadow: [BoxShadow(color: Pal.edge, offset: const Offset(7, 7))],
          ),
          child: child,
        );
      case 'pult':
        // «Пульт»: плитка с чётким рёбрышком, компактный радиус
        return Container(
          decoration: BoxDecoration(
            color: Pal.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Pal.edge, width: 1),
            boxShadow: [BoxShadow(color: Pal.glassShadow, blurRadius: 24, offset: const Offset(0, 8))],
          ),
          child: child,
        );
      case 'air':
        // «Воздух»: сплошная молочная карточка, крупный радиус, мягкая тень
        return Container(
          decoration: BoxDecoration(
            color: Pal.card,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [BoxShadow(color: Pal.glassShadow, blurRadius: 36, offset: const Offset(0, 14))],
          ),
          child: child,
        );
      case 'dawn':
        // «Рассвет»: полупрозрачное стекло над градиентом состояния
        return Container(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: Pal.edge, width: 1),
          ),
          child: child,
        );
      default:
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
}

Widget _label(String t) => Text(t, style: TextStyle(fontFamily: _mono, fontSize: 9, letterSpacing: 2.2, color: Pal.inkFaint));

// ===================== PAGE 1 =====================
class _TicketPage extends StatelessWidget {
  final _HomeShellState state;
  const _TicketPage({required this.state});

  @override
  Widget build(BuildContext context) {
    switch (Pal.style) {
      case 'air': return _air(context);
      case 'mag': return _mag(context);
      case 'dawn': return _dawn(context);
      case 'poster': return _poster(context);
      case 'pult': return _pult(context);
      default: return _classic(context);
    }
  }

  // ---------- shared bits ----------
  void _toServers() => state._pager.animateToPage(1,
      duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);

  Widget _bean(double s) => Container(
        width: s, height: s,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFFE8A33D), Color(0xFFC47C22)]),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(s / 2), topRight: Radius.circular(s / 2),
            bottomRight: Radius.circular(s / 2), bottomLeft: Radius.circular(s / 6),
          ),
        ),
      );

  /// Текстовый переключатель режима — активный подчёркнут карамелью.
  Widget _modeLink(String t, String id) {
    final sel = state.mode == id;
    return GestureDetector(
      onTap: () { state.setState(() => state.mode = id); state._save(); },
      child: Container(
        padding: const EdgeInsets.only(bottom: 2),
        decoration: sel
            ? BoxDecoration(border: Border(bottom: BorderSide(color: Pal.accent, width: 2)))
            : null,
        child: Text(t, style: TextStyle(fontSize: 13.5,
            fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
            color: sel ? Pal.ink : Pal.inkDim)),
      ),
    );
  }

  Widget _brandRow() => Row(mainAxisSize: MainAxisSize.min, children: [
        _bean(24),
        const SizedBox(width: 9),
        Text('coffee network', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: Pal.ink)),
      ]);

  Widget _gearBtn() => GestureDetector(
        onTap: _toServers,
        child: Container(
          width: 38, height: 38, alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, color: Pal.card),
          child: Icon(Icons.tune, size: 18, color: Pal.inkDim),
        ),
      );

  Widget _statPill(IconData i, String v) => Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        decoration: BoxDecoration(
          color: Pal.card, borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Pal.glassShadow, blurRadius: 14, offset: const Offset(0, 4))],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(i, size: 14, color: Pal.accent),
          const SizedBox(width: 7),
          Text(v, style: TextStyle(fontFamily: _mono, fontSize: 13, color: Pal.ink)),
        ]),
      );

  // ---------- ВОЗДУХ: кольцо по центру, техника в карточках ----------
  Widget _air(BuildContext context) {
    final on = state.connected && !state.busy;
    final a = state.active;
    Widget card(Widget child) => Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: BoxDecoration(
            color: Pal.card, borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Pal.glassShadow, blurRadius: 18, offset: const Offset(0, 6))],
          ),
          child: child,
        );
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 0),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [_brandRow(), _gearBtn()]),
      ),
      Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(state.busy ? '···' : (on ? 'Защищено' : 'Отключено'),
            style: TextStyle(fontSize: 15, fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                color: on ? Pal.accent : Pal.inkFaint)),
        const SizedBox(height: 22),
        _ConnectButton(state: state),
        if (on) ...[
          const SizedBox(height: 16),
          Text(state.sessionStr, style: TextStyle(fontFamily: _mono, fontSize: 13.5, color: Pal.inkFaint)),
          const SizedBox(height: 14),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _statPill(Icons.south, _HomeShellState.fmtSpeed(state.downSpeed)),
            const SizedBox(width: 10),
            _statPill(Icons.north, _HomeShellState.fmtSpeed(state.upSpeed)),
          ]),
        ],
      ])),
      Padding(
        padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
        child: Column(children: [
          GestureDetector(
            onTap: _toServers,
            child: card(Row(children: [
              Container(
                width: 40, height: 40, alignment: Alignment.center,
                decoration: BoxDecoration(color: Pal.bg, borderRadius: BorderRadius.circular(13)),
                child: Text((a?.protocol ?? '—').toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '').padRight(1).substring(0, 1),
                    style: TextStyle(fontFamily: _mono, fontSize: 15, fontWeight: FontWeight.w700, color: Pal.accent)),
              ),
              const SizedBox(width: 13),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(on ? 'Подключено · ${(state._liveProtocol ?? a?.protocol ?? '—').toUpperCase()}' : 'Сервер',
                    style: TextStyle(fontSize: 12, color: Pal.inkFaint)),
                const SizedBox(height: 2),
                Text(a?.name ?? 'не выбран', maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Pal.ink)),
              ])),
              Icon(Icons.chevron_right, size: 22, color: Pal.inkFaint),
            ])),
          ),
          const SizedBox(height: 10),
          card(Row(children: [
            Expanded(child: Text('Режим трафика', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: Pal.ink))),
            _miniSeg(),
          ])),
          const SizedBox(height: 10),
          card(Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Сайты РФ — напрямую', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: Pal.ink)),
              const SizedBox(height: 2),
              Text('госуслуги и банки работают как обычно', style: TextStyle(fontSize: 12, color: Pal.inkFaint)),
            ])),
            Switch(
              value: state.bypassRu,
              activeColor: Pal.accentInk,
              activeTrackColor: Pal.accent,
              onChanged: (v) { state.setState(() => state.bypassRu = v); state._save(); },
            ),
          ])),
        ]),
      ),
    ]);
  }

  Widget _miniSeg() {
    Widget seg(String id, String t) {
      final sel = state.mode == id;
      return GestureDetector(
        onTap: () { state.setState(() => state.mode = id); state._save(); },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 12),
          decoration: BoxDecoration(
            color: sel ? Pal.bg : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(t, style: TextStyle(fontSize: 12.5,
              fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
              color: sel ? Pal.ink : Pal.inkFaint)),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: Pal.hair, borderRadius: BorderRadius.circular(13)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [seg('sys', 'Прокси'), seg('tun', 'Весь (TUN)')]),
    );
  }

  // ---------- ЖУРНАЛ: слово-статус и текстовые действия ----------
  /// «24,3» — МБ/с без единиц, как в макете «Журнала».
  String _magSpeed(int bps) => (bps / 1048576).toStringAsFixed(1).replaceAll('.', ',');

  /// «00:42» — часы:минуты сессии, компактно как в макете.
  String _magTime() {
    final t = state.sessionStr.replaceAll(' ', '');
    return t.length >= 5 ? t.substring(0, 5) : t;
  }

  Widget _mag(BuildContext context) {
    final on = state.connected && !state.busy;
    final a = state.active;
    // перенос как в макете: «отклю-/чено.», точка — круглая, отдельным кружком
    final word = state.busy ? 'секунду' : (on ? 'защи-\nщено' : 'отклю-\nчено');
    final top3 = state.servers.take(3).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [
            _bean(18),
            const SizedBox(width: 8),
            Text('COFFEE NETWORK', style: TextStyle(fontSize: 11, letterSpacing: 3.4, fontWeight: FontWeight.w600, color: Pal.inkDim)),
          ]),
          GestureDetector(onTap: _toServers, child: Text('серверы →', style: TextStyle(fontSize: 13, color: Pal.inkDim))),
        ]),
        const Spacer(),
        // FittedBox растягивает слово на всю доступную ширину; правый отступ
        // даёт ~10-15% воздуха от края на любом экране
        Padding(
          padding: EdgeInsets.only(right: MediaQuery.of(context).size.width * 0.07),
          child: SizedBox(
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.fitWidth,
              alignment: Alignment.centerLeft,
              child: Text.rich(TextSpan(children: [
                TextSpan(text: word, style: TextStyle(fontSize: 76, height: 1.04, letterSpacing: -3,
                    fontWeight: FontWeight.w800, color: on ? Pal.accent : Pal.ink)),
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 7),
                    child: Container(width: 14, height: 14,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: on ? Pal.ink : Pal.accent)),
                  ),
                ),
              ])),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('${a?.name ?? 'сервер не выбран'} · ${(a?.protocol ?? '—').toLowerCase()}',
            style: TextStyle(fontSize: 17, color: Pal.inkDim)),
        if (on)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text.rich(TextSpan(
              style: TextStyle(fontFamily: _mono, fontSize: 16, color: Pal.ink),
              children: [
                TextSpan(text: '↓ ', style: TextStyle(color: Pal.accent)),
                TextSpan(text: _magSpeed(state.downSpeed)),
                const TextSpan(text: '  '),
                TextSpan(text: '↑ ', style: TextStyle(color: Pal.accent)),
                TextSpan(text: _magSpeed(state.upSpeed)),
                const TextSpan(text: '  '),
                TextSpan(text: _magTime(), style: TextStyle(color: Pal.inkDim)),
              ],
            )),
          ),
        const SizedBox(height: 30),
        _ConnectButton(state: state),
        if (!on) ...[
          const SizedBox(height: 24),
          Wrap(spacing: 18, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            _modeLink('весь трафик', 'tun'),
            _modeLink('только прокси', 'sys'),
            GestureDetector(
              onTap: () { state.setState(() => state.bypassRu = !state.bypassRu); state._save(); },
              child: Text('сайты РФ — напрямую ${state.bypassRu ? '✓' : '✕'}',
                  style: TextStyle(fontSize: 13.5, color: Pal.inkDim)),
            ),
          ]),
        ],
        const Spacer(),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.only(bottom: 9),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Pal.ink, width: 1.5))),
          child: Text('СЕРВЕРЫ — ${state.servers.length.toString().padLeft(2, '0')}',
              style: TextStyle(fontSize: 10.5, letterSpacing: 3, fontWeight: FontWeight.w600, color: Pal.inkFaint)),
        ),
        for (final s in top3)
          GestureDetector(
            onTap: () { state.setState(() => state.selectedId = s.id); state._save(); },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Pal.hair))),
              child: Row(children: [
                SizedBox(width: 28, child: Text((top3.indexOf(s) + 1).toString().padLeft(2, '0'),
                    style: TextStyle(fontFamily: _mono, fontSize: 11,
                        color: state.selectedId == s.id ? Pal.accent : Pal.inkFaint,
                        fontWeight: state.selectedId == s.id ? FontWeight.w700 : FontWeight.w400))),
                Expanded(child: Text(s.name.toLowerCase(), maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 16.5,
                        fontWeight: state.selectedId == s.id ? FontWeight.w600 : FontWeight.w400,
                        color: state.selectedId == s.id ? Pal.ink : Pal.inkDim))),
                if (state.selectedId == s.id)
                  Padding(padding: const EdgeInsets.only(right: 8),
                      child: Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: Pal.accent))),
                Text(s.protocol.toUpperCase(), style: TextStyle(fontSize: 10, letterSpacing: 1.4, color: Pal.inkFaint)),
              ]),
            ),
          ),
        const SizedBox(height: 12),
        Row(children: [
          GestureDetector(onTap: _toServers, child: Container(
            padding: const EdgeInsets.only(bottom: 2),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Pal.accent, width: 1.5))),
            child: Text('+ добавить', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Pal.accent)),
          )),
          const SizedBox(width: 20),
          GestureDetector(onTap: _toServers, child: Container(
            padding: const EdgeInsets.only(bottom: 2),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Pal.hair, width: 1.5))),
            child: Text('все серверы', style: TextStyle(fontSize: 13, color: Pal.inkDim)),
          )),
        ]),
        const SizedBox(height: 8),
      ]),
    );
  }

  // ---------- РАССВЕТ: цвет фона = статус, пилюля и чипы ----------
  Widget _dawn(BuildContext context) {
    final on = state.connected && !state.busy;
    final a = state.active;
    Widget chip(String t, {bool lead = false, VoidCallback? onTap}) => GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 15),
            decoration: BoxDecoration(color: Pal.card, borderRadius: BorderRadius.circular(999)),
            child: Text(t, style: TextStyle(fontSize: 12.5,
                fontWeight: lead ? FontWeight.w600 : FontWeight.w400, color: Pal.ink)),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          _brandRow(),
          GestureDetector(onTap: _toServers, child: Container(
            padding: const EdgeInsets.only(bottom: 1),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Pal.inkFaint))),
            child: Text('настройки', style: TextStyle(fontSize: 13, color: Pal.inkDim)),
          )),
        ]),
        Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(state.busy ? '···' : (on ? 'защищено' : 'не защищено'),
              style: TextStyle(fontSize: 34, letterSpacing: -0.8,
                  fontWeight: on ? FontWeight.w500 : FontWeight.w300,
                  color: on ? const Color(0xFF8A5410) : Pal.ink)),
          const SizedBox(height: 8),
          Text(on
                  ? '${a?.name ?? ''} · ${state.sessionStr}'
                  : 'Трафик идёт напрямую${a != null ? ' · выбран ${a.name}' : ''}',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 13.5, color: Pal.inkDim)),
          const SizedBox(height: 26),
          _ConnectButton(state: state),
          const SizedBox(height: 24),
          Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
            chip(state.mode == 'tun' ? 'Весь трафик' : 'Только прокси', lead: true, onTap: () {
              state.setState(() => state.mode = state.mode == 'tun' ? 'sys' : 'tun');
              state._save();
            }),
            chip('РФ напрямую ${state.bypassRu ? '✓' : '✕'}', onTap: () {
              state.setState(() => state.bypassRu = !state.bypassRu);
              state._save();
            }),
            if (on) chip('↓ ${_HomeShellState.fmtSpeed(state.downSpeed)}'),
            if (on) chip('↑ ${_HomeShellState.fmtSpeed(state.upSpeed)}'),
          ]),
        ])),
        GestureDetector(
          onTap: _toServers,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
            decoration: BoxDecoration(color: Pal.card, borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Pal.edge)),
            child: Row(children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: Pal.accent)),
              const SizedBox(width: 11),
              Expanded(child: Text(a?.name ?? 'сервер не выбран', maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: Pal.ink))),
              Text((a?.protocol ?? '').toUpperCase(),
                  style: TextStyle(fontSize: 10, letterSpacing: 1.4, color: Pal.inkFaint)),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        GestureDetector(onTap: _toServers,
            child: Text('все серверы · игнор · лог', style: TextStyle(fontSize: 12.5, color: Pal.inkFaint))),
      ]),
    );
  }

  // ---------- ПЛАКАТ: рубленое слово, чекбоксы, маркер ----------
  Widget _poster(BuildContext context) {
    final on = state.connected && !state.busy;
    final a = state.active;
    final top2 = state.servers.take(2).toList();
    Widget check(String t, bool v, VoidCallback onTap) => GestureDetector(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              Container(
                width: 17, height: 17, alignment: Alignment.center,
                decoration: BoxDecoration(color: Pal.card, border: Border.all(color: Pal.edge, width: 2.5)),
                child: v ? Text('✕', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Pal.ink, height: 1)) : null,
              ),
              const SizedBox(width: 10),
              Text(t, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: Pal.ink)),
            ]),
          ),
        );
    final markerBg = Pal.dark ? const Color(0x33FFD23F) : const Color(0xFFFFD23F);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 13),
          decoration: BoxDecoration(
            color: Pal.card, border: Border.all(color: Pal.edge, width: 2),
            boxShadow: [BoxShadow(color: Pal.edge, offset: const Offset(4, 4))],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _bean(17),
            const SizedBox(width: 8),
            Text('COFFEE NETWORK', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: Pal.ink)),
          ]),
        ),
        const Spacer(),
        Text(state.busy ? '···' : (on ? 'вкл.' : 'выкл.'),
            style: TextStyle(fontSize: 88, height: 0.9, letterSpacing: -4, fontWeight: FontWeight.w900,
                color: on ? Pal.accent : Pal.ink)),
        const SizedBox(height: 10),
        Text('${(a?.name ?? 'НЕТ СЕРВЕРА').toUpperCase()}${on ? ' · ${state.sessionStr}' : ''}',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: Pal.inkDim)),
        const SizedBox(height: 20),
        _ConnectButton(state: state),
        const SizedBox(height: 20),
        check('ВЕСЬ ТРАФИК (TUN)', state.mode == 'tun', () { state.setState(() => state.mode = 'tun'); state._save(); }),
        check('ТОЛЬКО ПРОКСИ', state.mode == 'sys', () { state.setState(() => state.mode = 'sys'); state._save(); }),
        check('САЙТЫ РФ — НАПРЯМУЮ', state.bypassRu, () { state.setState(() => state.bypassRu = !state.bypassRu); state._save(); }),
        if (on)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 12),
                decoration: BoxDecoration(color: Pal.card, border: Border.all(color: Pal.edge, width: 2)),
                child: Text('↓ ${_HomeShellState.fmtSpeed(state.downSpeed)}',
                    style: TextStyle(fontFamily: _mono, fontSize: 12, fontWeight: FontWeight.w700, color: Pal.ink)),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 12),
                decoration: BoxDecoration(color: Pal.card, border: Border.all(color: Pal.edge, width: 2)),
                child: Text('↑ ${_HomeShellState.fmtSpeed(state.upSpeed)}',
                    style: TextStyle(fontFamily: _mono, fontSize: 12, fontWeight: FontWeight.w700, color: Pal.ink)),
              ),
            ]),
          ),
        const Spacer(),
        for (final s in top2)
          GestureDetector(
            onTap: () { state.setState(() => state.selectedId = s.id); state._save(); },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 6),
              decoration: BoxDecoration(
                color: state.selectedId == s.id ? markerBg : Colors.transparent,
                border: Border(
                  top: top2.indexOf(s) == 0 ? BorderSide(color: Pal.edge, width: 2) : BorderSide.none,
                  bottom: BorderSide(color: Pal.edge, width: 2),
                ),
              ),
              child: Row(children: [
                Text((top2.indexOf(s) + 1).toString().padLeft(2, '0'),
                    style: TextStyle(fontFamily: _mono, fontSize: 11, fontWeight: FontWeight.w800, color: Pal.ink)),
                const SizedBox(width: 12),
                Expanded(child: Text(s.name.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: Pal.ink))),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 7),
                  decoration: BoxDecoration(border: Border.all(color: Pal.edge, width: 2)),
                  child: Text(s.protocol.toUpperCase(),
                      style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: Pal.ink)),
                ),
              ]),
            ),
          ),
        const SizedBox(height: 14),
        Row(children: [
          GestureDetector(onTap: _toServers, child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 13),
            decoration: BoxDecoration(
              color: Pal.accent, border: Border.all(color: Pal.edge, width: 2),
              boxShadow: [BoxShadow(color: Pal.edge, offset: const Offset(3, 3))],
            ),
            child: Text('+ ДОБАВИТЬ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1, color: Pal.accentInk)),
          )),
          const SizedBox(width: 12),
          GestureDetector(onTap: _toServers, child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 13),
            decoration: BoxDecoration(
              color: Pal.card, border: Border.all(color: Pal.edge, width: 2),
              boxShadow: [BoxShadow(color: Pal.edge, offset: const Offset(3, 3))],
            ),
            child: Text('ВСЕ СЕРВЕРЫ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1, color: Pal.ink)),
          )),
        ]),
      ]),
    );
  }

  // ---------- ПУЛЬТ: bento-плитки ----------
  Widget _pult(BuildContext context) {
    final on = state.connected && !state.busy;
    final a = state.active;
    Widget tile({required String cap, required Widget child, EdgeInsets? pad}) => Container(
          width: double.infinity,
          padding: pad ?? const EdgeInsets.fromLTRB(15, 13, 15, 13),
          decoration: BoxDecoration(
            color: Pal.card, borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Pal.edge),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(cap, style: TextStyle(fontSize: 10, letterSpacing: 1.2, fontWeight: FontWeight.w600, color: Pal.inkFaint)),
            const SizedBox(height: 8),
            child,
          ]),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 12),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [_brandRow(), _gearBtn()]),
        ),
        tile(
          cap: 'СТАТУС',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 11, height: 11, decoration: BoxDecoration(shape: BoxShape.circle,
                  color: on ? const Color(0xFF3DDC97) : Pal.inkFaint)),
              const SizedBox(width: 9),
              Text(state.busy ? '···' : (on ? 'Защищено' : 'Отключено'),
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: Pal.ink)),
            ]),
            const SizedBox(height: 4),
            Text(a != null ? '${a.name} · ${(state._liveProtocol ?? a.protocol).toUpperCase()}' : 'сервер не выбран',
                style: TextStyle(fontSize: 12.5, color: Pal.inkFaint)),
            const SizedBox(height: 12),
            _ConnectButton(state: state),
          ]),
        ),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: tile(cap: 'СКОРОСТЬ', child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(on ? '↓ ${_HomeShellState.fmtSpeed(state.downSpeed)}' : '—',
                style: TextStyle(fontFamily: _mono, fontSize: 16, fontWeight: FontWeight.w700, color: Pal.ink)),
            const SizedBox(height: 2),
            Text(on ? '↑ ${_HomeShellState.fmtSpeed(state.upSpeed)}' : 'нет данных',
                style: TextStyle(fontFamily: _mono, fontSize: 11.5, color: Pal.inkFaint)),
          ]))),
          const SizedBox(width: 10),
          Expanded(child: tile(cap: 'СЕССИЯ', child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(on ? state.sessionStr.replaceAll(' ', '') : '—',
                style: TextStyle(fontFamily: _mono, fontSize: 16, fontWeight: FontWeight.w700, color: Pal.ink)),
            const SizedBox(height: 2),
            Text(on ? 'подключено' : 'не подключено', style: TextStyle(fontSize: 11.5, color: Pal.inkFaint)),
          ]))),
        ]),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: tile(cap: 'РЕЖИМ', child: _miniSeg())),
          const SizedBox(width: 10),
          Expanded(child: tile(cap: 'САЙТЫ РФ', pad: const EdgeInsets.fromLTRB(15, 13, 8, 5),
              child: Row(children: [
                Expanded(child: Text('Напрямую', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Pal.ink))),
                Switch(
                  value: state.bypassRu,
                  activeColor: Colors.white,
                  activeTrackColor: Pal.accent,
                  onChanged: (v) { state.setState(() => state.bypassRu = v); state._save(); },
                ),
              ]))),
        ]),
        const SizedBox(height: 10),
        Expanded(child: tile(
          cap: 'СЕРВЕРЫ · ${state.servers.length}',
          child: Column(children: [
            for (final s in state.servers.take(3))
              GestureDetector(
                onTap: () { state.setState(() => state.selectedId = s.id); state._save(); },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 10),
                  decoration: BoxDecoration(
                    color: state.selectedId == s.id ? Pal.bg : Colors.transparent,
                    borderRadius: BorderRadius.circular(11),
                    border: state.selectedId == s.id ? Border.all(color: Pal.accent, width: 1.5) : null,
                  ),
                  child: Row(children: [
                    Expanded(child: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Pal.ink))),
                    Text(s.protocol.toUpperCase(),
                        style: TextStyle(fontSize: 9.5, letterSpacing: 1, fontWeight: FontWeight.w700, color: Pal.inkFaint)),
                  ]),
                ),
              ),
            GestureDetector(
              onTap: _toServers,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 9),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: Pal.hair, width: 1.5),
                ),
                child: Text('+ добавить / все серверы', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Pal.accent)),
              ),
            ),
          ]),
        )),
      ]),
    );
  }

  // ---------- КЛАССИКА: посадочный талон (без изменений) ----------
  Widget _classic(BuildContext context) {
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
          _meta('NODE', state._liveNode ?? (a == null ? '—' : '${a.address}:${a.port}')),
          _meta('PROTOCOL', (state._liveProtocol?.toUpperCase()) ?? a?.protocol.toUpperCase() ?? '—'),
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

    switch (Pal.style) {
      case 'air':
        // круглая кнопка-кольцо по центру: белая ↔ «нагретая» акцентом
        return Center(
          child: GestureDetector(
            onTap: state.toggle,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 148, height: 148,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: on ? Pal.accent : Pal.card,
                border: Border.all(color: on ? Pal.accent : Pal.hair, width: 1.5),
                boxShadow: [BoxShadow(
                  color: on ? Pal.accent.withValues(alpha: 0.45) : Pal.glassShadow,
                  blurRadius: 40, offset: const Offset(0, 16),
                )],
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.power_settings_new, size: 42, color: on ? Pal.accentInk : Pal.inkFaint),
                const SizedBox(height: 6),
                Text(state.busy ? '···' : (on ? 'ОТКЛЮЧИТЬ' : 'ВКЛЮЧИТЬ'),
                    style: TextStyle(fontFamily: _mono, fontSize: 10, letterSpacing: 1.4,
                        color: on ? Pal.accentInk : Pal.inkFaint)),
              ]),
            ),
          ),
        );
      case 'mag':
        // текст с подчёркиванием — как ссылка в журнале
        return Align(
          alignment: Alignment.centerLeft,
          child: GestureDetector(
            onTap: state.toggle,
            child: Container(
              padding: const EdgeInsets.only(bottom: 8, right: 34),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(
                  color: state.connected ? Pal.hair : Pal.accent, width: 3))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(
                  state.busy ? 'секунду…' : (state.connected ? 'отключить' : 'подключить'),
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: Pal.ink),
                ),
                const SizedBox(width: 12),
                Icon(Icons.arrow_forward, size: 28, color: Pal.ink),
              ]),
            ),
          ),
        );
      case 'dawn':
        // пилюля по центру: тёмная налитая ↔ призрачная
        return Center(
          child: GestureDetector(
            onTap: state.toggle,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 44),
              decoration: BoxDecoration(
                color: on ? Colors.transparent : Pal.ink,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: on ? Pal.ink.withValues(alpha: 0.35) : Pal.ink, width: 1.5),
              ),
              child: Text(
                state.busy ? '···' : (on ? 'Отключить' : 'Подключиться'),
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: on ? Pal.ink : Pal.bg),
              ),
            ),
          ),
        );
      case 'poster':
        // брутальный блок: жёсткая рамка + офсетная тень
        return GestureDetector(
          onTap: state.toggle,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 22),
            decoration: BoxDecoration(
              color: on ? Pal.card : Pal.accent,
              border: Border.all(color: Pal.edge, width: 3),
              boxShadow: [BoxShadow(color: Pal.edge, offset: const Offset(5, 5))],
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(
                state.busy ? '···' : (state.connected ? 'ВЫКЛЮЧИТЬ' : 'ВКЛЮЧИТЬ'),
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, letterSpacing: 2,
                    color: on ? Pal.ink : Pal.accentInk),
              ),
              const SizedBox(width: 10),
              Icon(Icons.arrow_forward, size: 22, color: on ? Pal.ink : Pal.accentInk),
            ]),
          ),
        );
      case 'pult':
        // плоская плитка-кнопка, как в дэшборде
        return GestureDetector(
          onTap: state.toggle,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              color: on ? Pal.card : Pal.accent,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: on ? Pal.edge : Pal.accent),
            ),
            child: Center(child: Text(
              state.busy ? '···' : (state.connected ? 'Отключить' : 'Подключиться'),
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: on ? Pal.ink : Pal.accentInk),
            )),
          ),
        );
      default:
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
          Container(
            padding: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Pal.ink, width: 1.5))),
            child: Row(children: [
              Expanded(child: Text('СЕРВЕРЫ — ${state.servers.length.toString().padLeft(2, '0')}',
                  style: TextStyle(fontSize: 11, letterSpacing: 3, fontWeight: FontWeight.w600, color: Pal.inkFaint))),
              GestureDetector(
                onTap: () => _addSheet(context),
                child: Container(
                  padding: const EdgeInsets.only(bottom: 2),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Pal.accent, width: 1.5))),
                  child: Text('+ добавить', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Pal.accent)),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: state.servers.isEmpty
                ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('пока пусто.', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600, letterSpacing: -0.8, color: Pal.ink)),
                    const SizedBox(height: 8),
                    Text('нажми «+ добавить» и вставь ссылку', style: TextStyle(fontSize: 13, color: Pal.inkFaint)),
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
            Expanded(child: _ghost('LOG', () => _showLog(context))),
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
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 2),
        child: Row(children: [
          Container(
            width: 8, height: 8,
            margin: const EdgeInsets.only(right: 13),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: sel ? Pal.accent : Colors.transparent,
              border: sel ? null : Border.all(color: Pal.hair, width: 1.5),
            ),
          ),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.name.toLowerCase(), maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 17, letterSpacing: -0.2,
                    fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                    color: sel ? Pal.ink : Pal.inkDim)),
            const SizedBox(height: 3),
            Text('${s.address}:${s.port}', style: TextStyle(fontFamily: _mono, fontSize: 11, color: Pal.inkFaint)),
          ])),
          Text(s.protocol.toUpperCase(),
              style: TextStyle(fontSize: 10, letterSpacing: 1.4, color: Pal.inkFaint)),
          IconButton(
            icon: Icon(Icons.signal_cellular_alt, size: 18,
              color: (s.mobileRaw ?? '').isNotEmpty ? Pal.accent : Pal.inkFaint),
            tooltip: (s.mobileRaw ?? '').isNotEmpty ? '4G: задан' : '4G: задать',
            onPressed: () => _mobileSheet(context, s),
          ),
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

  void _mobileSheet(BuildContext context, Server s) {
    final ctrl = TextEditingController(text: s.mobileRaw ?? '');
    showModalBottomSheet(
      context: context,
      backgroundColor: Pal.dark ? const Color(0xFF1A1714) : const Color(0xFFFFFFFF),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(left: 18, right: 18, top: 18, bottom: 18 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          _label('МОБИЛЬНАЯ ССЫЛКА (4G/5G)'),
          const SizedBox(height: 6),
          Text('Используется на мобильном интернете вместо основной',
            style: TextStyle(fontSize: 12, color: Pal.inkFaint)),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            maxLines: 3,
            style: TextStyle(fontFamily: _mono, fontSize: 13, color: Pal.ink),
            decoration: InputDecoration(
              hintText: 'vless:// · hysteria2:// …',
              hintStyle: TextStyle(fontFamily: _mono, fontSize: 11, color: Pal.inkFaint),
              filled: true,
              fillColor: Pal.dark ? const Color(0x66000000) : const Color(0x0D000000),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Pal.hair)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Pal.hair)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Pal.accent)),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            if ((s.mobileRaw ?? '').isNotEmpty) ...[
              Expanded(child: _ghost('УДАЛИТЬ', () {
                final idx = state.servers.indexWhere((x) => x.id == s.id);
                if (idx >= 0) {
                  state.setState(() => state.servers[idx] = state.servers[idx].withMobile(null));
                  state._save();
                }
                Navigator.pop(ctx);
              })),
              const SizedBox(width: 8),
            ],
            Expanded(child: _solid('СОХРАНИТЬ', () {
              final trimmed = ctrl.text.trim();
              final idx = state.servers.indexWhere((x) => x.id == s.id);
              if (idx >= 0) {
                state.setState(() => state.servers[idx] = state.servers[idx].withMobile(trimmed.isEmpty ? null : trimmed));
                state._save();
              }
              Navigator.pop(ctx);
            })),
          ]),
          if ((s.mobileRaw ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            _ghost('СКОПИРОВАТЬ BUNDLE', () {
              final w = base64Url.encode(utf8.encode(s.raw));
              final m = base64Url.encode(utf8.encode(s.mobileRaw!));
              final bundle = 'coffee://bundle?w=$w&m=$m';
              Clipboard.setData(ClipboardData(text: bundle));
              state.snack('Bundle скопирован');
              Navigator.pop(ctx);
            }),
          ],
        ]),
      ),
    );
  }

  Future<void> _showLog(BuildContext context) async {
    String text;
    try {
      text = await _vpn.invokeMethod<String>('getLog') ?? '';
      if (text.isEmpty) text = '— лог пуст —';
    } catch (_) {
      text = '— не удалось получить лог —';
    }
    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Pal.dark ? const Color(0xFF1A1714) : Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setModalState) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.65,
          maxChildSize: 0.95,
          minChildSize: 0.3,
          builder: (_, ctrl) => Column(children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: Pal.inkDim.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 10, 12),
              child: Row(children: [
                Text('Лог ядра',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Pal.ink)),
                const Spacer(),
                _logBtn('КОПИРОВАТЬ', () {
                  Clipboard.setData(ClipboardData(text: text));
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                      content: Text('Скопировано'),
                      duration: Duration(seconds: 2)));
                }),
                const SizedBox(width: 8),
                _logBtn('ОЧИСТИТЬ', () async {
                  await _vpn.invokeMethod('clearLog');
                  setModalState(() => text = '— лог пуст —');
                }),
                const SizedBox(width: 8),
              ]),
            ),
            Expanded(
              child: Scrollbar(
                controller: ctrl,
                child: SingleChildScrollView(
                  controller: ctrl,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  child: SelectableText(
                    text,
                    style: TextStyle(
                        fontFamily: _mono,
                        fontSize: 11,
                        height: 1.5,
                        color: Pal.inkDim),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _logBtn(String label, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
          decoration: BoxDecoration(
              border: Border.all(color: Pal.hair),
              borderRadius: BorderRadius.circular(8)),
          child: Text(label,
              style: TextStyle(
                  fontFamily: _mono,
                  fontSize: 10,
                  letterSpacing: 1.0,
                  color: Pal.inkDim)),
        ),
      );

  void _settingsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Pal.paper,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 28 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          _label('НАСТРОЙКИ'),
          const SizedBox(height: 18),
          _ghost('ПРОВЕРИТЬ ОБНОВЛЕНИЯ', () {
            Navigator.pop(ctx);
            state.checkUpdate(manual: true);
          }),
          const SizedBox(height: 10),
          _ghost('ПОКАЗАТЬ ОБУЧЕНИЕ', () {
            Navigator.pop(ctx);
            state.setState(() => state.onboard = true);
          }),
          const SizedBox(height: 20),
          _label('ТЕМА'),
          const SizedBox(height: 12),
          Row(children: [
            for (final e in const [['светлая', 'light'], ['тёмная', 'dark'], ['системная', 'system']])
              Padding(
                padding: const EdgeInsets.only(right: 22),
                child: GestureDetector(
                  onTap: () {
                    _prefs!.setString('theme', e[1]);
                    Navigator.pop(ctx);
                    appRefresh?.call();
                  },
                  child: Container(
                    padding: const EdgeInsets.only(bottom: 4),
                    decoration: BoxDecoration(border: Border(bottom: BorderSide(
                        width: 2,
                        color: (_prefs!.getString('theme') ?? 'light') == e[1]
                            ? Pal.accent : Colors.transparent))),
                    child: Text(e[0], style: TextStyle(fontSize: 14,
                        fontWeight: (_prefs!.getString('theme') ?? 'light') == e[1]
                            ? FontWeight.w700 : FontWeight.w400,
                        color: (_prefs!.getString('theme') ?? 'light') == e[1]
                            ? Pal.ink : Pal.inkDim)),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 16),
          Text('coffeeNetwork v${state.appVer}', style: TextStyle(fontFamily: _mono, fontSize: 12, color: Pal.inkDim)),
        ]),
      ),
    );
  }

  /// Журнал: «кнопка-ссылка» — текст с тонкой линейкой снизу.
  Widget _ghost(String t, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
          alignment: Alignment.center,
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Pal.hair, width: 1.5))),
          child: Text(t.toLowerCase(), style: TextStyle(fontSize: 13.5, letterSpacing: 0.3, color: Pal.inkDim)),
        ),
      );

  /// Журнал: главное действие — плоская карамельная плашка.
  Widget _solid(String t, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 24),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: Pal.accent, borderRadius: BorderRadius.circular(4)),
          child: Text(t.toLowerCase(), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 0.3, color: Pal.accentInk)),
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
    if (widget.state.apps.isEmpty) {
      loading = true; // plain field write — calling setState() here throws ("during build")
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadApps());
    }
  }

  Future<void> _loadApps() async {
    if (mounted) setState(() => loading = true);
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

// ===================== ONBOARDING (first-launch visual tutorial) =====================
class _OnbStep {
  final String tag, title, body, why;
  final Widget visual;
  const _OnbStep({required this.tag, required this.title, required this.body, required this.why, required this.visual});
}

/// Full-screen tutorial shown once on first launch (flag `onboarded` in prefs).
/// A swipeable, on-brand walkthrough: each step pairs a mock UI cue ("где
/// кликать") with what to do and why. Re-openable from Настройки.
class _Onboarding extends StatefulWidget {
  final VoidCallback onDone;
  const _Onboarding({required this.onDone});
  @override
  State<_Onboarding> createState() => _OnboardingState();
}

class _OnboardingState extends State<_Onboarding> {
  final _pc = PageController();
  int _i = 0;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  void _next() {
    if (_i >= _steps.length - 1) {
      widget.onDone();
      return;
    }
    _pc.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
  }

  TextStyle _ts(double size, {Color? color, FontWeight w = FontWeight.w700, double ls = 1.4}) =>
      TextStyle(fontFamily: _mono, fontSize: size, fontWeight: w, letterSpacing: ls, color: color ?? Pal.ink);

  Widget _finger() => Padding(padding: const EdgeInsets.only(top: 12), child: Icon(Icons.touch_app, color: Pal.accent, size: 26));

  List<_OnbStep> get _steps => [
        _OnbStep(
          tag: 'COFFEE · NETWORK',
          title: 'Свобода в один тап',
          body: 'Быстрый VPN на ядре sing-box. Главный экран — твой «посадочный талон»: статус, режим и большая кнопка подключения.',
          why: 'Свайпай между талоном и списком серверов.',
          visual: Icon(Icons.flight, color: Pal.accent, size: 66),
        ),
        _OnbStep(
          tag: 'ШАГ 1 · СЕРВЕР',
          title: 'Добавь сервер',
          body: 'Свайпни влево на экран SERVERS и нажми «+ ДОБАВИТЬ». Вставь ссылку (vless://, hysteria2://, vmess://, ss://, trojan://, tuic://) от своего VPN-провайдера.',
          why: 'Без сервера подключаться не к чему.',
          visual: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
              decoration: BoxDecoration(
                color: Pal.accent.withOpacity(0.16),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: Pal.accent, width: 1.5),
              ),
              child: Text('+ ДОБАВИТЬ', style: _ts(14, color: Pal.accent)),
            ),
            _finger(),
          ]),
        ),
        _OnbStep(
          tag: 'ШАГ 2 · ПОДКЛЮЧЕНИЕ',
          title: 'Выбери и жми CONNECT',
          body: 'Коснись сервера в списке, чтобы выбрать его. Вернись на талон и нажми большую кнопку CONNECT.',
          why: 'Код ON и зелёная точка — значит ты под защитой.',
          visual: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 220,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
              decoration: BoxDecoration(color: Pal.accent, borderRadius: BorderRadius.circular(16)),
              child: Row(children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: Pal.accentInk)),
                const SizedBox(width: 12),
                Text('CONNECT', style: _ts(15, color: Pal.accentInk, ls: 2)),
                const Spacer(),
                Icon(Icons.arrow_forward, size: 18, color: Pal.accentInk),
              ]),
            ),
            _finger(),
          ]),
        ),
        _OnbStep(
          tag: 'РЕЖИМ ПОДКЛЮЧЕНИЯ',
          title: 'TUN · ALL или SYS PROXY',
          body: 'TUN · ALL — весь трафик устройства идёт через VPN (рекомендуется). SYS PROXY — только системный прокси.',
          why: 'TUN надёжнее: ни одно приложение не утечёт мимо туннеля.',
          visual: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: Pal.hair, borderRadius: BorderRadius.circular(14)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13), child: Text('SYS PROXY', style: _ts(13, color: Pal.inkFaint, w: FontWeight.w400))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                decoration: BoxDecoration(color: Pal.accent.withOpacity(0.18), borderRadius: BorderRadius.circular(11), border: Border.all(color: Pal.accent)),
                child: Text('TUN · ALL', style: _ts(13, color: Pal.accent)),
              ),
            ]),
          ),
        ),
        _OnbStep(
          tag: 'RU-BYPASS',
          title: 'Российское — мимо VPN',
          body: 'С включённым RU-BYPASS российские сайты и IP идут напрямую, в обход VPN.',
          why: 'Быстрее и без «обнаружен VPN» на РФ-сервисах. Выключи для полного туннеля.',
          visual: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(color: Pal.accent.withOpacity(0.10), borderRadius: BorderRadius.circular(14), border: Border.all(color: Pal.accent)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('RU-BYPASS', style: _ts(13, color: Pal.ink)),
              const SizedBox(width: 16),
              Container(
                width: 46, height: 27,
                padding: const EdgeInsets.all(3),
                alignment: Alignment.centerRight,
                decoration: BoxDecoration(color: Pal.accent, borderRadius: BorderRadius.circular(14)),
                child: Container(width: 21, height: 21, decoration: BoxDecoration(shape: BoxShape.circle, color: Pal.accentInk)),
              ),
            ]),
          ),
        ),
        _OnbStep(
          tag: 'ИГНОР · SPLIT-TUNNEL',
          title: 'Приложения мимо VPN',
          body: 'На экране SERVERS внизу нажми «ИГНОР» и отметь приложения, которые должны ходить напрямую, в обход VPN — например, банки, госуслуги или игры.',
          why: 'Отмеченные приложения видят твой реальный IP, весь остальной трафик идёт через VPN.',
          visual: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(border: Border.all(color: Pal.accent), borderRadius: BorderRadius.circular(12), color: Pal.accent.withOpacity(0.10)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 26, height: 26, decoration: BoxDecoration(color: Pal.hair, borderRadius: BorderRadius.circular(6))),
                const SizedBox(width: 10),
                Text('Банк', style: TextStyle(fontSize: 14, color: Pal.ink)),
                const SizedBox(width: 16),
                Container(
                  width: 22, height: 22,
                  decoration: BoxDecoration(color: Pal.accent, borderRadius: BorderRadius.circular(6)),
                  child: Icon(Icons.check, size: 15, color: Pal.accentInk),
                ),
              ]),
            ),
            const SizedBox(height: 10),
            Text('ИГНОР', style: _ts(11, color: Pal.inkFaint, ls: 2)),
          ]),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final last = _i == _steps.length - 1;
    return Material(
      color: Pal.dark ? const Color(0xF2171210) : const Color(0xF7F4F1EC),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 22),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text.rich(TextSpan(children: [
                TextSpan(text: 'COFFEE', style: _ts(12, ls: 3)),
                TextSpan(text: 'NETWORK', style: _ts(12, color: Pal.accent, ls: 3)),
              ])),
              GestureDetector(onTap: widget.onDone, child: Text('ПРОПУСТИТЬ', style: _ts(11, color: Pal.inkFaint, w: FontWeight.w400, ls: 1.5))),
            ]),
            Expanded(
              child: PageView.builder(
                controller: _pc,
                onPageChanged: (v) => setState(() => _i = v),
                itemCount: _steps.length,
                itemBuilder: (_, i) => _slide(_steps[i]),
              ),
            ),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var k = 0; k < _steps.length; k++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: k == _i ? 22 : 7,
                  height: 7,
                  decoration: BoxDecoration(color: k == _i ? Pal.accent : Pal.edge, borderRadius: BorderRadius.circular(4)),
                ),
            ]),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: _next,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 17),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: Pal.accent, borderRadius: BorderRadius.circular(16)),
                child: Text(last ? 'НАЧАТЬ ✦' : 'ДАЛЕЕ', style: _ts(15, color: Pal.accentInk, ls: 2)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _slide(_OnbStep s) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            height: 190,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Pal.card, borderRadius: BorderRadius.circular(22), border: Border.all(color: Pal.edge)),
            child: s.visual,
          ),
          const SizedBox(height: 26),
          Text(s.tag, style: _ts(10, color: Pal.accent, ls: 2.4)),
          const SizedBox(height: 10),
          Text(s.title, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Pal.ink, height: 1.1)),
          const SizedBox(height: 12),
          Text(s.body, style: TextStyle(fontSize: 14.5, height: 1.45, color: Pal.inkDim)),
          const SizedBox(height: 14),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline, size: 16, color: Pal.accent),
            const SizedBox(width: 8),
            Expanded(child: Text(s.why, style: TextStyle(fontSize: 13, height: 1.4, color: Pal.inkFaint))),
          ]),
          const SizedBox(height: 14),
        ]),
      );
}

// ===================== UPDATE DIALOG =====================
/// Update prompt → on «ОБНОВИТЬ» downloads the APK in-app (silent, with a
/// progress bar) via the native channel, then the system installer's
/// Update/Cancel modal appears. Updating over the same signature keeps all
/// servers/settings (they live in SharedPreferences).
class _UpdateDialog extends StatefulWidget {
  final String ver, notes, url, current;
  final VoidCallback onSkip;
  const _UpdateDialog({required this.ver, required this.notes, required this.url, required this.current, required this.onSkip});
  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _downloading = false;
  bool _needPermission = false;
  int _pct = 0;
  StreamSubscription? _sub;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() => _needPermission = false);
    String? res;
    try {
      res = await _vpn.invokeMethod<String>('installUpdate', {'url': widget.url});
    } catch (_) {
      res = 'error';
    }
    if (!mounted) return;
    if (res == 'permission') {
      setState(() => _needPermission = true);
    } else if (res == 'downloading') {
      setState(() => _downloading = true);
      _sub = _updateProgress.receiveBroadcastStream().listen(
        (e) { if (mounted) setState(() => _pct = (e as num).toInt()); },
        onError: (_) { if (mounted) setState(() => _downloading = false); },
      );
    } else {
      setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final head = widget.notes.trim().split('\n').take(10).join('\n').trim();
    return Dialog(
      backgroundColor: Pal.dark ? const Color(0xFF1A1714) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.system_update, color: Pal.accent, size: 22),
            const SizedBox(width: 10),
            Text('ОБНОВЛЕНИЕ', style: TextStyle(fontFamily: _mono, fontSize: 13, letterSpacing: 2, fontWeight: FontWeight.w700, color: Pal.ink)),
          ]),
          const SizedBox(height: 14),
          Text('Доступна версия ${widget.ver}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Pal.accent)),
          const SizedBox(height: 4),
          Text('у вас ${widget.current}', style: TextStyle(fontFamily: _mono, fontSize: 11, color: Pal.inkFaint)),
          if (_downloading) ...[
            const SizedBox(height: 18),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: _pct >= 100 ? null : _pct / 100,
                minHeight: 8,
                backgroundColor: Pal.hair,
                valueColor: AlwaysStoppedAnimation<Color>(Pal.accent),
              ),
            ),
            const SizedBox(height: 8),
            Text(_pct >= 100 ? 'Запуск установщика…' : 'Загрузка обновления… $_pct%',
                style: TextStyle(fontFamily: _mono, fontSize: 12, color: Pal.inkDim)),
          ] else if (_needPermission) ...[
            const SizedBox(height: 14),
            Text('Разрешите установку приложений из этого источника в открывшихся настройках, затем нажмите «ОБНОВИТЬ» снова.',
                style: TextStyle(fontSize: 13, height: 1.4, color: Pal.inkDim)),
          ] else if (head.isNotEmpty) ...[
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: SingleChildScrollView(child: Text(head, style: TextStyle(fontSize: 13, height: 1.45, color: Pal.inkDim))),
            ),
          ],
          const SizedBox(height: 18),
          if (!_downloading)
            Row(children: [
              GestureDetector(
                onTap: () { widget.onSkip(); Navigator.pop(context); },
                child: Text('ПРОПУСТИТЬ', style: TextStyle(fontFamily: _mono, fontSize: 12, color: Pal.inkFaint)),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), child: Text('ОТМЕНА', style: TextStyle(fontFamily: _mono, fontSize: 12, color: Pal.inkDim))),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: _start,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                  decoration: BoxDecoration(color: Pal.accent, borderRadius: BorderRadius.circular(11)),
                  child: Text('ОБНОВИТЬ', style: TextStyle(fontFamily: _mono, fontSize: 12, fontWeight: FontWeight.w700, color: Pal.accentInk)),
                ),
              ),
            ]),
        ]),
      ),
    );
  }
}
