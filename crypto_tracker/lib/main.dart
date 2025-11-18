import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ======================
/// ТЕМА / НАСТРОЙКИ
/// ======================

class ThemeController extends ChangeNotifier {
  static const _key = 'theme_mode';
  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_key);
    switch (s) {
      case 'light':
        _mode = ThemeMode.light;
        break;
      case 'dark':
        _mode = ThemeMode.dark;
        break;
      default:
        _mode = ThemeMode.system;
    }
  }

  Future<void> setMode(ThemeMode m) async {
    _mode = m;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, switch (m) { ThemeMode.light => 'light', ThemeMode.dark => 'dark', _ => 'system' });
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ru_RU', null);
  Intl.defaultLocale = 'ru_RU';

  final themeController = ThemeController();
  await themeController.load();

  runApp(CryptoApp(controller: themeController));
}

class CryptoApp extends StatelessWidget {
  final ThemeController controller;
  const CryptoApp({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) => MaterialApp(
        title: 'Крипто‑трекер',
        themeMode: controller.mode,
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: Colors.blue,
          brightness: Brightness.light,
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: Colors.blue,
          brightness: Brightness.dark,
        ),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('ru', 'RU'), Locale('en', 'US')],
        home: CryptoListPage(controller: controller),
      ),
    );
  }
}

/// ======================
/// МОДЕЛИ
/// ======================

class CoinTicker {
  final String id;
  final String name;
  final String symbol; // e.g., BTC
  final int rank;
  final double priceUsd;
  final double percentChange24h;
  final double marketCapUsd;
  final double volume24hUsd;

  String get logoUrl => 'https://static.coinpaprika.com/coin/$id/logo.png';

  CoinTicker({
    required this.id,
    required this.name,
    required this.symbol,
    required this.rank,
    required this.priceUsd,
    required this.percentChange24h,
    required this.marketCapUsd,
    required this.volume24hUsd,
  });

  factory CoinTicker.fromJson(Map<String, dynamic> json) {
    final quotes = json['quotes']?['USD'] ?? {};
    return CoinTicker(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      symbol: (json['symbol'] as String? ?? '').toUpperCase(),
      rank: (json['rank'] as num?)?.toInt() ?? 0,
      priceUsd: (quotes['price'] as num?)?.toDouble() ?? 0.0,
      percentChange24h: (quotes['percent_change_24h'] as num?)?.toDouble() ?? 0.0,
      marketCapUsd: (quotes['market_cap'] as num?)?.toDouble() ?? 0.0,
      volume24hUsd: (quotes['volume_24h'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class HistoricalPoint {
  final DateTime time;
  final double price;
  HistoricalPoint(this.time, this.price);
}

enum ChartRange { d1, d7, d30, y1 }

/// ======================
/// API / СЕРВИСЫ
/// ======================

class CoinPaprikaApi {
  static const _base = 'https://api.coinpaprika.com/v1';
  final http.Client _client = http.Client();

  Future<List<CoinTicker>> fetchTopTickers({int limit = 100}) async {
    final uri = Uri.parse('$_base/tickers?quotes=USD');
    final res = await _client.get(uri, headers: {'Accept': 'application/json'});
    if (res.statusCode != 200) {
      throw Exception('CoinPaprika tickers failed: ${res.statusCode}');
    }
    final list = (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
    final items = list.map(CoinTicker.fromJson).where((e) => e.rank > 0).toList()
      ..sort((a, b) => a.rank.compareTo(b.rank));
    return items.take(limit).toList();
  }

  /// История цены (основной путь). Может вернуть 402 на бесплатном плане.
  Future<List<HistoricalPoint>> fetchHistory(String coinId, ChartRange range) async {
    final now = DateTime.now().toUtc();
    late DateTime start;
    late String interval;

    switch (range) {
      case ChartRange.d1:
        start = now.subtract(const Duration(days: 1));
        interval = '1h'; // часто платный — для d1 будет фолбэк
        break;
      case ChartRange.d7:
        start = now.subtract(const Duration(days: 7));
        interval = '1d';
        break;
      case ChartRange.d30:
        start = now.subtract(const Duration(days: 30));
        interval = '1d';
        break;
      case ChartRange.y1:
        start = now.subtract(const Duration(days: 365));
        interval = '1d'; // может быть 402 — фолбэк на Binance
        break;
    }

    final startStr = DateFormat('yyyy-MM-dd').format(start);
    final endStr = DateFormat('yyyy-MM-dd').format(now);
    final uri = Uri.parse(
      '$_base/tickers/$coinId/historical?start=$startStr&end=$endStr&interval=$interval&quote=usd',
    );

    final res = await _client.get(uri, headers: {'Accept': 'application/json'});
    if (res.statusCode != 200) {
      throw Exception('CoinPaprika history failed ${res.statusCode}');
    }

    final list = (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
    return list.map((m) {
      final ts = DateTime.parse(m['timestamp'] as String).toLocal();
      final price = (m['price'] as num?)?.toDouble() ?? 0.0;
      return HistoricalPoint(ts, price);
    }).toList();
  }

  /// Дневные OHLC — надёжный бесплатный эндпоинт для фолбэка.
  Future<List<HistoricalPoint>> fetchDailyOhlc(String coinId, DateTime start, DateTime end) async {
    final s = DateFormat('yyyy-MM-dd').format(start);
    final e = DateFormat('yyyy-MM-dd').format(end);
    final uri = Uri.parse('$_base/coins/$coinId/ohlcv/historical?start=$s&end=$e');
    final res = await _client.get(uri, headers: {'Accept': 'application/json'});
    if (res.statusCode != 200) {
      throw Exception('CoinPaprika ohlcv failed ${res.statusCode}');
    }
    final list = (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
    return list.map((m) {
      // берём закрытие дня
      final ts = DateTime.parse((m['time_close'] ?? m['time_open']) as String).toLocal();
      final close = (m['close'] as num?)?.toDouble() ?? 0.0;
      return HistoricalPoint(ts, close);
    }).toList()
      ..sort((a, b) => a.time.compareTo(b.time));
  }
}

class BinanceWsService {
  WebSocketChannel? _channel;
  Stream<double>? _priceStream;

  Stream<double>? openTradePriceStream(String symbolUpper) {
    close();
    // Простейшее сопоставление к USDT
    final sym = symbolUpper.toLowerCase();
    if (sym == 'usdt') return null; // пары USDTUSDT нет
    final pair = '${sym}usdt';
    final url = Uri.parse('wss://stream.binance.com:9443/ws/${pair}@trade');

    try {
      _channel = WebSocketChannel.connect(url);
      _priceStream = _channel!.stream.map<double?>((event) {
        try {
          final map = jsonDecode(event as String) as Map<String, dynamic>;
          final p = (map['p'] as String?) ?? (map['c'] as String?);
          return p != null ? double.tryParse(p) : null;
        } catch (_) {
          return null;
        }
      }).where((v) => v != null).cast<double>();
      return _priceStream;
    } catch (_) {
      close();
      return null;
    }
  }

  void close() {
    _channel?.sink.close();
    _channel = null;
    _priceStream = null;
  }
}

/// Binance REST — фолбэк для графиков (1D/1Y).
class BinanceRestService {
  static const _base = 'https://api.binance.com';
  final http.Client _client = http.Client();

  /// interval: '1h', '1d'; limit: 24 или 365
  Future<List<HistoricalPoint>?> fetchKlines(String symbolUpper, String interval, int limit) async {
    final sym = symbolUpper.toUpperCase();
    if (sym == 'USDT') return null; // бессмысленно
    final symbol = '${sym}USDT';
    final uri = Uri.parse('$_base/api/v3/klines?symbol=$symbol&interval=$interval&limit=$limit');
    try {
      final res = await _client.get(uri, headers: {'Accept': 'application/json'});
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as List;
      return data.map<HistoricalPoint>((e) {
        final arr = e as List;
        final openTimeMs = (arr[0] as num).toInt();
        final closeStr = arr[4] as String; // close price
        return HistoricalPoint(
          DateTime.fromMillisecondsSinceEpoch(openTimeMs).toLocal(),
          double.parse(closeStr),
        );
      }).toList();
    } catch (_) {
      return null;
    }
  }
}

/// Единая точка получения истории с фолбэками.
class HistoryRepository {
  final CoinPaprikaApi paprika;
  final BinanceRestService binance;

  HistoryRepository({CoinPaprikaApi? paprika, BinanceRestService? binance})
      : paprika = paprika ?? CoinPaprikaApi(),
        binance = binance ?? BinanceRestService();

  Future<List<HistoricalPoint>> get(String coinId, String symbol, ChartRange range) async {
    try {
      // Сначала пробуем CoinPaprika (может вернуть 402)
      return await paprika.fetchHistory(coinId, range);
    } catch (_) {
      // Фолбэки
      if (range == ChartRange.d1) {
        final b = await binance.fetchKlines(symbol, '1h', 24);
        if (b != null && b.isNotEmpty) return b;
      }
      if (range == ChartRange.y1) {
        final b = await binance.fetchKlines(symbol, '1d', 365);
        if (b != null && b.isNotEmpty) return b;
      }
      // Последняя попытка — дневные OHLC из Paprika
      final now = DateTime.now().toUtc();
      late DateTime start;
      switch (range) {
        case ChartRange.d1:
          start = now.subtract(const Duration(days: 2));
          break;
        case ChartRange.d7:
          start = now.subtract(const Duration(days: 7));
          break;
        case ChartRange.d30:
          start = now.subtract(const Duration(days: 30));
          break;
        case ChartRange.y1:
          start = now.subtract(const Duration(days: 365));
          break;
      }
      final ohlc = await paprika.fetchDailyOhlc(coinId, start, now);
      if (ohlc.isNotEmpty) return ohlc;
      rethrow;
    }
  }
}

/// ======================
/// UI — Список монет
/// ======================

class CryptoListPage extends StatefulWidget {
  final ThemeController controller;
  const CryptoListPage({super.key, required this.controller});

  @override
  State<CryptoListPage> createState() => _CryptoListPageState();
}

class _CryptoListPageState extends State<CryptoListPage> {
  final api = CoinPaprikaApi();
  final _fmtCurrency = NumberFormat.currency(locale: 'ru_RU', symbol: '\$');
  final _fmtPerc = NumberFormat.decimalPattern('ru_RU');
  List<CoinTicker> _all = [];
  List<CoinTicker> _filtered = [];
  bool _loading = true;
  String _query = '';
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    try {
      if (!silent) setState(() => _loading = true);
      final data = await api.fetchTopTickers(limit: 100);
      setState(() {
        _all = data;
        _applyFilter();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка загрузки: $e')),
      );
    }
  }

  void _applyFilter() {
    final q = _query.trim().toLowerCase();
    _filtered = q.isEmpty
        ? _all
        : _all.where((c) => c.name.toLowerCase().contains(q) || c.symbol.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Крипто‑трекер'),
        actions: [
          IconButton(
            tooltip: 'Настройки',
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => SettingsPage(controller: widget.controller),
              ));
            },
          ),
          IconButton(
            onPressed: () => _load(),
            icon: const Icon(Icons.refresh),
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Поиск по имени или символу…',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onChanged: (v) => setState(() {
                _query = v;
                _applyFilter();
              }),
            ),
          ),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: ListView.separated(
                  itemCount: _filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final c = _filtered[i];
                    final change = c.percentChange24h;
                    final changeColor = change >= 0 ? Colors.green : Colors.red;
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage: NetworkImage(c.logoUrl),
                        onBackgroundImageError: (_, __) {},
                        child: Text(c.symbol.isNotEmpty ? c.symbol[0] : '?'),
                      ),
                      title: Text('${c.rank}. ${c.name} (${c.symbol})',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        'MC: ${_fmtCurrency.format(c.marketCapUsd)} • Vol 24ч: ${_fmtCurrency.format(c.volume24hUsd)}',
                      ),
                      trailing: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(_fmtCurrency.format(c.priceUsd),
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(
                            '${change >= 0 ? '+' : ''}${_fmtPerc.format(change)}%',
                            style: TextStyle(color: changeColor, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      onTap: () {
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => CoinDetailPage(ticker: c),
                        ));
                      },
                    );
                  },
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text(
              'Источник: CoinPaprika (REST). График 1D/1Y — с фолбэком на Binance.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          )
        ],
      ),
    );
  }
}

/// ======================
/// UI — Настройки
/// ======================

class SettingsPage extends StatelessWidget {
  final ThemeController controller;
  const SettingsPage({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final current = controller.mode;
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Тема', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
          RadioListTile<ThemeMode>(
            title: const Text('Системная'),
            value: ThemeMode.system,
            groupValue: current,
            onChanged: (m) => controller.setMode(m!),
          ),
          RadioListTile<ThemeMode>(
            title: const Text('Светлая'),
            value: ThemeMode.light,
            groupValue: current,
            onChanged: (m) => controller.setMode(m!),
          ),
          RadioListTile<ThemeMode>(
            title: const Text('Тёмная'),
            value: ThemeMode.dark,
            groupValue: current,
            onChanged: (m) => controller.setMode(m!),
          ),
          const SizedBox(height: 24),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Выбор темы сохраняется и применяется ко всему приложению.',
              style: TextStyle(color: Colors.grey),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

/// ======================
/// UI — Детальная страница монеты
/// ======================

class CoinDetailPage extends StatefulWidget {
  final CoinTicker ticker;
  const CoinDetailPage({super.key, required this.ticker});

  @override
  State<CoinDetailPage> createState() => _CoinDetailPageState();
}

class _CoinDetailPageState extends State<CoinDetailPage> {
  final history = HistoryRepository();
  final ws = BinanceWsService();

  ChartRange _range = ChartRange.d7;
  List<HistoricalPoint> _points = [];
  bool _loading = true;
  StreamSubscription<double>? _liveSub;
  double? _livePrice;

  final _fmtCurrency = NumberFormat.currency(locale: 'ru_RU', symbol: '\$');
  final _fmtTimeH = DateFormat.Hm('ru_RU');
  final _fmtDate = DateFormat('dd.MM.yyyy', 'ru_RU');

  @override
  void initState() {
    super.initState();
    _loadChart();
    _tryOpenWs();
  }

  @override
  void dispose() {
    _liveSub?.cancel();
    ws.close();
    super.dispose();
  }

  Future<void> _loadChart() async {
    setState(() => _loading = true);
    try {
      final list = await history.get(widget.ticker.id, widget.ticker.symbol, _range);
      setState(() {
        _points = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось получить график: $e')),
      );
    }
  }

  void _tryOpenWs() {
    final stream = ws.openTradePriceStream(widget.ticker.symbol);
    if (stream != null) {
      _liveSub = stream.listen((p) {
        setState(() => _livePrice = p);
      }, onError: (_) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentPrice = _livePrice ?? widget.ticker.priceUsd;
    final ch24 = widget.ticker.percentChange24h;
    final changeColor = ch24 >= 0 ? Colors.green : Colors.red;

    return Scaffold(
      appBar: AppBar(title: Text('${widget.ticker.name} (${widget.ticker.symbol})')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Шапка
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                CircleAvatar(backgroundImage: NetworkImage(widget.ticker.logoUrl), radius: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_fmtCurrency.format(currentPrice),
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(ch24 >= 0 ? Icons.trending_up : Icons.trending_down, size: 16, color: changeColor),
                          const SizedBox(width: 6),
                          Text(
                            '${ch24 >= 0 ? '+' : ''}${NumberFormat.decimalPattern('ru_RU').format(ch24)}% за 24ч',
                            style: TextStyle(color: changeColor, fontWeight: FontWeight.w600),
                          ),
                          const Spacer(),
                          if (_livePrice != null)
                            const Chip(
                              labelPadding: EdgeInsets.symmetric(horizontal: 6),
                              visualDensity: VisualDensity.compact,
                              label: Text('Live: Binance'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Диапазоны
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              children: [
                _rangeChip('1D', ChartRange.d1),
                _rangeChip('7D', ChartRange.d7),
                _rangeChip('30D', ChartRange.d30),
                _rangeChip('1Y', ChartRange.y1),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // График
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _points.isEmpty
                ? const Center(child: Text('Нет данных для выбранного диапазона'))
                : Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 16, 16),
              child: _buildLineChart(),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              'График: CoinPaprika (c фолбэком на Binance для 1D/1Y). Лайв‑тикер: Binance WebSocket.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _rangeChip(String label, ChartRange value) {
    final selected = _range == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        setState(() => _range = value);
        _loadChart();
      },
    );
  }

  Widget _buildLineChart() {
    final spots = <FlSpot>[];
    double minY = double.infinity;
    double maxY = -double.infinity;

    for (var i = 0; i < _points.length; i++) {
      final p = _points[i];
      final x = p.time.millisecondsSinceEpoch.toDouble();
      final y = p.price;
      if (y.isFinite) {
        spots.add(FlSpot(x, y));
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }

    if (spots.isEmpty) return const Center(child: Text('Нет данных'));

    final yPadding = (maxY - minY) * 0.05;
    minY = (minY - yPadding).clamp(0, double.infinity);
    maxY = maxY + yPadding;

    final minX = spots.first.x;
    final maxX = spots.last.x;
    final intervalX = (maxX - minX) / 4.0;

    String formatX(double xVal) {
      final dt = DateTime.fromMillisecondsSinceEpoch(xVal.toInt()).toLocal();
      return _range == ChartRange.d1 ? _fmtTimeH.format(dt) : _fmtDate.format(dt);
    }

    return LineChart(
      LineChartData(
        minY: minY,
        maxY: maxY,
        minX: minX,
        maxX: maxX,
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touchedSpots) => touchedSpots.map((ts) {
              final dt = DateTime.fromMillisecondsSinceEpoch(ts.x.toInt()).toLocal();
              final timeLabel = _range == ChartRange.d1 ? _fmtTimeH.format(dt) : _fmtDate.format(dt);
              return LineTooltipItem('${_fmtCurrency.format(ts.y)}\n$timeLabel',
                  const TextStyle(fontWeight: FontWeight.w700));
            }).toList(),
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 44)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: intervalX,
              getTitlesWidget: (value, meta) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(formatX(value), style: const TextStyle(fontSize: 11)),
              ),
            ),
          ),
        ),
        gridData: const FlGridData(show: true),
        borderData: FlBorderData(show: true),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            barWidth: 2.4,
            dotData: const FlDotData(show: false),
          ),
        ],
      ),
    );
  }
}
