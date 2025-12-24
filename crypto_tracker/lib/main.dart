// lib/main.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// ======================
/// ТЕМА / НАСТРОЙКИ
/// ======================

enum AccentPalette { purple, teal, gray, bitcoin, tether }

/// Пользовательские настройки дизайна (+ параметры бегущей строки)
@immutable
class DesignPrefs extends ThemeExtension<DesignPrefs> {
  final double radius;
  final bool compact;
  final bool amoledBlack; // только для dark
  final bool highContrast; // усиливает контраст текста
  final bool curvedCharts; // кривая линия
  final bool showChartArea; // заливка под графиком
  final bool autoChartColor; // зел/красн от направления
  final bool showLastDot; // точка на последнем значении

  // Новые параметры кастомизации
  final double tickerSpeed; // 0.5..2.0 (x)
  final bool tickerCompact; // компактные плашки тикера

  const DesignPrefs({
    required this.radius,
    required this.compact,
    required this.amoledBlack,
    required this.highContrast,
    required this.curvedCharts,
    required this.showChartArea,
    required this.autoChartColor,
    required this.showLastDot,
    required this.tickerSpeed,
    required this.tickerCompact,
  });

  DesignPrefs copyWith({
    double? radius,
    bool? compact,
    bool? amoledBlack,
    bool? highContrast,
    bool? curvedCharts,
    bool? showChartArea,
    bool? autoChartColor,
    bool? showLastDot,
    double? tickerSpeed,
    bool? tickerCompact,
  }) =>
      DesignPrefs(
        radius: radius ?? this.radius,
        compact: compact ?? this.compact,
        amoledBlack: amoledBlack ?? this.amoledBlack,
        highContrast: highContrast ?? this.highContrast,
        curvedCharts: curvedCharts ?? this.curvedCharts,
        showChartArea: showChartArea ?? this.showChartArea,
        autoChartColor: autoChartColor ?? this.autoChartColor,
        showLastDot: showLastDot ?? this.showLastDot,
        tickerSpeed: tickerSpeed ?? this.tickerSpeed,
        tickerCompact: tickerCompact ?? this.tickerCompact,
      );

  @override
  ThemeExtension<DesignPrefs> lerp(ThemeExtension<DesignPrefs>? other, double t) {
    if (other is! DesignPrefs) return this;
    return DesignPrefs(
      radius: _lerpDouble(radius, other.radius, t),
      compact: t < .5 ? compact : other.compact,
      amoledBlack: t < .5 ? amoledBlack : other.amoledBlack,
      highContrast: t < .5 ? highContrast : other.highContrast,
      curvedCharts: t < .5 ? curvedCharts : other.curvedCharts,
      showChartArea: t < .5 ? showChartArea : other.showChartArea,
      autoChartColor: t < .5 ? autoChartColor : other.autoChartColor,
      showLastDot: t < .5 ? showLastDot : other.showLastDot,
      tickerSpeed: _lerpDouble(tickerSpeed, other.tickerSpeed, t),
      tickerCompact: t < .5 ? tickerCompact : other.tickerCompact,
    );
  }

  static double _lerpDouble(double a, double b, double t) => a + (b - a) * t;

  static DesignPrefs of(BuildContext context) =>
      Theme.of(context).extension<DesignPrefs>()!;
}

class ThemeController extends ChangeNotifier {
  // Keys
  static const _modeKey = 'theme_mode';
  static const _accentKey = 'theme_accent';
  static const _radiusKey = 'ui_radius';
  static const _compactKey = 'ui_compact';
  static const _amoledKey = 'ui_amoled';
  static const _contrastKey = 'ui_contrast';
  static const _curvedKey = 'chart_curved';
  static const _areaKey = 'chart_area';
  static const _autoColorKey = 'chart_autoColor';
  static const _lastDotKey = 'chart_lastDot';
  static const _tickerSpeedKey = 'ticker_speed';
  static const _tickerCompactKey = 'ticker_compact';

  // State
  ThemeMode _mode = ThemeMode.system;
  AccentPalette _accent = AccentPalette.gray;

  // Строгий дефолт: меньше скругления, более “деловой” вид
  double _radius = 14.0;
  bool _compact = false;
  bool _amoled = false;
  bool _highContrast = false;

  bool _curvedCharts = true;
  bool _showArea = true;
  bool _autoChartColor = true;
  bool _showLastDot = true;

  double _tickerSpeed = 1.0; // x
  bool _tickerCompact = false;

  ThemeMode get mode => _mode;
  AccentPalette get accent => _accent;

  DesignPrefs get design => DesignPrefs(
    radius: _radius,
    compact: _compact,
    amoledBlack: _amoled,
    highContrast: _highContrast,
    curvedCharts: _curvedCharts,
    showChartArea: _showArea,
    autoChartColor: _autoChartColor,
    showLastDot: _showLastDot,
    tickerSpeed: _tickerSpeed,
    tickerCompact: _tickerCompact,
  );

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();

      switch (p.getString(_modeKey)) {
        case 'light':
          _mode = ThemeMode.light;
          break;
        case 'dark':
          _mode = ThemeMode.dark;
          break;
        default:
          _mode = ThemeMode.system;
      }

      switch (p.getString(_accentKey)) {
        case 'teal':
          _accent = AccentPalette.teal;
          break;
        case 'gray':
          _accent = AccentPalette.gray;
          break;
        case 'orange':
          _accent = AccentPalette.bitcoin;
          break;
        case 'tether':
          _accent = AccentPalette.tether;
          break;
        default:
          _accent = AccentPalette.purple;
      }

      _radius = (p.getInt(_radiusKey) ?? 14).toDouble().clamp(8.0, 40.0);
      _compact = p.getBool(_compactKey) ?? false;
      _amoled = p.getBool(_amoledKey) ?? false;
      _highContrast = p.getBool(_contrastKey) ?? false;

      _curvedCharts = p.getBool(_curvedKey) ?? true;
      _showArea = p.getBool(_areaKey) ?? true;
      _autoChartColor = p.getBool(_autoColorKey) ?? true;
      _showLastDot = p.getBool(_lastDotKey) ?? true;

      _tickerSpeed = (p.getDouble(_tickerSpeedKey) ?? 1.0).clamp(0.5, 2.0);
      _tickerCompact = p.getBool(_tickerCompactKey) ?? false;
    } catch (_) {
      // defaults remain
    }
    notifyListeners();
  }

  Future<void> setMode(ThemeMode m) async {
    _mode = m;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _modeKey,
      switch (m) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        _ => 'system',
      },
    );
  }

  Future<void> setAccent(AccentPalette a) async {
    _accent = a;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _accentKey,
      switch (a) {
        AccentPalette.teal => 'teal',
        AccentPalette.gray => 'gray',
        AccentPalette.bitcoin => 'orange',
        AccentPalette.tether => 'tether',
        _ => 'purple',
      },
    );
  }

  Future<void> setRadius(double r) async {
    _radius = r.clamp(8.0, 40.0);
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setInt(_radiusKey, _radius.round());
  }

  Future<void> setCompact(bool v) async {
    _compact = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool(_compactKey, v);
  }

  Future<void> setAmoled(bool v) async {
    _amoled = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool(_amoledKey, v);
  }

  Future<void> setHighContrast(bool v) async {
    _highContrast = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool(_contrastKey, v);
  }

  Future<void> setCurvedCharts(bool v) async {
    _curvedCharts = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool(_curvedKey, v);
  }

  Future<void> setShowArea(bool v) async {
    _showArea = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool(_areaKey, v);
  }

  Future<void> setAutoChartColor(bool v) async {
    _autoChartColor = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool(_autoColorKey, v);
  }

  Future<void> setShowLastDot(bool v) async {
    _showLastDot = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool(_lastDotKey, v);
  }

  Future<void> setTickerSpeed(double x) async {
    _tickerSpeed = x.clamp(0.5, 2.0);
    notifyListeners();
    (await SharedPreferences.getInstance()).setDouble(_tickerSpeedKey, _tickerSpeed);
  }

  Future<void> setTickerCompact(bool v) async {
    _tickerCompact = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool(_tickerCompactKey, v);
  }
}

/// Конструктор темы (строгий/минималистичный стиль)
ThemeData buildFluidTheme(Brightness brightness, AccentPalette accent, DesignPrefs prefs) {
  final isDark = brightness == Brightness.dark;

  // seed для ColorScheme
  final seed = switch (accent) {
    AccentPalette.purple => const Color(0xFF4F46E5), // indigo
    AccentPalette.teal => const Color(0xFF0F766E), // deep teal
    AccentPalette.gray => const Color(0xFF334155), // slate
    AccentPalette.bitcoin => const Color(0xFFB45309), // amber/dark orange
    AccentPalette.tether => const Color(0xFF047857), // emerald dark
  };

  var scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);

  // Базовые поверхности: нейтральнее и “корпоративнее”
  late final Color background;
  late final Color surface;
  late final Color surfaceVariant;
  late final Color outlineVariant;
  late final Color onSurface;
  late final Color onSurfaceVariant;

  if (isDark) {
    final baseBg = const Color(0xFF0B0E12);
    background = prefs.amoledBlack ? const Color(0xFF000000) : baseBg;
    surface = prefs.amoledBlack ? const Color(0xFF0A0A0A) : const Color(0xFF10141B);
    surfaceVariant = const Color(0xFF171D26);
    outlineVariant = const Color(0xFF2A3340);
    onSurface = prefs.highContrast ? Colors.white : const Color(0xFFE6E8EC);
    onSurfaceVariant = prefs.highContrast ? const Color(0xFFCED4DC) : const Color(0xFFB7C0CC);
  } else {
    background = const Color(0xFFF6F7F9);
    surface = const Color(0xFFFFFFFF);
    surfaceVariant = const Color(0xFFF0F2F5);
    outlineVariant = const Color(0xFFD0D5DD);
    onSurface = const Color(0xFF101828);
    onSurfaceVariant = const Color(0xFF475467);
  }

  scheme = scheme.copyWith(
    background: background,
    surface: surface,
    surfaceVariant: surfaceVariant,
    outlineVariant: outlineVariant,
    onSurface: onSurface,
    onSurfaceVariant: onSurfaceVariant,
  );

  final radius = prefs.radius.clamp(8.0, 40.0);
  final fieldRadius = (radius - 4).clamp(8.0, 28.0);

  final textTheme = GoogleFonts.interTextTheme(
    ThemeData(brightness: brightness).textTheme,
  ).apply(bodyColor: onSurface, displayColor: onSurface);

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    textTheme: textTheme,
    visualDensity: prefs.compact ? VisualDensity.compact : VisualDensity.standard,
    scaffoldBackgroundColor: background,

    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 1,
      backgroundColor: surface,
      foregroundColor: onSurface,
      centerTitle: false,
      titleTextStyle: GoogleFonts.inter(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.1,
        color: onSurface,
      ),
      iconTheme: IconThemeData(color: onSurface),
      actionsIconTheme: IconThemeData(color: onSurface),
      systemOverlayStyle: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
    ),

    dividerTheme: DividerThemeData(
      color: outlineVariant.withOpacity(isDark ? 0.65 : 0.9),
      thickness: 1,
      space: 1,
    ),

    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: outlineVariant),
      ),
    ),

    listTileTheme: ListTileThemeData(
      dense: prefs.compact,
      iconColor: scheme.primary,
      textColor: onSurface,
      titleTextStyle: TextStyle(fontWeight: FontWeight.w600, color: onSurface),
      subtitleTextStyle: TextStyle(color: onSurfaceVariant),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surfaceVariant,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(fieldRadius),
        borderSide: BorderSide(color: outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(fieldRadius),
        borderSide: BorderSide(color: outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(fieldRadius),
        borderSide: BorderSide(color: scheme.primary, width: 1.4),
      ),
      hintStyle: TextStyle(color: onSurfaceVariant.withOpacity(0.8)),
      prefixIconColor: onSurfaceVariant,
      suffixIconColor: onSurfaceVariant,
      labelStyle: TextStyle(color: onSurfaceVariant),
    ),

    chipTheme: ChipThemeData(
      backgroundColor: surfaceVariant,
      selectedColor: scheme.primary.withOpacity(0.12),
      side: BorderSide(color: outlineVariant),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      labelStyle: TextStyle(color: onSurface, fontWeight: FontWeight.w600),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    ),

    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        shape: MaterialStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        padding: MaterialStateProperty.all(const EdgeInsets.all(10)),
      ),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: BorderSide(color: outlineVariant),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),

    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: isDark ? const Color(0xFF1B222C) : const Color(0xFF101828),
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),

    floatingActionButtonTheme: FloatingActionButtonThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );

  // Добавляем расширения
  return base.copyWith(
    extensions: <ThemeExtension<dynamic>>[
      prefs,
    ],
  );
}

/// Универсальный AppBar (строгий, без градиентов/волн)
PreferredSizeWidget fluidAppBar(
    BuildContext context, {
      String? title,
      Widget? titleWidget,
      List<Widget>? actions,
      Widget? leading,
      bool centerTitle = false,
      double titleSpacing = 16,
    }) {
  final theme = Theme.of(context);
  final cs = theme.colorScheme;

  final text = titleWidget ??
      (title != null
          ? Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      )
          : const SizedBox.shrink());

  final isDark = theme.brightness == Brightness.dark;
  final overlay = isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark;

  return AppBar(
    title: text,
    titleSpacing: titleSpacing,
    centerTitle: centerTitle,
    actions: actions,
    leading: leading,
    elevation: 0,
    scrolledUnderElevation: 1,
    backgroundColor: cs.surface,
    foregroundColor: cs.onSurface,
    surfaceTintColor: Colors.transparent,
    systemOverlayStyle: overlay,
  );
}

/// Строгая “шапка” страницы (замена волнистой)
class StrictHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final EdgeInsetsGeometry margin;

  const StrictHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.margin = const EdgeInsets.fromLTRB(16, 12, 16, 0),
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final prefs = DesignPrefs.of(context);

    return Container(
      margin: margin,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(prefs.radius),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 10),
            trailing!,
          ],
        ],
      ),
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ru_RU', null);
  Intl.defaultLocale = 'ru_RU';

  final themeController = ThemeController();
  await themeController.load(); // чтобы не мигала тема на старте
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
        debugShowCheckedModeBanner: false,
        title: 'Crypto Tracker',
        themeMode: controller.mode,
        theme: buildFluidTheme(Brightness.light, controller.accent, controller.design),
        darkTheme: buildFluidTheme(Brightness.dark, controller.accent, controller.design),
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
/// БЕГУЩАЯ СТРОКА (ТИКЕР)
/// ======================

class TickerMarquee extends StatefulWidget {
  final List<CoinTicker> items;
  final double height;
  final double speed; // 0.5..2.0 (x)
  final bool compact;

  const TickerMarquee({
    super.key,
    required this.items,
    required this.speed,
    this.height = 40,
    this.compact = false,
  });

  @override
  State<TickerMarquee> createState() => _TickerMarqueeState();
}

class _TickerMarqueeState extends State<TickerMarquee> {
  final _ctrl = ScrollController();
  bool _running = false;

  @override
  void didUpdateWidget(covariant TickerMarquee oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.length != widget.items.length ||
        oldWidget.speed != widget.speed ||
        oldWidget.compact != widget.compact) {
      _restart();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (_running) return;
    _running = true;
    while (mounted) {
      if (!_ctrl.hasClients) {
        await Future.delayed(const Duration(milliseconds: 300));
        continue;
      }
      final max = _ctrl.position.maxScrollExtent;
      if (max <= 0) {
        await Future.delayed(const Duration(milliseconds: 500));
        continue;
      }
      final pps = 45.0 * widget.speed; // пикселей в секунду
      final dur = Duration(milliseconds: ((max / pps) * 1000).round());
      try {
        await _ctrl.animateTo(max, duration: dur, curve: Curves.linear);
        if (!mounted) break;
        _ctrl.jumpTo(0);
        await Future.delayed(const Duration(milliseconds: 80));
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }
  }

  void _restart() {
    if (!_ctrl.hasClients) return;
    _ctrl.jumpTo(0);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final prefs = DesignPrefs.of(context);
    final border = cs.outlineVariant.withOpacity(.9);

    final items = widget.items.isEmpty ? const <CoinTicker>[] : widget.items.take(40).toList();
    final tape = [...items, ...items]; // бесшовная прокрутка

    return Container(
      height: widget.height,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(prefs.radius),
        border: Border.all(color: border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          ListView.separated(
            controller: _ctrl,
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: tape.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) => _TickerTag(
              coin: tape[i % items.length],
              compact: widget.compact,
            ),
          ),
          // мягкие затухания по краям
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      cs.surface.withOpacity(.95),
                      Colors.transparent,
                      Colors.transparent,
                      cs.surface.withOpacity(.95),
                    ],
                    stops: const [0.0, 0.06, 0.94, 1.0],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TickerTag extends StatelessWidget {
  final CoinTicker coin;
  final bool compact;

  const _TickerTag({required this.coin, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final up = coin.percentChange24h >= 0;
    final color = up ? const Color(0xFF16A34A) : const Color(0xFFDC2626);

    final fmtPrice = NumberFormat.compactCurrency(locale: 'ru_RU', symbol: '\$').format(coin.priceUsd);
    final ch = NumberFormat("+#,##0.00;-#,##0.00", 'ru_RU').format(coin.percentChange24h) + '%';

    final pad = compact
        ? const EdgeInsets.symmetric(horizontal: 10, vertical: 4)
        : const EdgeInsets.symmetric(horizontal: 12, vertical: 6);

    return Container(
      padding: pad,
      decoration: BoxDecoration(
        color: cs.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: compact ? 9 : 10,
            backgroundColor: cs.surface,
            backgroundImage: NetworkImage(coin.logoUrl),
            onBackgroundImageError: (_, __) {},
          ),
          const SizedBox(width: 8),
          Text(
            coin.symbol,
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: compact ? 12 : 13),
          ),
          const SizedBox(width: 8),
          Text(
            fmtPrice,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: compact ? 12 : 13,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(width: 10),
          Row(
            children: [
              Icon(up ? Icons.arrow_drop_up : Icons.arrow_drop_down, color: color, size: compact ? 18 : 20),
              Text(
                ch,
                style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: compact ? 12 : 13),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// ======================
/// МОДЕЛИ (рынок)
/// ======================

class CoinTicker {
  final String id; // coinpaprika id (e.g., btc-bitcoin)
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
/// API / СЕРВИСЫ (рынок)
/// ======================

String _friendlyNetworkError(Object e) {
  if (e is SocketException) {
    return 'Нет доступа к интернету или не выдано разрешение INTERNET (Android). '
        'Добавьте <uses-permission android:name="android.permission.INTERNET" /> в AndroidManifest '
        'и проверьте соединение.';
  }
  if (e is TimeoutException) {
    return 'Таймаут сети. Проверьте подключение и повторите попытку.';
  }
  return e.toString();
}

class CoinPaprikaApi {
  static const _base = 'https://api.coinpaprika.com/v1';
  final http.Client _client = http.Client();

  Future<List<CoinTicker>> fetchTopTickers({int limit = 200}) async {
    final uri = Uri.parse('$_base/tickers?quotes=USD');
    try {
      final res = await _client.get(uri, headers: {'Accept': 'application/json'}).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) {
        throw Exception('CoinPaprika tickers failed: ${res.statusCode}');
      }
      final list = (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
      final items = list.map(CoinTicker.fromJson).where((e) => e.rank > 0).toList()
        ..sort((a, b) => a.rank.compareTo(b.rank));
      return items.take(limit).toList();
    } catch (e) {
      throw Exception(_friendlyNetworkError(e));
    }
  }

  Future<List<HistoricalPoint>> fetchHistory(String coinId, ChartRange range) async {
    final now = DateTime.now().toUtc();
    late DateTime start;
    late String interval;

    switch (range) {
      case ChartRange.d1:
        start = now.subtract(const Duration(days: 1));
        interval = '1h';
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
        interval = '1d';
        break;
    }

    final startStr = DateFormat('yyyy-MM-dd').format(start);
    final endStr = DateFormat('yyyy-MM-dd').format(now);
    final uri = Uri.parse(
      '$_base/tickers/$coinId/historical?start=$startStr&end=$endStr&interval=$interval&quote=usd',
    );
    try {
      final res = await _client.get(uri, headers: {'Accept': 'application/json'}).timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        throw Exception('CoinPaprika history failed ${res.statusCode}');
      }
      final list = (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
      return list.map((m) {
        final ts = DateTime.parse(m['timestamp'] as String).toLocal();
        final price = (m['price'] as num?)?.toDouble() ?? 0.0;
        return HistoricalPoint(ts, price);
      }).toList();
    } catch (e) {
      throw Exception(_friendlyNetworkError(e));
    }
  }

  /// Дневные OHLC — с фолбэком
  Future<List<HistoricalPoint>> fetchDailyOhlc(String coinId, DateTime start, DateTime end) async {
    final s0 = DateTime(start.year, start.month, start.day);
    var e0 = DateTime(end.year, end.month, end.day);
    if (!e0.isAfter(s0)) e0 = s0.add(const Duration(days: 1));

    final s = DateFormat('yyyy-MM-dd').format(s0);
    final e = DateFormat('yyyy-MM-dd').format(e0);

    final ohlcUri = Uri.parse('$_base/coins/$coinId/ohlcv/historical?start=$s&end=$e');
    try {
      final res = await _client.get(ohlcUri, headers: {'Accept': 'application/json'}).timeout(const Duration(seconds: 20));
      if (res.statusCode == 200) {
        final list = (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
        final points = list
            .map((m) {
          final ts = DateTime.parse((m['time_close'] ?? m['time_open']) as String).toLocal();
          final close = (m['close'] as num?)?.toDouble() ?? 0.0;
          return HistoricalPoint(ts, close);
        })
            .toList()
          ..sort((a, b) => a.time.compareTo(b.time));
        return points;
      }
    } catch (_) {
      // идём на фолбэк ниже
    }

    // фолбэк: tickers/{id}/historical (1d)
    final altUri = Uri.parse(
      '$_base/tickers/$coinId/historical?start=$s&end=$e&interval=1d&quote=usd',
    );
    try {
      final res2 = await _client.get(altUri, headers: {'Accept': 'application/json'}).timeout(const Duration(seconds: 20));
      if (res2.statusCode == 200) {
        final list = (jsonDecode(res2.body) as List).cast<Map<String, dynamic>>();
        final points = list
            .map((m) {
          final ts = DateTime.parse(m['timestamp'] as String).toLocal();
          final price = (m['price'] as num?)?.toDouble() ?? 0.0;
          return HistoricalPoint(ts, price);
        })
            .toList()
          ..sort((a, b) => a.time.compareTo(b.time));
        return points;
      }
      throw Exception('CoinPaprika ohlcv failed and fallback failed (code: ${res2.statusCode})');
    } catch (e) {
      throw Exception(_friendlyNetworkError(e));
    }
  }
}

class BinanceWsService {
  WebSocketChannel? _channel;
  Stream<double>? _priceStream;

  Stream<double>? openTradePriceStream(String symbolUpper) {
    close();
    final sym = symbolUpper.toLowerCase();
    if (sym == 'usdt') return null;
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

class BinanceRestService {
  static const _base = 'https://api.binance.com';
  final http.Client _client = http.Client();

  Future<List<HistoricalPoint>?> fetchKlines(String symbolUpper, String interval, int limit) async {
    final sym = symbolUpper.toUpperCase();
    if (sym == 'USDT') return null;
    final symbol = '${sym}USDT';
    final uri = Uri.parse('$_base/api/v3/klines?symbol=$symbol&interval=$interval&limit=$limit');
    try {
      final res = await _client.get(uri, headers: {'Accept': 'application/json'}).timeout(const Duration(seconds: 20));
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

class HistoryRepository {
  final CoinPaprikaApi paprika;
  final BinanceRestService binance;

  HistoryRepository({CoinPaprikaApi? paprika, BinanceRestService? binance})
      : paprika = paprika ?? CoinPaprikaApi(),
        binance = binance ?? BinanceRestService();

  Future<List<HistoricalPoint>> get(String coinId, String symbol, ChartRange range) async {
    try {
      final r = await paprika.fetchHistory(coinId, range);
      if (r.isNotEmpty) return r;
    } catch (_) {}

    try {
      List<HistoricalPoint>? b;
      switch (range) {
        case ChartRange.d1:
          b = await binance.fetchKlines(symbol, '1h', 24);
          break;
        case ChartRange.d7:
          b = await binance.fetchKlines(symbol, '1d', 7);
          break;
        case ChartRange.d30:
          b = await binance.fetchKlines(symbol, '1d', 30);
          break;
        case ChartRange.y1:
          b = await binance.fetchKlines(symbol, '1d', 365);
          break;
      }
      if (b != null && b.isNotEmpty) return b;
    } catch (_) {}

    try {
      final now = DateTime.now().toUtc();
      final start = switch (range) {
        ChartRange.d1 => now.subtract(const Duration(days: 2)),
        ChartRange.d7 => now.subtract(const Duration(days: 7)),
        ChartRange.d30 => now.subtract(const Duration(days: 30)),
        ChartRange.y1 => now.subtract(const Duration(days: 365)),
      };
      final o = await paprika.fetchDailyOhlc(coinId, start, now);
      if (o.isNotEmpty) return o;
    } catch (_) {}

    return <HistoricalPoint>[];
  }
}

/// ======================
/// ГЛАВНЫЙ ЭКРАН — Список монет
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
  DateTime? _updatedAt;

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    try {
      if (!silent) setState(() => _loading = true);
      final data = await api.fetchTopTickers(limit: 200);
      setState(() {
        _all = data;
        _updatedAt = DateTime.now();
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
    final prefs = DesignPrefs.of(context);
    final updatedText =
    _updatedAt == null ? '—' : DateFormat('dd.MM.yyyy, HH:mm', 'ru_RU').format(_updatedAt!);

    return Scaffold(
      appBar: fluidAppBar(
        context,
        title: 'Crypto Tracker',
        actions: [
          IconButton(
            tooltip: 'Портфель',
            icon: const Icon(Icons.pie_chart_rounded),
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => PortfolioPage(controller: widget.controller),
              ));
            },
          ),
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
          // === БЕГУЩАЯ СТРОКА (строгая) ===
          TickerMarquee(
            items: _all,
            speed: prefs.tickerSpeed,
            compact: prefs.tickerCompact,
            height: prefs.tickerCompact ? 34 : 40,
          ),

          // Шапка раздела
          // StrictHeader(
          //   title: 'Рынок',
          //   subtitle: 'Топ‑200 по CoinPaprika • Обновлено: $updatedText',
          //   margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          // ),

          // Поиск
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Поиск по имени или символу…',
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
                    final changeColor = change >= 0 ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
                    return ListTile(
                      visualDensity: prefs.compact ? VisualDensity.compact : VisualDensity.standard,
                      leading: CircleAvatar(
                        backgroundImage: NetworkImage(c.logoUrl),
                        onBackgroundImageError: (_, __) {},
                        child: Text(c.symbol.isNotEmpty ? c.symbol[0] : '?'),
                      ),
                      title: Text(
                        '${c.rank}. ${c.name} (${c.symbol})',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        'MC: ${_fmtCurrency.format(c.marketCapUsd)} • Vol 24ч: ${_fmtCurrency.format(c.volume24hUsd)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      // В dense/компактном режиме ListTile даёт трейлингу ~40px высоты.
                      // Чтобы не ловить RenderFlex overflow — скейлим по необходимости.
                      trailing: SizedBox(
                        height: 40,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                _fmtCurrency.format(c.priceUsd),
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  height: 1.1,
                                ),
                              ),
                              Text(
                                '${change >= 0 ? '+' : ''}${_fmtPerc.format(change)}%',
                                style: TextStyle(
                                  color: changeColor,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  height: 1.1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => CoinDetailPage(ticker: c),
                      )),
                    );
                  },
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Text(
              'Источник: CoinPaprika (REST). На экране детали — лайв‑тикер Binance, если доступно.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          )
        ],
      ),
    );
  }
}

/// ======================
/// НАСТРОЙКИ
/// ======================

class SettingsPage extends StatelessWidget {
  final ThemeController controller;
  const SettingsPage({super.key, required this.controller});

  Color _accentSeed(AccentPalette a) => switch (a) {
    AccentPalette.purple => const Color(0xFF4F46E5),
    AccentPalette.teal => const Color(0xFF0F766E),
    AccentPalette.gray => const Color(0xFF334155),
    AccentPalette.bitcoin => const Color(0xFFB45309),
    AccentPalette.tether => const Color(0xFF047857),
  };

  Widget _accentOption(BuildContext context, AccentPalette accent, String title) {
    final selected = controller.accent == accent;
    final cs = Theme.of(context).colorScheme;

    return RadioListTile<AccentPalette>(
      value: accent,
      groupValue: controller.accent,
      onChanged: (v) => controller.setAccent(v!),
      title: Row(
        children: [
          Expanded(child: Text(title)),
          const SizedBox(width: 12),
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: _accentSeed(accent),
              shape: BoxShape.circle,
              border: Border.all(color: cs.outlineVariant),
            ),
          ),
        ],
      ),
      selected: selected,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = controller.mode;

    return Scaffold(
      appBar: fluidAppBar(context, title: 'Настройки'),
      body: ListView(
        children: [
          const StrictHeader(
            title: 'Настройки',
            subtitle: 'Тема, палитра и кастомизация интерфейса',
          ),
          const SizedBox(height: 8),

          // Режим темы
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Text('Режим темы', style: Theme.of(context).textTheme.titleMedium),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                RadioListTile<ThemeMode>(
                  title: const Text('Системная'),
                  value: ThemeMode.system,
                  groupValue: current,
                  onChanged: (m) => controller.setMode(m!),
                ),
                const Divider(height: 1),
                RadioListTile<ThemeMode>(
                  title: const Text('Светлая'),
                  value: ThemeMode.light,
                  groupValue: current,
                  onChanged: (m) => controller.setMode(m!),
                ),
                const Divider(height: 1),
                RadioListTile<ThemeMode>(
                  title: const Text('Тёмная'),
                  value: ThemeMode.dark,
                  groupValue: current,
                  onChanged: (m) => controller.setMode(m!),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Палитра
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Text('Акцент', style: Theme.of(context).textTheme.titleMedium),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                _accentOption(context, AccentPalette.gray, 'Slate (строгая)'),
                const Divider(height: 1),
                _accentOption(context, AccentPalette.purple, 'Indigo'),
                const Divider(height: 1),
                _accentOption(context, AccentPalette.teal, 'Teal'),
                const Divider(height: 1),
                _accentOption(context, AccentPalette.bitcoin, 'Bitcoin (оранжевая)'),
                const Divider(height: 1),
                _accentOption(context, AccentPalette.tether, 'Tether (зелёная)'),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Кастомизация интерфейса
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Text('Интерфейс', style: Theme.of(context).textTheme.titleMedium),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                ListTile(
                  title: const Text('Скругление углов'),
                  subtitle: AnimatedBuilder(
                    animation: controller,
                    builder: (_, __) => Text('${controller.design.radius.round()} px'),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Slider(
                    min: 8,
                    max: 40,
                    divisions: 32,
                    value: controller.design.radius,
                    onChanged: (v) => controller.setRadius(v),
                    label: '${controller.design.radius.round()}',
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Компактные списки и отступы'),
                  value: controller.design.compact,
                  onChanged: controller.setCompact,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('AMOLED‑чёрный фон (только тёмная тема)'),
                  value: controller.design.amoledBlack,
                  onChanged: controller.setAmoled,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Высокая контрастность текста'),
                  value: controller.design.highContrast,
                  onChanged: controller.setHighContrast,
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Параметры графиков
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Text('Графики', style: Theme.of(context).textTheme.titleMedium),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Кривые линии'),
                  value: controller.design.curvedCharts,
                  onChanged: controller.setCurvedCharts,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Заливка под графиком'),
                  value: controller.design.showChartArea,
                  onChanged: controller.setShowArea,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Цвет графика: авто (зел/красн)'),
                  subtitle: const Text('Выключите, чтобы использовать цвет темы'),
                  value: controller.design.autoChartColor,
                  onChanged: controller.setAutoChartColor,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Показывать точку на последнем значении'),
                  value: controller.design.showLastDot,
                  onChanged: controller.setShowLastDot,
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Параметры бегущей строки
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Text('Бегущая строка', style: Theme.of(context).textTheme.titleMedium),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                ListTile(
                  title: const Text('Скорость прокрутки'),
                  subtitle: AnimatedBuilder(
                    animation: controller,
                    builder: (_, __) => Text('${controller.design.tickerSpeed.toStringAsFixed(2)}×'),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Slider(
                    min: 0.5,
                    max: 2.0,
                    divisions: 15,
                    value: controller.design.tickerSpeed,
                    onChanged: (v) => controller.setTickerSpeed(v),
                    label: '${controller.design.tickerSpeed.toStringAsFixed(2)}×',
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Компактные теги тикера'),
                  value: controller.design.tickerCompact,
                  onChanged: controller.setTickerCompact,
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Подсказка: все изменения применяются сразу и сохраняются.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// ======================
/// ДЕТАЛИ МОНЕТЫ
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
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    final cs = Theme.of(context).colorScheme;
    final currentPrice = _livePrice ?? widget.ticker.priceUsd;
    final ch24 = widget.ticker.percentChange24h;
    final changeColor = ch24 >= 0 ? const Color(0xFF16A34A) : const Color(0xFFDC2626);

    // === AUTO-FULLSCREEN В LANDSCAPE ===
    // При повороте телефона в горизонталь — показываем только график на весь экран
    // прямо на этой же странице (без отдельной кнопки).
    if (isLandscape) {
      final prefs = DesignPrefs.of(context);
      final title = '${widget.ticker.name} (${widget.ticker.symbol})';

      Widget chart;
      if (_loading) {
        chart = const Center(child: CircularProgressIndicator());
      } else if (_points.isEmpty) {
        chart = const Center(child: Text('Нет данных для выбранного диапазона'));
      } else {
        chart = Padding(
          padding: const EdgeInsets.fromLTRB(12, 56, 12, 60),
          child: _buildLineChart(),
        );
      }

      return Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(child: chart),

              // Верхняя панель (back + название + цена)
              Positioned(
                left: 12,
                right: 12,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: cs.surface.withOpacity(0.92),
                    borderRadius: BorderRadius.circular(prefs.radius),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back),
                        tooltip: 'Назад',
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${_fmtCurrency.format(currentPrice)}  •  ${ch24 >= 0 ? '+' : ''}${NumberFormat.decimalPattern('ru_RU').format(ch24)}% 24ч',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: changeColor, fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Нижняя панель (диапазоны)
              Positioned(
                left: 12,
                right: 12,
                bottom: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: cs.surface.withOpacity(0.92),
                    borderRadius: BorderRadius.circular(prefs.radius),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _rangeChip('1D', ChartRange.d1),
                        const SizedBox(width: 8),
                        _rangeChip('7D', ChartRange.d7),
                        const SizedBox(width: 8),
                        _rangeChip('30D', ChartRange.d30),
                        const SizedBox(width: 8),
                        _rangeChip('1Y', ChartRange.y1),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: fluidAppBar(
        context,
        title: '${widget.ticker.name} (${widget.ticker.symbol})',
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StrictHeader(
            title: widget.ticker.name,
            subtitle: '${widget.ticker.symbol} • ${_fmtCurrency.format(currentPrice)}',
            leading: CircleAvatar(
              backgroundImage: NetworkImage(widget.ticker.logoUrl),
              radius: 18,
              onBackgroundImageError: (_, __) {},
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: cs.surfaceVariant,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    ch24 >= 0 ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                    size: 18,
                    color: changeColor,
                  ),
                  Text(
                    '${ch24 >= 0 ? '+' : ''}${NumberFormat.decimalPattern('ru_RU').format(ch24)}% 24ч',
                    style: TextStyle(fontWeight: FontWeight.w800, color: changeColor),
                  ),
                ],
              ),
            ),
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          ),

          const SizedBox(height: 8),

          // диапазоны
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

          // график
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _points.isEmpty
                ? const Center(child: Text('Нет данных для выбранного диапазона'))
                : Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: _buildLineChart(),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );
  }

  Widget _buildLineChart() {
    final prefs = DesignPrefs.of(context);
    final cs = Theme.of(context).colorScheme;

    final spots = <FlSpot>[];
    double minY = double.infinity;
    double maxY = -double.infinity;

    for (final p in _points) {
      final x = p.time.millisecondsSinceEpoch.toDouble();
      final y = p.price;
      if (y.isFinite) {
        spots.add(FlSpot(x, y));
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }

    if (spots.isEmpty) return const Center(child: Text('Нет данных'));

    // Диапазон Y
    if (maxY - minY == 0) {
      final pad = maxY == 0 ? 1.0 : maxY * 0.05;
      minY = (maxY - pad).clamp(0, double.infinity);
      maxY = maxY + pad;
    } else {
      final pad = (maxY - minY) * 0.05;
      minY = (minY - pad).clamp(0, double.infinity);
      maxY = maxY + pad;
    }

    // Ось X/Y
    final minX = spots.first.x;
    final maxX = spots.last.x;
    final double xInterval = (maxX - minX).abs() > 0 ? (maxX - minX) / 4.0 : 1.0;
    final double yInterval = (maxY - minY).abs() > 0 ? (maxY - minY) / 4.0 : 1.0;

    final isUp = spots.last.y >= spots.first.y;
    final baseColor = prefs.autoChartColor
        ? (isUp ? const Color(0xFF16A34A) : const Color(0xFFDC2626))
        : cs.primary;

    final axisColor = cs.onSurface.withOpacity(0.70);
    final gridColor = cs.onSurface.withOpacity(0.10);

    String formatX(double xVal) {
      final dt = DateTime.fromMillisecondsSinceEpoch(xVal.toInt()).toLocal();
      return _range == ChartRange.d1 ? DateFormat.Hm('ru_RU').format(dt) : DateFormat('dd.MM.yyyy', 'ru_RU').format(dt);
    }

    String formatY(double v) => NumberFormat.compactCurrency(locale: 'ru_RU', symbol: '\$').format(v);

    final lastSpot = spots.last;

    return LineChart(
      LineChartData(
        minY: minY,
        maxY: maxY,
        minX: minX,
        maxX: maxX,
        lineTouchData: LineTouchData(
          handleBuiltInTouches: true,
          touchTooltipData: LineTouchTooltipData(
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            tooltipRoundedRadius: 10,
            tooltipPadding: const EdgeInsets.all(8),
            getTooltipItems: (ts) => ts.map((s) {
              final dt = DateTime.fromMillisecondsSinceEpoch(s.x.toInt()).toLocal();
              final timeLabel = _range == ChartRange.d1
                  ? DateFormat.Hm('ru_RU').format(dt)
                  : DateFormat('dd.MM.yyyy', 'ru_RU').format(dt);
              return LineTooltipItem(
                '${NumberFormat.currency(locale: "ru_RU", symbol: "\$").format(s.y)}\n$timeLabel',
                TextStyle(fontWeight: FontWeight.w700, color: cs.onSurface),
              );
            }).toList(),
          ),
          getTouchedSpotIndicator: (bar, indexes) => indexes.map((_) {
            return TouchedSpotIndicatorData(
              FlLine(color: baseColor.withOpacity(0.30), strokeWidth: 1),
              const FlDotData(show: false),
            );
          }).toList(),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 56,
              interval: yInterval,
              getTitlesWidget: (v, _) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(formatY(v), style: TextStyle(fontSize: 11, color: axisColor)),
              ),
            ),
          ),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: xInterval,
              getTitlesWidget: (value, _) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(formatX(value), style: TextStyle(fontSize: 11, color: axisColor)),
              ),
            ),
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: yInterval,
          getDrawingHorizontalLine: (_) => FlLine(color: gridColor, strokeWidth: 1, dashArray: const [4, 4]),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: prefs.curvedCharts,
            color: baseColor,
            barWidth: 3,
            dotData: FlDotData(
              show: prefs.showLastDot,
              checkToShowDot: (s, __) => s.x == lastSpot.x,
              getDotPainter: (s, __, ___, ____) => FlDotCirclePainter(
                radius: 3.8,
                color: baseColor,
                strokeWidth: 2,
                strokeColor: Theme.of(context).scaffoldBackgroundColor,
              ),
            ),
            belowBarData: BarAreaData(
              show: prefs.showChartArea,
              gradient: LinearGradient(
                colors: [baseColor.withOpacity(0.22), baseColor.withOpacity(0.04)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ======================
/// ПОРТФЕЛЬ
/// ======================

enum TxType { buy, sell, transferIn, reward, watchOnly }

enum BasisMethod { price, zero, fmv, income, none }

class PortfolioTx {
  final String id;
  final String coinId;
  final String symbol;
  final String name;
  final double quantity;
  final TxType type;
  final BasisMethod basis;
  final double? price;
  final DateTime date;
  final String? note;

  PortfolioTx({
    required this.id,
    required this.coinId,
    required this.symbol,
    required this.name,
    required this.quantity,
    required this.type,
    required this.basis,
    required this.date,
    this.price,
    this.note,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'coinId': coinId,
    'symbol': symbol,
    'name': name,
    'quantity': quantity,
    'type': type.name,
    'basis': basis.name,
    'price': price,
    'date': date.toIso8601String(),
    'note': note,
  };

  factory PortfolioTx.fromJson(Map<String, dynamic> m) => PortfolioTx(
    id: m['id'] as String,
    coinId: m['coinId'] as String,
    symbol: (m['symbol'] as String).toUpperCase(),
    name: m['name'] as String,
    quantity: (m['quantity'] as num).toDouble(),
    type: TxType.values.firstWhere((v) => v.name == m['type']),
    basis: BasisMethod.values.firstWhere((v) => v.name == m['basis']),
    price: (m['price'] as num?)?.toDouble(),
    date: DateTime.parse(m['date'] as String),
    note: m['note'] as String?,
  );
}

abstract class IPortfolioRepository {
  Future<List<PortfolioTx>> load();
  Future<void> save(List<PortfolioTx> list);
  Future<void> clear();
}

class PortfolioRepositoryPrefs implements IPortfolioRepository {
  static const _key = 'portfolio_txs';

  @override
  Future<List<PortfolioTx>> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString(_key);
      if (s == null || s.isEmpty) return [];
      final list = (jsonDecode(s) as List).cast<Map<String, dynamic>>();
      return list.map(PortfolioTx.fromJson).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> save(List<PortfolioTx> list) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, jsonEncode(list.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  @override
  Future<void> clear() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_key);
    } catch (_) {}
  }
}

class PortfolioPosition {
  final String coinId;
  final String symbol;
  final String name;
  double totalQty = 0;
  double costQty = 0;
  double costAmount = 0;
  double incomeAmount = 0;

  PortfolioPosition({required this.coinId, required this.symbol, required this.name});

  double? get avgCost => costQty > 0 ? (costAmount / costQty) : null;
}

class PortfolioComputed {
  final List<PortfolioPosition> positions;
  final Map<String, double> priceByCoinId;
  PortfolioComputed(this.positions, this.priceByCoinId);

  double priceOf(String coinId) => priceByCoinId[coinId] ?? 0;

  double get totalCurrentValue => positions.fold(0, (s, p) => s + priceOf(p.coinId) * p.totalQty);

  double get investedCost => positions.fold(0, (s, p) => s + p.costAmount);

  double get unrealizedAbs {
    double sum = 0;
    for (final p in positions) {
      if (p.costQty > 0) {
        sum += priceOf(p.coinId) * p.costQty - p.costAmount;
      }
    }
    return sum;
  }

  double? get unrealizedPct => investedCost > 0 ? (unrealizedAbs / investedCost) * 100.0 : null;

  double get incomeTotal => positions.fold(0, (s, p) => s + p.incomeAmount);
}

class PortfolioService {
  // AVG COST + варианты cost basis
  List<PortfolioPosition> aggregate(List<PortfolioTx> txs) {
    txs = [...txs]..sort((a, b) => a.date.compareTo(b.date));
    final map = <String, PortfolioPosition>{};

    PortfolioPosition get(String coinId, String symbol, String name) =>
        map.putIfAbsent(coinId, () => PortfolioPosition(coinId: coinId, symbol: symbol, name: name));

    for (final t in txs) {
      final p = get(t.coinId, t.symbol, t.name);

      switch (t.type) {
        case TxType.buy:
          p.totalQty += t.quantity;
          if (t.price != null) {
            p.costQty += t.quantity;
            p.costAmount += (t.price! * t.quantity);
          }
          break;

        case TxType.transferIn:
        case TxType.reward:
          p.totalQty += t.quantity;
          switch (t.basis) {
            case BasisMethod.zero:
              p.costQty += t.quantity;
              break;
            case BasisMethod.fmv:
              if (t.price != null) {
                p.costQty += t.quantity;
                p.costAmount += t.price! * t.quantity;
              }
              break;
            case BasisMethod.income:
              if (t.price != null) {
                p.costQty += t.quantity;
                final amt = t.price! * t.quantity;
                p.costAmount += amt;
                p.incomeAmount += amt;
              }
              break;
            default:
              if (t.price != null) {
                p.costQty += t.quantity;
                p.costAmount += t.price! * t.quantity;
              }
          }
          break;

        case TxType.watchOnly:
          p.totalQty += t.quantity;
          break;

        case TxType.sell:
          final q = t.quantity;
          if (p.costQty > 0) {
            final avg = p.costAmount / p.costQty;
            final reduce = q <= p.costQty ? q : p.costQty;
            p.costQty -= reduce;
            p.costAmount -= avg * reduce;
            p.totalQty -= q;
          } else {
            p.totalQty -= q;
          }
          break;
      }
    }

    return map.values
        .where((p) => p.totalQty != 0 || p.costQty != 0 || p.costAmount != 0)
        .toList()
      ..sort((a, b) => a.symbol.compareTo(b.symbol));
  }
}

/// ======================
/// ПОРТФЕЛЬ — UI
/// ======================

enum PortfolioChartRange { d30, y1 }

class PortfolioPage extends StatefulWidget {
  final ThemeController controller;
  const PortfolioPage({super.key, required this.controller});

  @override
  State<PortfolioPage> createState() => _PortfolioPageState();
}

class _PortfolioPageState extends State<PortfolioPage> {
  final repo = PortfolioRepositoryPrefs();
  final paprika = CoinPaprikaApi();
  final service = PortfolioService();
  final _binance = BinanceRestService();

  int _touchedSlice = -1;

  final _fmtCurrency = NumberFormat.currency(locale: 'ru_RU', symbol: '\$');

  List<PortfolioTx> _txs = [];
  List<CoinTicker> _tickers = [];
  Map<String, double> _priceById = {};
  List<PortfolioPosition> _positions = [];

  PortfolioChartRange _range = PortfolioChartRange.d30;

  bool _loading = true;
  bool _loadingHistory = false;
  List<HistoricalPoint> _portfolioHistory = [];

  @override
  void initState() {
    super.initState();
    _initLoad();
  }

  Future<void> _initLoad() async {
    setState(() => _loading = true);
    try {
      final txs = await repo.load();
      final ticks = await paprika.fetchTopTickers(limit: 200);
      final price = {for (final t in ticks) t.id: t.priceUsd};

      final positions = service.aggregate(txs);

      setState(() {
        _txs = txs;
        _tickers = ticks;
        _priceById = price;
        _positions = positions;
        _loading = false;
      });

      _loadHistory();
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    }
  }

  Future<void> _refreshPrices() async {
    try {
      final ticks = await paprika.fetchTopTickers(limit: 200);
      setState(() {
        _tickers = ticks;
        _priceById = {for (final t in ticks) t.id: t.priceUsd};
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Не удалось обновить цены: $e')));
    }
  }

  Future<void> _saveTxs() async {
    await repo.save(_txs);
    setState(() {
      _positions = service.aggregate(_txs);
    });
    _loadHistory();
  }

  Future<void> _addTx() async {
    final res = await Navigator.of(context).push<PortfolioTx>(
      MaterialPageRoute(
        builder: (_) => AddTransactionPage(tickers: _tickers),
      ),
    );
    if (res != null) {
      setState(() => _txs.add(res));
      await _saveTxs();
    }
  }

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Очистить портфель?'),
        content: const Text('Все транзакции будут удалены. Это необратимо.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Очистить')),
        ],
      ),
    );
    if (ok == true) {
      setState(() => _txs.clear());
      await repo.clear();
      setState(() {
        _positions = [];
        _portfolioHistory = [];
      });
    }
  }

  Future<List<HistoricalPoint>> _dailySeriesWithFallback(
      String coinId,
      String symbol,
      DateTime start,
      DateTime end,
      ) async {
    try {
      return await paprika.fetchDailyOhlc(coinId, start, end);
    } catch (_) {
      final days = end.difference(start).inDays + 1;
      final klines = await _binance.fetchKlines(symbol, '1d', days.clamp(1, 1000));
      if (klines != null && klines.isNotEmpty) {
        final s0 = DateTime(start.year, start.month, start.day);
        final e0 = DateTime(end.year, end.month, end.day);
        return klines.where((p) {
          final d = DateTime(p.time.year, p.time.month, p.time.day);
          return !d.isBefore(s0) && !d.isAfter(e0);
        }).toList();
      }
      return <HistoricalPoint>[];
    }
  }

  Future<void> _loadHistory() async {
    setState(() => _loadingHistory = true);
    try {
      if (_positions.isEmpty) {
        setState(() {
          _portfolioHistory = [];
          _loadingHistory = false;
        });
        return;
      }

      final now = DateTime.now();
      final start = _range == PortfolioChartRange.d30 ? now.subtract(const Duration(days: 30)) : now.subtract(const Duration(days: 365));

      final series = <DateTime, double>{};
      for (final p in _positions) {
        if (p.totalQty <= 0) continue;

        final data = await _dailySeriesWithFallback(p.coinId, p.symbol, start, now);

        for (final point in data) {
          final day = DateTime(point.time.year, point.time.month, point.time.day);
          series[day] = (series[day] ?? 0) + point.price * p.totalQty;
        }
      }

      final points = series.entries.toList()..sort((a, b) => a.key.compareTo(b.key));

      setState(() {
        _portfolioHistory = points.map((e) => HistoricalPoint(e.key, e.value)).toList();
      });
    } finally {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final prefs = DesignPrefs.of(context);
    final computed = PortfolioComputed(_positions, _priceById);

    // Авто‑fullscreen для графика портфеля в landscape.
    // В landscape показываем только график + компактную панель управления.
    if (isLandscape) {
      final cs = Theme.of(context).colorScheme;
      final title = 'Портфель';
      final total = _fmtCurrency.format(computed.totalCurrentValue);

      final Widget chartChild;
      if (_loading) {
        chartChild = const Center(child: CircularProgressIndicator());
      } else if (_loadingHistory) {
        chartChild = const Center(child: CircularProgressIndicator());
      } else if (_portfolioHistory.isEmpty) {
        chartChild = const Center(child: Text('Нет данных'));
      } else {
        chartChild = _buildPortfolioChart(prefs);
      }

      return Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 60, 12, 12),
                  child: chartChild,
                ),
              ),
              Positioned(
                top: 8,
                left: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(prefs.radius),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Назад',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            Text(
                              'Итого: $total',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Обновить',
                        onPressed: () async {
                          await _refreshPrices();
                          if (!mounted) return;
                          setState(() => _positions = service.aggregate(_txs));
                          await _loadHistory();
                        },
                        icon: const Icon(Icons.refresh),
                      ),
                      const SizedBox(width: 6),
                      SegmentedButton<PortfolioChartRange>(
                        segments: const [
                          ButtonSegment(value: PortfolioChartRange.d30, label: Text('30D')),
                          ButtonSegment(value: PortfolioChartRange.y1, label: Text('1Y')),
                        ],
                        selected: {_range},
                        onSelectionChanged: (s) {
                          setState(() => _range = s.first);
                          _loadHistory();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: fluidAppBar(
        context,
        title: 'Портфель',
        actions: [
          IconButton(
            tooltip: 'Обновить цены',
            icon: const Icon(Icons.refresh),
            onPressed: _refreshPrices,
          ),
          IconButton(
            tooltip: 'Настройки',
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => SettingsPage(controller: widget.controller),
              ));
            },
          ),
          PopupMenuButton<String>(
            tooltip: 'Действия',
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'clear', child: Text('Очистить портфель')),
            ],
            onSelected: (v) {
              if (v == 'clear') _clearAll();
            },
            icon: const Icon(Icons.more_vert),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addTx,
        icon: const Icon(Icons.add),
        label: const Text('Добавить'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: () async {
          await _refreshPrices();
          setState(() => _positions = service.aggregate(_txs));
          await _loadHistory();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          children: [
            const StrictHeader(
              title: 'Портфель',
              subtitle: 'Сводка, распределение и динамика',
              margin: EdgeInsets.zero,
            ),
            const SizedBox(height: 12),
            _summary(computed),
            const SizedBox(height: 12),
            _allocationChart(computed, prefs),
            const SizedBox(height: 12),
            _historyCard(prefs),
            const SizedBox(height: 12),
            _positionsList(computed, prefs),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _summary(PortfolioComputed c) {
    final invested = c.investedCost;
    final pnlAbs = c.unrealizedAbs;
    final pnlPct = c.unrealizedPct;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 24,
          runSpacing: 12,
          children: [
            _kv('Текущая стоимость', _fmtCurrency.format(c.totalCurrentValue)),
            _kv('Инвестировано (Cost Basis)', invested > 0 ? _fmtCurrency.format(invested) : '—'),
            _kv('Нереализованный P&L', invested > 0 ? _fmtCurrency.format(pnlAbs) : 'N/A'),
            _kv('Доходность', invested > 0 ? '${pnlPct!.toStringAsFixed(2)}%' : 'N/A'),
          ],
        ),
      ),
    );
  }

  // Пончик: распределение активов
  Widget _allocationChart(PortfolioComputed c, DesignPrefs prefs) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final positions = _positions.where((p) => c.priceOf(p.coinId) * p.totalQty > 0).toList();
    final total = positions.fold<double>(0, (s, p) => s + c.priceOf(p.coinId) * p.totalQty);

    if (total <= 0) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            height: 220,
            child: Center(child: Text('Нет позиций для диаграммы', style: theme.textTheme.bodyMedium)),
          ),
        ),
      );
    }

    const minSlicePct = 0.03; // <3% → «Другое»
    const maxSlices = 9;
    const maxLegend = 10;

    final items = positions
        .map((p) => (coinId: p.coinId, symbol: p.symbol, name: p.name, value: c.priceOf(p.coinId) * p.totalQty))
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final major = <(String, String, String, double)>[];
    double othersValue = 0;
    for (final it in items) {
      final share = it.value / total;
      if (major.length < maxSlices && share >= minSlicePct) {
        major.add((it.coinId, it.symbol, it.name, it.value));
      } else {
        othersValue += it.value;
      }
    }
    if (othersValue > 0) major.add(('', 'ДРУГОЕ', 'Другое', othersValue));

    final themeColors = <Color>[
      cs.primary,
      cs.tertiary,
      const Color(0xFF2563EB),
      const Color(0xFF7C3AED),
      const Color(0xFF0F766E),
      const Color(0xFFB45309),
      const Color(0xFFDB2777),
      const Color(0xFF0891B2),
      const Color(0xFF4B5563),
      const Color(0xFF059669),
    ];

    final fmtCompact = NumberFormat.compactCurrency(locale: 'ru_RU', symbol: '\$');

    final sections = <PieChartSectionData>[];
    for (var i = 0; i < major.length; i++) {
      final m = major[i];
      final color = themeColors[i % themeColors.length];
      final percent = (m.$4 / total * 100);
      final isTouched = i == _touchedSlice;

      sections.add(
        PieChartSectionData(
          value: m.$4,
          color: color,
          title: '${percent.round()}%',
          titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12),
          radius: isTouched ? 74 : 64,
          borderSide: BorderSide(color: theme.scaffoldBackgroundColor, width: 2),
        ),
      );
    }

    Widget centerWidget() {
      if (_touchedSlice >= 0 && _touchedSlice < major.length) {
        final m = major[_touchedSlice];
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(m.$2, style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text(fmtCompact.format(m.$4), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
          ],
        );
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('ИТОГО', style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(fmtCompact.format(total), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
        ],
      );
    }

    Widget legendRow(Color color, String label, double value) {
      final pct = value / total * 100;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Expanded(child: Text(label, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall)),
            Text('${pct.toStringAsFixed(1)}%', style: theme.textTheme.bodySmall),
          ],
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          height: 260,
          child: LayoutBuilder(
            builder: (ctx, constraints) {
              final narrow = constraints.maxWidth < 420;
              final legendWidgets = <Widget>[
                for (var i = 0; i < major.length && i < maxLegend; i++)
                  legendRow(themeColors[i % themeColors.length], '${major[i].$2}  ${major[i].$3}', major[i].$4),
              ];

              final chart = Expanded(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    PieChart(
                      PieChartData(
                        sections: sections,
                        sectionsSpace: 2,
                        centerSpaceRadius: 50,
                        pieTouchData: PieTouchData(
                          touchCallback: (evt, resp) {
                            setState(() {
                              if (!evt.isInterestedForInteractions || resp?.touchedSection == null) {
                                _touchedSlice = -1;
                              } else {
                                _touchedSlice = resp!.touchedSection!.touchedSectionIndex;
                              }
                            });
                          },
                        ),
                      ),
                    ),
                    centerWidget(),
                  ],
                ),
              );

              final legend = SizedBox(
                width: narrow ? double.infinity : 180,
                child: ListView(shrinkWrap: true, children: legendWidgets),
              );

              return narrow ? Column(children: [chart, const SizedBox(height: 12), legend]) : Row(children: [chart, const SizedBox(width: 12), legend]);
            },
          ),
        ),
      ),
    );
  }

  Widget _historyCard(DesignPrefs prefs) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          height: 260,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Историческая динамика портфеля',
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: SegmentedButton<PortfolioChartRange>(
                        segments: const [
                          ButtonSegment(value: PortfolioChartRange.d30, label: Text('30D')),
                          ButtonSegment(value: PortfolioChartRange.y1, label: Text('1Y')),
                        ],
                        selected: {_range},
                        onSelectionChanged: (s) {
                          setState(() => _range = s.first);
                          _loadHistory();
                        },
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _loadingHistory
                    ? const Center(child: CircularProgressIndicator())
                    : _portfolioHistory.isEmpty
                    ? const Center(child: Text('Нет данных'))
                    : _buildPortfolioChart(prefs),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPortfolioChart(DesignPrefs prefs) {
    final cs = Theme.of(context).colorScheme;

    final spots = <FlSpot>[];
    double minY = double.infinity;
    double maxY = -double.infinity;

    for (final p in _portfolioHistory) {
      final x = DateTime(p.time.year, p.time.month, p.time.day).millisecondsSinceEpoch.toDouble();
      final y = p.price;
      spots.add(FlSpot(x, y));
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }

    if (spots.isEmpty) return const Center(child: Text('Нет данных'));

    if (minY == double.infinity || maxY == -double.infinity) {
      minY = 0;
      maxY = 1;
    }

    if (maxY - minY == 0) {
      if (maxY == 0) {
        minY = 0;
        maxY = 1;
      } else {
        final pad = maxY * 0.05;
        minY = maxY - pad;
        maxY = maxY + pad;
      }
    } else {
      final pad = (maxY - minY) * 0.05;
      minY = (minY - pad).clamp(0, double.infinity);
      maxY = maxY + pad;
    }

    final minX = spots.first.x;
    final maxX = spots.last.x;

    final double dy = (maxY - minY).abs();
    final double yInterval = dy > 0 ? dy / 4.0 : 1.0;

    final double dx = (maxX - minX).abs();
    final double xInterval = dx > 0 ? dx / 4.0 : 1.0;

    final axisColor = cs.onSurface.withOpacity(0.70);
    final gridColor = cs.onSurface.withOpacity(0.10);
    final baseColor = cs.primary;

    String formatX(double x) {
      final dt = DateTime.fromMillisecondsSinceEpoch(x.toInt()).toLocal();
      return DateFormat('dd.MM', 'ru_RU').format(dt);
    }

    String formatY(double v) => NumberFormat.compactCurrency(locale: 'ru_RU', symbol: '\$').format(v);

    final lastSpot = spots.last;

    return LineChart(
      LineChartData(
        minY: minY,
        maxY: maxY,
        minX: minX,
        maxX: maxX,
        lineTouchData: LineTouchData(
          handleBuiltInTouches: true,
          touchTooltipData: LineTouchTooltipData(
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            tooltipRoundedRadius: 10,
            tooltipPadding: const EdgeInsets.all(8),
            getTooltipItems: (items) => items.map((s) {
              return LineTooltipItem(
                '${NumberFormat.currency(locale: "ru_RU", symbol: "\$").format(s.y)}\n${formatX(s.x)}',
                TextStyle(fontWeight: FontWeight.w700, color: cs.onSurface),
              );
            }).toList(),
          ),
          getTouchedSpotIndicator: (bar, indexes) => indexes
              .map(
                (_) => TouchedSpotIndicatorData(
              FlLine(color: baseColor.withOpacity(0.30), strokeWidth: 1),
              const FlDotData(show: false),
            ),
          )
              .toList(),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 64,
              interval: yInterval,
              getTitlesWidget: (v, _) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(
                  formatY(v),
                  style: TextStyle(fontSize: 11, color: axisColor),
                ),
              ),
            ),
          ),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: xInterval,
              getTitlesWidget: (value, _) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  formatX(value),
                  style: TextStyle(fontSize: 11, color: axisColor),
                ),
              ),
            ),
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: yInterval,
          getDrawingHorizontalLine: (_) => FlLine(color: gridColor, strokeWidth: 1, dashArray: const [4, 4]),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: prefs.curvedCharts,
            color: baseColor,
            barWidth: 3,
            dotData: FlDotData(
              show: prefs.showLastDot,
              checkToShowDot: (s, __) => s.x == lastSpot.x,
              getDotPainter: (s, __, ___, ____) => FlDotCirclePainter(
                radius: 3.8,
                color: baseColor,
                strokeWidth: 2,
                strokeColor: Theme.of(context).scaffoldBackgroundColor,
              ),
            ),
            belowBarData: BarAreaData(
              show: prefs.showChartArea,
              gradient: LinearGradient(
                colors: [baseColor.withOpacity(0.20), baseColor.withOpacity(0.04)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _positionsList(PortfolioComputed c, DesignPrefs prefs) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Позиции', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final p in _positions) _positionTile(p, c, prefs),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _positionTile(PortfolioPosition p, PortfolioComputed c, DesignPrefs prefs) {
    final price = c.priceOf(p.coinId);
    final curVal = price * p.totalQty;
    final avg = p.avgCost;
    final pnlAbs = (p.costQty > 0) ? (price * p.costQty - p.costAmount) : null;
    final pnlPct = (p.costAmount > 0) ? (pnlAbs! / p.costAmount * 100) : null;
    final watchOnlyQty = p.totalQty - p.costQty;

    final color = (pnlAbs ?? 0) >= 0 ? const Color(0xFF16A34A) : const Color(0xFFDC2626);

    return ListTile(
      visualDensity: prefs.compact ? VisualDensity.compact : VisualDensity.standard,
      leading: CircleAvatar(
        backgroundImage: NetworkImage('https://static.coinpaprika.com/coin/${p.coinId}/logo.png'),
        onBackgroundImageError: (_, __) {},
      ),
      title: Text(
        '${p.name} (${p.symbol})',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Кол-во: ${p.totalQty.toStringAsFixed(8)}${watchOnlyQty > 1e-12 ? '  (watch‑only: ${watchOnlyQty.toStringAsFixed(8)})' : ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            'Средняя цена: ${avg != null ? NumberFormat.currency(locale: "ru_RU", symbol: "\$").format(avg) : 'N/A'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      trailing: SizedBox(
        height: 40,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                NumberFormat.currency(locale: 'ru_RU', symbol: '\$').format(curVal),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              Text(
                pnlAbs == null
                    ? 'P&L: N/A'
                    : 'P&L: ${NumberFormat.currency(locale: "ru_RU", symbol: "\$").format(pnlAbs)}${pnlPct != null ? " (${pnlPct.toStringAsFixed(2)}%)" : ""}',
                style: TextStyle(color: pnlAbs == null ? null : color, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(k, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      const SizedBox(height: 2),
      Text(v, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
    ],
  );
}

/// ======================
/// ДОБАВИТЬ ТРАНЗАКЦИЮ
/// ======================

class AddTransactionPage extends StatefulWidget {
  final List<CoinTicker> tickers;
  const AddTransactionPage({super.key, required this.tickers});

  @override
  State<AddTransactionPage> createState() => _AddTransactionPageState();
}

class _AddTransactionPageState extends State<AddTransactionPage> {
  final _form = GlobalKey<FormState>();
  late List<CoinTicker> _coins;
  late List<CoinTicker> _filtered;
  CoinTicker? _selected;

  final _qtyCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _dateCtrl = TextEditingController();
  DateTime _date = DateTime.now();

  TxType _type = TxType.buy;
  BasisMethod _basis = BasisMethod.price; // для buy используется price
  bool _fetchingFmv = false;

  final paprika = CoinPaprikaApi();

  @override
  void initState() {
    super.initState();
    _coins = widget.tickers;
    _filtered = _coins;
    _dateCtrl.text = DateFormat('dd.MM.yyyy').format(_date);
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    _dateCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2015),
      lastDate: DateTime.now(),
      locale: const Locale('ru', 'RU'),
    );
    if (d != null) {
      setState(() {
        _date = DateTime(d.year, d.month, d.day);
        _dateCtrl.text = DateFormat('dd.MM.yyyy').format(_date);
      });
    }
  }

  Future<void> _fillFmv() async {
    if (_selected == null) return;
    setState(() => _fetchingFmv = true);
    try {
      // берём дневные OHLC вокруг даты (±1 день) — устойчивее к дыркам
      final from = _date.subtract(const Duration(days: 1));
      final to = _date.add(const Duration(days: 1));
      final list = await paprika.fetchDailyOhlc(_selected!.id, from, to);
      if (list.isNotEmpty) {
        HistoricalPoint bestHp = list.first;
        Duration best = (bestHp.time.difference(_date)).abs();
        for (final hp in list) {
          final d = (hp.time.difference(_date)).abs();
          if (d < best) {
            best = d;
            bestHp = hp;
          }
        }
        _priceCtrl.text = bestHp.price.toStringAsFixed(8);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Нет цены за выбранную дату')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('FMV: $e')));
    } finally {
      if (mounted) setState(() => _fetchingFmv = false);
    }
  }

  void _onSave() {
    if (_selected == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Выберите монету')));
      return;
    }
    if (!_form.currentState!.validate()) return;

    final qty = double.parse(_qtyCtrl.text.replaceAll(',', '.'));
    double? price;

    switch (_type) {
      case TxType.buy:
        price = double.parse(_priceCtrl.text.replaceAll(',', '.'));
        break;
      case TxType.transferIn:
      case TxType.reward:
        switch (_basis) {
          case BasisMethod.zero:
            price = 0;
            break;
          case BasisMethod.fmv:
          case BasisMethod.income:
          case BasisMethod.price:
            if (_priceCtrl.text.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Укажите цену или нажмите “FMV на дату”')));
              return;
            }
            price = double.parse(_priceCtrl.text.replaceAll(',', '.'));
            break;
          case BasisMethod.none:
            price = null;
            break;
        }
        break;
      case TxType.watchOnly:
        price = null; // без кост‑базы
        break;
      case TxType.sell:
        price = null; // не требуется для нереализованного P&L
        break;
    }

    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final tx = PortfolioTx(
      id: id,
      coinId: _selected!.id,
      symbol: _selected!.symbol,
      name: _selected!.name,
      quantity: qty,
      type: _type,
      basis: (_type == TxType.buy) ? BasisMethod.price : (_type == TxType.sell ? BasisMethod.none : _basis),
      price: price,
      date: _date,
      note: null,
    );

    Navigator.of(context).pop(tx);
  }

  @override
  Widget build(BuildContext context) {
    final priceNeeded = _type == TxType.buy ||
        (_type == TxType.transferIn &&
            (_basis == BasisMethod.fmv || _basis == BasisMethod.income || _basis == BasisMethod.price)) ||
        (_type == TxType.reward && (_basis == BasisMethod.fmv || _basis == BasisMethod.income || _basis == BasisMethod.price));

    final showDate = _type == TxType.transferIn || _type == TxType.reward;

    return Scaffold(
      appBar: fluidAppBar(context, title: 'Добавить транзакцию'),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Form(
          key: _form,
          child: ListView(
            children: [
              const StrictHeader(
                title: 'Новая транзакция',
                subtitle: 'Добавьте актив и параметры учёта',
                margin: EdgeInsets.zero,
              ),
              const SizedBox(height: 12),

              // Поиск/выбор монеты
              TextFormField(
                decoration: const InputDecoration(labelText: 'Монета (поиск по имени/символу)'),
                onChanged: (q) {
                  final qq = q.trim().toLowerCase();
                  setState(() {
                    _filtered = _coins.where((c) => c.name.toLowerCase().contains(qq) || c.symbol.toLowerCase().contains(qq)).toList();
                  });
                },
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 160,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListView.builder(
                    itemCount: _filtered.length,
                    itemBuilder: (_, i) {
                      final c = _filtered[i];
                      final selected = _selected?.id == c.id;
                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(backgroundImage: NetworkImage(c.logoUrl), onBackgroundImageError: (_, __) {}),
                        title: Text('${c.name} (${c.symbol})', maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: selected ? const Icon(Icons.check_circle, color: Color(0xFF16A34A)) : null,
                        onTap: () => setState(() => _selected = c),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),

              DropdownButtonFormField<TxType>(
                value: _type,
                decoration: const InputDecoration(labelText: 'Тип операции'),
                items: const [
                  DropdownMenuItem(value: TxType.buy, child: Text('Buy (Покупка)')),
                  DropdownMenuItem(value: TxType.sell, child: Text('Sell (Продажа)')),
                  DropdownMenuItem(value: TxType.transferIn, child: Text('Transfer In (Ввод/Перевод)')),
                  DropdownMenuItem(value: TxType.reward, child: Text('Reward / Airdrop (Награда)')),
                  DropdownMenuItem(value: TxType.watchOnly, child: Text('Watch‑only (без цены покупки)')),
                ],
                onChanged: (v) => setState(() => _type = v!),
              ),
              const SizedBox(height: 12),

              if (_type == TxType.transferIn || _type == TxType.reward)
                DropdownButtonFormField<BasisMethod>(
                  value: _basis,
                  decoration: const InputDecoration(labelText: 'Кост‑база'),
                  items: const [
                    DropdownMenuItem(value: BasisMethod.zero, child: Text('Zero Cost Basis (0)')),
                    DropdownMenuItem(value: BasisMethod.fmv, child: Text('FMV (рыночная цена на дату)')),
                    DropdownMenuItem(value: BasisMethod.income, child: Text('Received as Income (как доход)')),
                    DropdownMenuItem(value: BasisMethod.price, child: Text('Ввести цену вручную')),
                    DropdownMenuItem(value: BasisMethod.none, child: Text('Без кост‑базы (как watch‑only)')),
                  ],
                  onChanged: (v) => setState(() => _basis = v!),
                ),

              const SizedBox(height: 12),

              TextFormField(
                controller: _qtyCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Количество'),
                validator: (v) {
                  final n = double.tryParse((v ?? '').replaceAll(',', '.')) ?? 0;
                  if (n <= 0) return 'Введите количество > 0';
                  return null;
                },
              ),
              const SizedBox(height: 12),

              if (priceNeeded)
                TextFormField(
                  controller: _priceCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Цена за 1 (USD)'),
                ),

              if (showDate) const SizedBox(height: 12),
              if (showDate)
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _dateCtrl,
                        readOnly: true,
                        decoration: const InputDecoration(labelText: 'Дата операции'),
                        onTap: _pickDate,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_basis == BasisMethod.fmv || _basis == BasisMethod.income)
                      Flexible(
                        child: FilledButton.icon(
                          onPressed: _fetchingFmv ? null : _fillFmv,
                          icon: _fetchingFmv
                              ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.auto_awesome),
                          label: const Text('FMV'),
                        ),
                      ),
                  ],
                ),

              const SizedBox(height: 20),
              FilledButton.icon(onPressed: _onSave, icon: const Icon(Icons.check), label: const Text('Сохранить')),
            ],
          ),
        ),
      ),
    );
  }
}
