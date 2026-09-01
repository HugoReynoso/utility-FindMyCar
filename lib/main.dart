import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FindMyCarApp());
}

class FindMyCarApp extends StatefulWidget {
  const FindMyCarApp({super.key});

  @override
  State<FindMyCarApp> createState() => _FindMyCarAppState();
}

class _FindMyCarAppState extends State<FindMyCarApp> {
  final _repository = ParkingRepository();
  Locale? _locale;
  Color _seedColor = AppPalette.colors.first.color;
  ThemeMode _themeMode = ThemeMode.system;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final languageCode = await _repository.loadLanguageCode();
    final colorValue = await _repository.loadThemeColor();
    final themeModeName = await _repository.loadThemeMode();
    if (!mounted) return;
    setState(() {
      _locale = languageCode == null ? null : Locale(languageCode);
      _seedColor = Color(colorValue ?? AppPalette.colors.first.color.toARGB32());
      _themeMode = themeModeFromName(themeModeName);
      _ready = true;
    });
  }

  Future<void> _changeLocale(Locale? locale) async {
    await _repository.saveLanguageCode(locale?.languageCode);
    if (!mounted) return;
    setState(() => _locale = locale);
  }

  Future<void> _changeColor(Color color) async {
    await _repository.saveThemeColor(color.toARGB32());
    if (!mounted) return;
    setState(() => _seedColor = color);
  }

  Future<void> _changeThemeMode(ThemeMode mode) async {
    await _repository.saveThemeMode(mode.name);
    if (!mounted) return;
    setState(() => _themeMode = mode);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    return MaterialApp(
      key: ValueKey(
        'app-${_locale?.languageCode ?? 'system'}-${_seedColor.toARGB32()}',
      ),
      debugShowCheckedModeBanner: false,
      title: 'FindMyCar',
      locale: _locale,
      supportedLocales: AppText.supportedLocales,
      localizationsDelegates: const [
        AppText.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      localeResolutionCallback: (locale, supportedLocales) {
        if (_locale != null) return _locale;
        if (locale == null) return const Locale('it');
        return supportedLocales.firstWhere(
          (supported) => supported.languageCode == locale.languageCode,
          orElse: () => const Locale('it'),
        );
      },
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seedColor,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xfff7f7f4),
        navigationBarTheme: NavigationBarThemeData(
          labelTextStyle: WidgetStateProperty.all(
            const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seedColor,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xff101412),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      themeMode: _themeMode,
      home: HomeScreen(
        repository: _repository,
        onLocaleChanged: _changeLocale,
        onColorChanged: _changeColor,
        onThemeModeChanged: _changeThemeMode,
        seedColor: _seedColor,
        themeMode: _themeMode,
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    required this.repository,
    required this.onLocaleChanged,
    required this.onColorChanged,
    required this.onThemeModeChanged,
    required this.seedColor,
    required this.themeMode,
    super.key,
  });

  final ParkingRepository repository;
  final Future<void> Function(Locale?) onLocaleChanged;
  final Future<void> Function(Color) onColorChanged;
  final Future<void> Function(ThemeMode) onThemeModeChanged;
  final Color seedColor;
  final ThemeMode themeMode;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _locationService = AccurateLocationService();
  final _imagePicker = ImagePicker();

  List<ParkingSpot> _spots = [];
  Position? _currentPosition;
  bool _loading = true;
  bool _saving = false;
  bool _finding = false;
  bool _sharing = false;
  String? _errorKey;
  int _selectedIndex = 0;

  ParkingSpot? get _latestSpot => _spots.isEmpty ? null : _spots.first;
  List<ParkingSpot> get _favoriteSpots {
    return _spots.where((spot) => spot.favorite).toList();
  }

  @override
  void initState() {
    super.initState();
    _loadSpots();
  }

  Future<void> _loadSpots() async {
    final spots = await widget.repository.loadSpots();
    if (!mounted) return;
    setState(() {
      _spots = spots;
      _loading = false;
    });
  }

  Future<void> _saveCurrentPosition() async {
    final text = AppText.of(context);
    setState(() {
      _saving = true;
      _errorKey = null;
    });

    try {
      final position = await _locationService.getBestPosition();
      var spot = ParkingSpot(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
        savedAt: DateTime.now(),
      );
      await widget.repository.upsertSpot(spot);
      await _loadSpots();
      if (!mounted) return;
      setState(() => _currentPosition = position);
      _showSnack(text.positionSaved);

      final updatedSpot = await _showSaveDetailsSheet(spot);
      if (updatedSpot != null) {
        spot = updatedSpot;
        await widget.repository.upsertSpot(spot);
        await _loadSpots();
      }
    } on LocationFailure catch (failure) {
      if (mounted) setState(() => _errorKey = failure.messageKey);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<ParkingSpot?> _showSaveDetailsSheet(ParkingSpot spot) {
    return showModalBottomSheet<ParkingSpot>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _SaveDetailsSheet(
        initialSpot: spot,
        imagePicker: _imagePicker,
      ),
    );
  }

  Future<void> _openFinder() async {
    final spot = _latestSpot;
    if (spot == null) {
      setState(() => _errorKey = 'noSavedLocation');
      return;
    }

    setState(() => _finding = true);
    Position? currentPosition = _currentPosition;
    try {
      currentPosition = await _locationService.getCurrentPosition(
        requestPermission: false,
      );
      if (mounted) setState(() => _currentPosition = currentPosition);
    } on LocationFailure {
      currentPosition = null;
    } finally {
      if (mounted) setState(() => _finding = false);
    }

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => FinderMapScreen(
          spot: spot,
          currentPosition: currentPosition,
          onOpenGoogleMaps: () => _openGoogleMaps(spot),
        ),
      ),
    );
  }

  Future<void> _openGoogleMaps(ParkingSpot spot) async {
    final uri = _mapsUri(spot);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) setState(() => _errorKey = 'mapsError');
    }
  }

  Future<void> _shareSpot(ParkingSpot spot) async {
    final text = AppText.of(context);
    final shareText = '${text.shareMessage}\n${_mapsUri(spot)}';
    setState(() => _sharing = true);
    try {
      await SharePlus.instance.share(
        ShareParams(
          title: 'FindMyCar',
          text: shareText,
        ),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _toggleFavorite(ParkingSpot spot) async {
    await widget.repository.upsertSpot(
      spot.copyWith(favorite: !spot.favorite),
    );
    await _loadSpots();
  }

  Uri _mapsUri(ParkingSpot spot) {
    return Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination='
      '${spot.latitude},${spot.longitude}&travelmode=walking',
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final latestSpot = _latestSpot;

    return Scaffold(
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) => setState(() => _selectedIndex = index),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: text.home,
          ),
          NavigationDestination(
            icon: const Icon(Icons.history),
            selectedIcon: const Icon(Icons.history),
            label: text.history,
          ),
          NavigationDestination(
            icon: const Icon(Icons.star_border),
            selectedIcon: const Icon(Icons.star),
            label: text.favorites,
          ),
          NavigationDestination(
            icon: const Icon(Icons.ios_share),
            selectedIcon: const Icon(Icons.ios_share),
            label: text.share,
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: text.settings,
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : IndexedStack(
                index: _selectedIndex,
                children: [
                  HomeTab(
                    latestSpot: latestSpot,
                    saving: _saving,
                    finding: _finding,
                    errorKey: _errorKey,
                    onLocaleChanged: widget.onLocaleChanged,
                    onSave: _saveCurrentPosition,
                    onFind: _openFinder,
                  ),
                  HistoryTab(
                    spots: _spots,
                    onFavorite: _toggleFavorite,
                    onOpen: (spot) => _openGoogleMaps(spot),
                  ),
                  FavoritesTab(
                    spots: _favoriteSpots,
                    onFavorite: _toggleFavorite,
                    onOpen: (spot) => _openGoogleMaps(spot),
                  ),
                  ShareTab(
                    spot: latestSpot,
                    sharing: _sharing,
                    onShare: latestSpot == null
                        ? null
                        : () => _shareSpot(latestSpot),
                  ),
                  SettingsTab(
                    seedColor: widget.seedColor,
                    themeMode: widget.themeMode,
                    onLocaleChanged: widget.onLocaleChanged,
                    onColorChanged: widget.onColorChanged,
                    onThemeModeChanged: widget.onThemeModeChanged,
                  ),
                ],
              ),
      ),
    );
  }
}

class HomeTab extends StatelessWidget {
  const HomeTab({
    required this.latestSpot,
    required this.saving,
    required this.finding,
    required this.errorKey,
    required this.onLocaleChanged,
    required this.onSave,
    required this.onFind,
    super.key,
  });

  final ParkingSpot? latestSpot;
  final bool saving;
  final bool finding;
  final String? errorKey;
  final Future<void> Function(Locale?) onLocaleChanged;
  final VoidCallback onSave;
  final VoidCallback onFind;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Theme.of(context).colorScheme.primary.withValues(alpha: 0.22),
            Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.28),
            Theme.of(context).scaffoldBackgroundColor,
          ],
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        children: [
          _AppHeader(onLocaleChanged: onLocaleChanged),
          const SizedBox(height: 18),
          const _AdSlotPlaceholder(),
          const SizedBox(height: 18),
          _HeroActionCard(
            title: text.savePosition,
            subtitle: text.savePositionHint,
            icon: Icons.add_location_alt,
            color: Theme.of(context).colorScheme.primary,
            busy: saving,
            busyText: text.savingShort,
            onTap: saving ? null : onSave,
          ),
          const SizedBox(height: 14),
          _HeroActionCard(
            title: text.findMyCar,
            subtitle: latestSpot == null ? text.findDisabled : text.findHint,
            icon: Icons.near_me,
            color: const Color(0xff2563eb),
            busy: finding,
            busyText: text.loadingMap,
            onTap: finding ? null : onFind,
          ),
          if (errorKey != null) ...[
            const SizedBox(height: 16),
            _ErrorBanner(message: text.value(errorKey!)),
          ],
        ],
      ),
    );
  }
}

class _AdSlotPlaceholder extends StatelessWidget {
  const _AdSlotPlaceholder();

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    return Container(
      height: 72,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.16),
        ),
      ),
      child: Text(
        text.advertising,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

class _AppHeader extends StatelessWidget {
  const _AppHeader({required this.onLocaleChanged});

  final Future<void> Function(Locale?) onLocaleChanged;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    return Row(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.directions_car, color: Colors.white),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'FindMyCar',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              Text(
                text.tagline,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.black54,
                    ),
              ),
            ],
          ),
        ),
        _LanguageMenu(onLocaleChanged: onLocaleChanged),
      ],
    );
  }
}

class _LanguageMenu extends StatefulWidget {
  const _LanguageMenu({required this.onLocaleChanged});

  final Future<void> Function(Locale?) onLocaleChanged;

  @override
  State<_LanguageMenu> createState() => _LanguageMenuState();
}

class _LanguageMenuState extends State<_LanguageMenu> {
  bool _loading = false;

  Future<void> _select(Locale? locale) async {
    setState(() => _loading = true);
    _showLanguageLoadingOverlay(context);
    await widget.onLocaleChanged(locale);
    if (!mounted) return;
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: _loading ? 0.55 : 1,
      child: PopupMenuButton<Locale?>(
        tooltip: text.language,
        icon: const Icon(Icons.language),
        enabled: !_loading,
        onSelected: _select,
        itemBuilder: (context) => [
          PopupMenuItem(value: null, child: Text(text.systemLanguage)),
          ...AppText.languageOptions.map(
            (option) => PopupMenuItem(
              value: option.locale,
              child: Text(option.label),
            ),
          ),
        ],
      ),
    );
  }
}

void _showLanguageLoadingOverlay(BuildContext context) {
  final text = AppText.of(context);
  showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.10),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (context, animation, secondaryAnimation) {
      Future<void>.delayed(const Duration(milliseconds: 520), () {
        if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      });

      return Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 230,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(22),
              boxShadow: const [
                BoxShadow(
                  blurRadius: 28,
                  color: Colors.black26,
                  offset: Offset(0, 14),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.translate,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  text.changingLanguage,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: const LinearProgressIndicator(minHeight: 4),
                ),
              ],
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          ),
          child: child,
        ),
      );
    },
  );
}

class _HeroActionCard extends StatelessWidget {
  const _HeroActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
    this.busy = false,
    this.busyText,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final bool busy;
  final String? busyText;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      duration: const Duration(milliseconds: 180),
      scale: busy ? 0.985 : 1,
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            constraints: const BoxConstraints(minHeight: 172),
            padding: const EdgeInsets.all(20),
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: busy
                        ? const Padding(
                            padding: EdgeInsets.all(16),
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 3,
                            ),
                          )
                        : Icon(icon, color: Colors.white, size: 32),
                  ),
                  const Spacer(),
                  const Icon(Icons.chevron_right, color: Colors.white, size: 34),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.84),
                          height: 1.25,
                        ),
                  ),
                  if (busy && busyText != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          busyText!,
                          style:
                              Theme.of(context).textTheme.labelLarge?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SaveDetailsSheet extends StatefulWidget {
  const _SaveDetailsSheet({
    required this.initialSpot,
    required this.imagePicker,
  });

  final ParkingSpot initialSpot;
  final ImagePicker imagePicker;

  @override
  State<_SaveDetailsSheet> createState() => _SaveDetailsSheetState();
}

class _SaveDetailsSheetState extends State<_SaveDetailsSheet> {
  late final TextEditingController _noteController;
  late bool _favorite;
  String? _photoPath;
  bool _photoLoading = false;

  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController(text: widget.initialSpot.note);
    _favorite = widget.initialSpot.favorite;
    _photoPath = widget.initialSpot.photoPath;
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _takePhoto() async {
    setState(() => _photoLoading = true);
    try {
      final image = await widget.imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1800,
      );
      if (image == null) return;

      final directory = await getApplicationDocumentsDirectory();
      final target = File(
        '${directory.path}/parking_${widget.initialSpot.id}.jpg',
      );
      await File(image.path).copy(target.path);
      if (!mounted) return;
      setState(() => _photoPath = target.path);
    } finally {
      if (mounted) setState(() => _photoLoading = false);
    }
  }

  void _save() {
    Navigator.of(context).pop(
      widget.initialSpot.copyWith(
        note: _noteController.text.trim(),
        photoPath: _photoPath,
        favorite: _favorite,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text.savedDetailsTitle,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              text.savedDetailsSubtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.black54,
                  ),
            ),
            const SizedBox(height: 16),
            _InfoPanel(
              icon: Icons.gps_fixed,
              title: text.savedPositionData,
              body:
                  '${text.accuracy}: ${text.meters(widget.initialSpot.accuracyMeters.round())}\n'
                  'Lat ${widget.initialSpot.latitude.toStringAsFixed(6)}  Long ${widget.initialSpot.longitude.toStringAsFixed(6)}',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: text.note,
                hintText: text.noteHint,
                prefixIcon: const Icon(Icons.notes),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _photoLoading ? null : _takePhoto,
                    icon: _photoLoading
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.photo_camera),
                    label: Text(text.addPhoto),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilterChip(
                    selected: _favorite,
                    avatar: const Icon(Icons.star, size: 18),
                    label: Text(text.favorite),
                    onSelected: (value) => setState(() => _favorite = value),
                  ),
                ),
              ],
            ),
            if (_photoPath != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.file(
                  File(_photoPath!),
                  height: 150,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.check),
                label: Text(text.done),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FinderMapScreen extends StatelessWidget {
  const FinderMapScreen({
    required this.spot,
    required this.currentPosition,
    required this.onOpenGoogleMaps,
    super.key,
  });

  final ParkingSpot spot;
  final Position? currentPosition;
  final VoidCallback onOpenGoogleMaps;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final carPoint = LatLng(spot.latitude, spot.longitude);
    final current = currentPosition == null
        ? null
        : LatLng(currentPosition!.latitude, currentPosition!.longitude);
    final distance = current == null
        ? null
        : Geolocator.distanceBetween(
            current.latitude,
            current.longitude,
            spot.latitude,
            spot.longitude,
          );

    return Scaffold(
      appBar: AppBar(title: Text(text.findMyCar)),
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: carPoint,
              initialZoom: 17,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.reynosostudios.findmycar',
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: carPoint,
                    width: 76,
                    height: 66,
                    child: _MapPin(
                      icon: Icons.directions_car,
                      label: text.car,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  if (current != null)
                    Marker(
                      point: current,
                      width: 76,
                      height: 66,
                      child: const _MapPin(
                        icon: Icons.person_pin_circle,
                        label: 'Io',
                        color: Color(0xff2563eb),
                      ),
                    ),
                ],
              ),
            ],
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: _MapBottomPanel(
              spot: spot,
              distance: distance,
              onOpenGoogleMaps: onOpenGoogleMaps,
            ),
          ),
        ],
      ),
    );
  }
}

class _MapPin extends StatelessWidget {
  const _MapPin({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: const [
              BoxShadow(
                blurRadius: 12,
                color: Colors.black26,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(icon, color: Colors.white),
          ),
        ),
        const SizedBox(height: 3),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
            boxShadow: const [
              BoxShadow(
                blurRadius: 8,
                color: Colors.black12,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

class _MapBottomPanel extends StatelessWidget {
  const _MapBottomPanel({
    required this.spot,
    required this.distance,
    required this.onOpenGoogleMaps,
  });

  final ParkingSpot spot;
  final double? distance;
  final VoidCallback onOpenGoogleMaps;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            blurRadius: 22,
            color: Colors.black26,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            distance == null
                ? text.currentPositionUnavailable
                : '${text.distance}: ${formatDistance(distance!, text)}',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onOpenGoogleMaps,
                  icon: const Icon(Icons.map),
                  label: Text(text.openGoogleMaps),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => showSpotDetails(context, spot),
                  icon: const Icon(Icons.notes),
                  label: Text(text.notePhoto),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class HistoryTab extends StatelessWidget {
  const HistoryTab({
    required this.spots,
    required this.onFavorite,
    required this.onOpen,
    super.key,
  });

  final List<ParkingSpot> spots;
  final ValueChanged<ParkingSpot> onFavorite;
  final ValueChanged<ParkingSpot> onOpen;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    return _ListScaffold(
      title: text.history,
      emptyText: text.historyEmpty,
      spots: spots,
      onFavorite: onFavorite,
      onOpen: onOpen,
    );
  }
}

class FavoritesTab extends StatelessWidget {
  const FavoritesTab({
    required this.spots,
    required this.onFavorite,
    required this.onOpen,
    super.key,
  });

  final List<ParkingSpot> spots;
  final ValueChanged<ParkingSpot> onFavorite;
  final ValueChanged<ParkingSpot> onOpen;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    return _ListScaffold(
      title: text.favorites,
      emptyText: text.favoritesEmpty,
      spots: spots,
      onFavorite: onFavorite,
      onOpen: onOpen,
    );
  }
}

class _ListScaffold extends StatelessWidget {
  const _ListScaffold({
    required this.title,
    required this.emptyText,
    required this.spots,
    required this.onFavorite,
    required this.onOpen,
  });

  final String title;
  final String emptyText;
  final List<ParkingSpot> spots;
  final ValueChanged<ParkingSpot> onFavorite;
  final ValueChanged<ParkingSpot> onOpen;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: 14),
        if (spots.isEmpty)
          _EmptyState(message: emptyText)
        else
          ...spots.map(
            (spot) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ParkingSpotTile(
                spot: spot,
                onFavorite: () => onFavorite(spot),
                onOpen: () => onOpen(spot),
              ),
            ),
          ),
      ],
    );
  }
}

class ParkingSpotTile extends StatelessWidget {
  const ParkingSpotTile({
    required this.spot,
    required this.onFavorite,
    required this.onOpen,
    super.key,
  });

  final ParkingSpot spot;
  final VoidCallback onFavorite;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => showSpotDetails(context, spot),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.local_parking,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatDate(context, spot.savedAt),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${text.accuracy}: ${text.meters(spot.accuracyMeters.round())}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.black54,
                          ),
                    ),
                    if (spot.note.isNotEmpty)
                      Text(
                        spot.note,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: text.favorite,
                onPressed: onFavorite,
                icon: Icon(spot.favorite ? Icons.star : Icons.star_border),
              ),
              IconButton(
                tooltip: text.openGoogleMaps,
                onPressed: onOpen,
                icon: const Icon(Icons.map),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ShareTab extends StatelessWidget {
  const ShareTab({
    required this.spot,
    required this.sharing,
    required this.onShare,
    super.key,
  });

  final ParkingSpot? spot;
  final bool sharing;
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
      children: [
        Text(
          text.share,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: 14),
        _InfoPanel(
          icon: Icons.ios_share,
          title: text.shareLastPosition,
          body: spot == null ? text.noSavedLocation : text.shareHint,
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: sharing ? null : onShare,
          icon: sharing
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send),
          label: Text(text.shareWithApps),
        ),
      ],
    );
  }
}

class SettingsTab extends StatefulWidget {
  const SettingsTab({
    required this.seedColor,
    required this.themeMode,
    required this.onLocaleChanged,
    required this.onColorChanged,
    required this.onThemeModeChanged,
    super.key,
  });

  final Color seedColor;
  final ThemeMode themeMode;
  final Future<void> Function(Locale?) onLocaleChanged;
  final Future<void> Function(Color) onColorChanged;
  final Future<void> Function(ThemeMode) onThemeModeChanged;

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  bool _languageLoading = false;
  bool _colorLoading = false;
  bool _themeLoading = false;

  Future<void> _changeLanguage(Locale? locale) async {
    setState(() => _languageLoading = true);
    _showLanguageLoadingOverlay(context);
    await widget.onLocaleChanged(locale);
    if (!mounted) return;
    setState(() => _languageLoading = false);
  }

  Future<void> _changeColor(Color color) async {
    setState(() => _colorLoading = true);
    await widget.onColorChanged(color);
    if (!mounted) return;
    setState(() => _colorLoading = false);
  }

  Future<void> _changeTheme(ThemeMode mode) async {
    setState(() => _themeLoading = true);
    await widget.onThemeModeChanged(mode);
    if (!mounted) return;
    setState(() => _themeLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
      children: [
        Text(
          text.settings,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: 14),
        _InfoPanel(
          icon: Icons.language,
          title: text.language,
          body: text.languageAutoHint,
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ActionChip(
              avatar: const Icon(Icons.phone_android, size: 18),
              label: Text(text.systemLanguage),
              onPressed: _languageLoading ? null : () => _changeLanguage(null),
            ),
            ...AppText.languageOptions.map(
              (option) => ActionChip(
                label: Text(option.label),
                onPressed:
                    _languageLoading ? null : () => _changeLanguage(option.locale),
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        _InfoPanel(
          icon: Icons.contrast,
          title: text.appearance,
          body: _themeLoading ? text.applyingChange : text.appearanceHint,
        ),
        const SizedBox(height: 10),
        SegmentedButton<ThemeMode>(
          segments: [
            ButtonSegment(
              value: ThemeMode.system,
              icon: const Icon(Icons.phone_android),
              label: Text(text.systemTheme),
            ),
            ButtonSegment(
              value: ThemeMode.light,
              icon: const Icon(Icons.light_mode),
              label: Text(text.lightTheme),
            ),
            ButtonSegment(
              value: ThemeMode.dark,
              icon: const Icon(Icons.dark_mode),
              label: Text(text.darkTheme),
            ),
          ],
          selected: {widget.themeMode},
          onSelectionChanged: _themeLoading
              ? null
              : (selection) => _changeTheme(selection.first),
        ),
        const SizedBox(height: 22),
        _InfoPanel(
          icon: Icons.palette,
          title: text.colors,
          body: _colorLoading ? text.applyingChange : text.colorsHint,
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: AppPalette.colors.map(
            (option) {
              final selected =
                  option.color.toARGB32() == widget.seedColor.toARGB32();
              return InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: _colorLoading ? null : () => _changeColor(option.color),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: option.color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      width: selected ? 4 : 2,
                      color: selected ? Colors.black87 : Colors.white,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        blurRadius: 10,
                        color: Colors.black12,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                ),
              );
            },
          ).toList(),
        ),
        const SizedBox(height: 26),
        Center(
          child: Text(
            text.createdBy,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
      ],
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.black54,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xfffff1f2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xfffecdd3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber, color: Color(0xffbe123c)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xff881337),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void showSpotDetails(BuildContext context, ParkingSpot spot) {
  final text = AppText.of(context);
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text.notePhoto,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 12),
            _InfoPanel(
              icon: Icons.schedule,
              title: text.savedAt,
              body: formatDate(context, spot.savedAt),
            ),
            const SizedBox(height: 10),
            _InfoPanel(
              icon: Icons.gps_fixed,
              title: text.accuracy,
              body:
                  '${text.meters(spot.accuracyMeters.round())}\n'
                  'Lat ${spot.latitude.toStringAsFixed(6)}  Long ${spot.longitude.toStringAsFixed(6)}',
            ),
            if (spot.note.isEmpty && spot.photoPath == null) ...[
              const SizedBox(height: 10),
              _InfoPanel(
                icon: Icons.info_outline,
                title: text.noDetailsTitle,
                body: text.noDetailsBody,
              ),
            ],
            if (spot.note.isNotEmpty) ...[
              const SizedBox(height: 10),
              _InfoPanel(
                icon: Icons.notes,
                title: text.note,
                body: spot.note,
              ),
            ],
            if (spot.photoPath != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: File(spot.photoPath!).existsSync()
                    ? Image.file(
                        File(spot.photoPath!),
                        height: 220,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      )
                    : _EmptyState(message: text.photoUnavailable),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class AccurateLocationService {
  Future<Position> getBestPosition() async {
    await _ensureServiceEnabled();
    await _ensurePermission(requestIfNeeded: true);

    Position? best;
    final deadline = DateTime.now().add(const Duration(seconds: 12));

    while (DateTime.now().isBefore(deadline)) {
      final position = await _readHighAccuracyPosition();
      if (best == null || position.accuracy < best.accuracy) {
        best = position;
      }
      if (position.accuracy <= 8) break;
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }

    return best!;
  }

  Future<Position> getCurrentPosition({required bool requestPermission}) async {
    await _ensureServiceEnabled();
    await _ensurePermission(requestIfNeeded: requestPermission);
    return _readHighAccuracyPosition();
  }

  Future<Position> _readHighAccuracyPosition() {
    return Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.bestForNavigation,
      timeLimit: const Duration(seconds: 12),
    );
  }

  Future<void> _ensureServiceEnabled() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationFailure('gpsOff');
    }
  }

  Future<void> _ensurePermission({required bool requestIfNeeded}) async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied && requestIfNeeded) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const LocationFailure('permissionDenied');
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationFailure('permissionDeniedForever');
    }
  }
}

class LocationFailure implements Exception {
  const LocationFailure(this.messageKey);

  final String messageKey;
}

class ParkingRepository {
  ParkingRepository() : _prefs = SharedPreferencesAsync();

  static const _spotsKey = 'findmycar.spots';
  static const _languageKey = 'findmycar.language';
  static const _themeColorKey = 'findmycar.theme_color';
  static const _themeModeKey = 'findmycar.theme_mode';
  final SharedPreferencesAsync _prefs;

  Future<List<ParkingSpot>> loadSpots() async {
    final value = await _prefs.getString(_spotsKey);
    if (value == null) return [];

    try {
      final decoded = jsonDecode(value);
      if (decoded is! List) return [];
      final spots = decoded
          .whereType<Map>()
          .map((item) => ParkingSpot.fromMap(Map<String, Object?>.from(item)))
          .toList()
        ..sort((a, b) => b.savedAt.compareTo(a.savedAt));
      return spots;
    } on Object {
      return [];
    }
  }

  Future<void> upsertSpot(ParkingSpot spot) async {
    final spots = await loadSpots();
    final next = [
      spot,
      ...spots.where((item) => item.id != spot.id),
    ]..sort((a, b) => b.savedAt.compareTo(a.savedAt));

    await _prefs.setString(
      _spotsKey,
      jsonEncode(next.map((item) => item.toMap()).toList()),
    );
  }

  Future<String?> loadLanguageCode() => _prefs.getString(_languageKey);

  Future<void> saveLanguageCode(String? languageCode) async {
    if (languageCode == null) {
      await _prefs.remove(_languageKey);
    } else {
      await _prefs.setString(_languageKey, languageCode);
    }
  }

  Future<int?> loadThemeColor() => _prefs.getInt(_themeColorKey);

  Future<void> saveThemeColor(int colorValue) {
    return _prefs.setInt(_themeColorKey, colorValue);
  }

  Future<String?> loadThemeMode() => _prefs.getString(_themeModeKey);

  Future<void> saveThemeMode(String mode) {
    return _prefs.setString(_themeModeKey, mode);
  }
}

ThemeMode themeModeFromName(String? name) {
  return switch (name) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
}

class ParkingSpot {
  const ParkingSpot({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.savedAt,
    this.note = '',
    this.photoPath,
    this.favorite = false,
  });

  final String id;
  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final DateTime savedAt;
  final String note;
  final String? photoPath;
  final bool favorite;

  ParkingSpot copyWith({
    String? note,
    String? photoPath,
    bool? favorite,
  }) {
    return ParkingSpot(
      id: id,
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: accuracyMeters,
      savedAt: savedAt,
      note: note ?? this.note,
      photoPath: photoPath ?? this.photoPath,
      favorite: favorite ?? this.favorite,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'latitude': latitude,
      'longitude': longitude,
      'accuracy_meters': accuracyMeters,
      'saved_at': savedAt.toIso8601String(),
      'note': note,
      'photo_path': photoPath,
      'favorite': favorite,
    };
  }

  factory ParkingSpot.fromMap(Map<String, Object?> map) {
    return ParkingSpot(
      id: map['id'] as String,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      accuracyMeters: (map['accuracy_meters'] as num).toDouble(),
      savedAt: DateTime.parse(map['saved_at'] as String),
      note: (map['note'] as String?) ?? '',
      photoPath: map['photo_path'] as String?,
      favorite: (map['favorite'] as bool?) ?? false,
    );
  }
}

String formatDate(BuildContext context, DateTime dateTime) {
  final localizations = MaterialLocalizations.of(context);
  final date = localizations.formatMediumDate(dateTime);
  final time = localizations.formatTimeOfDay(
    TimeOfDay.fromDateTime(dateTime),
  );
  return '$date $time';
}

String formatDistance(double meters, AppText text) {
  if (meters >= 1000) {
    final km = meters / 1000;
    return text.kilometers(km.toStringAsFixed(km >= 10 ? 1 : 2));
  }
  return text.meters(math.max(1, meters.round()));
}

class AppPalette {
  static const colors = [
    AppColorOption('Teal', Color(0xff0f766e)),
    AppColorOption('Blue', Color(0xff2563eb)),
    AppColorOption('Green', Color(0xff16a34a)),
    AppColorOption('Rose', Color(0xffe11d48)),
    AppColorOption('Violet', Color(0xff7c3aed)),
    AppColorOption('Graphite', Color(0xff374151)),
  ];
}

class AppColorOption {
  const AppColorOption(this.label, this.color);

  final String label;
  final Color color;
}

class AppText {
  AppText(this.locale);

  final Locale locale;

  static const supportedLocales = [
    Locale('it'),
    Locale('en'),
    Locale('es'),
    Locale('zh'),
    Locale('fr'),
    Locale('de'),
    Locale('ar'),
  ];

  static const languageOptions = [
    LanguageOption(Locale('it'), 'Italiano'),
    LanguageOption(Locale('en'), 'English'),
    LanguageOption(Locale('es'), 'Espanol'),
    LanguageOption(Locale('zh'), 'Chinese'),
    LanguageOption(Locale('fr'), 'Francais'),
    LanguageOption(Locale('de'), 'Deutsch'),
    LanguageOption(Locale('ar'), 'Arabic'),
  ];

  static const delegate = _AppTextDelegate();

  static AppText of(BuildContext context) {
    return Localizations.of<AppText>(context, AppText)!;
  }

  static const _strings = <String, Map<String, String>>{
    'it': {
      'tagline': 'Trovo la mia auto',
      'home': 'Home',
      'history': 'Cronologia',
      'favorites': 'Preferiti',
      'share': 'Condividi',
      'settings': 'Impostazioni',
      'savePosition': 'Memorizza posizione auto',
      'savePositionHint': 'Salva la posizione precisa della tua auto.',
      'findMyCar': 'Trova la mia auto',
      'findHint': 'Apri la mappa interna con auto e posizione attuale.',
      'findDisabled': 'Prima memorizza la posizione della tua auto.',
      'positionSaved': 'Posizione memorizzata.',
      'savingShort': 'Salvando posizione...',
      'savingCarPosition': 'Memorizzazione posizione auto',
      'searchingGps': 'Sto cercando il segnale GPS migliore...',
      'savedDetailsTitle': 'Aggiungi dettagli (opzionale)',
      'savedDetailsSubtitle': 'Puoi aggiungere nota, foto o preferito. Utile nei parcheggi multipiano.',
      'savedPositionData': 'Posizione salvata',
      'note': 'Nota',
      'noteHint': 'Es. Piano B, fila 12, ingresso nord',
      'addPhoto': 'Foto parcheggio',
      'favorite': 'Preferito',
      'done': 'Fatto',
      'distance': 'Distanza',
      'accuracy': 'Precisione',
      'savedAt': 'Salvata il',
      'openGoogleMaps': 'Vai su Google Maps',
      'notePhoto': 'Nota o foto',
      'noDetailsTitle': 'Nessun dettaglio salvato',
      'noDetailsBody': 'Puoi aggiungere una nota o una foto quando memorizzi la posizione.',
      'photoUnavailable': 'Foto non disponibile.',
      'car': 'Auto',
      'currentPositionUnavailable': 'Posizione attuale non disponibile',
      'historyEmpty': 'Le posizioni memorizzate appariranno qui.',
      'favoritesEmpty': 'Segna una posizione come preferita per trovarla qui.',
      'shareLastPosition': 'Invia ultima posizione',
      'shareHint': 'Condividi con WhatsApp, messaggi o altre app.',
      'shareWithApps': 'Condividi con app',
      'shareMessage': 'Ecco dove ho parcheggiato:',
      'language': 'Lingua',
      'systemLanguage': 'Automatico',
      'languageAutoHint': 'L app rileva la lingua del telefono. Puoi cambiarla quando vuoi.',
      'changingLanguage': 'Cambio lingua...',
      'appearance': 'Aspetto',
      'appearanceHint': 'Scegli tema chiaro, scuro o automatico.',
      'systemTheme': 'Sistema',
      'lightTheme': 'Chiaro',
      'darkTheme': 'Scuro',
      'colors': 'Colori',
      'colorsHint': 'Scegli il colore principale dell app.',
      'applyingChange': 'Applicando modifica...',
      'loadingMap': 'Caricando mappa...',
      'createdBy': 'Created by Reynoso Studios',
      'advertising': 'Pubblicità',
      'noSavedLocation': 'Nessuna posizione salvata.',
      'gpsOff': 'GPS disattivato. Attiva i servizi di posizione e riprova.',
      'permissionDenied': 'Permesso posizione negato. Serve per memorizzare la macchina.',
      'permissionDeniedForever': 'Permesso posizione bloccato. Abilitalo dalle impostazioni Android.',
      'mapsError': 'Non riesco ad aprire Google Maps.',
      'meters': '{value} m',
      'kilometers': '{value} km',
    },
    'en': {
      'tagline': 'Find my car',
      'home': 'Home',
      'history': 'History',
      'favorites': 'Favorites',
      'share': 'Share',
      'settings': 'Settings',
      'savePosition': 'Save car location',
      'savePositionHint': 'Save your car position with high GPS accuracy.',
      'findMyCar': 'Find my car',
      'findHint': 'Open the in-app map with your car and current position.',
      'findDisabled': 'Save your car location first.',
      'positionSaved': 'Location saved.',
      'savingShort': 'Saving location...',
      'savingCarPosition': 'Saving car position',
      'searchingGps': 'Looking for the best GPS signal...',
      'savedDetailsTitle': 'Add details (optional)',
      'savedDetailsSubtitle': 'Add a note, photo, or favorite. Helpful in multi-level parking lots.',
      'savedPositionData': 'Saved position',
      'note': 'Note',
      'noteHint': 'E.g. Level B, row 12, north entrance',
      'addPhoto': 'Parking photo',
      'favorite': 'Favorite',
      'done': 'Done',
      'distance': 'Distance',
      'accuracy': 'Accuracy',
      'savedAt': 'Saved at',
      'openGoogleMaps': 'Go to Google Maps',
      'notePhoto': 'Note or photo',
      'noDetailsTitle': 'No details saved',
      'noDetailsBody': 'You can add a note or photo when saving the position.',
      'photoUnavailable': 'Photo unavailable.',
      'car': 'Car',
      'currentPositionUnavailable': 'Current position unavailable',
      'historyEmpty': 'Saved positions will appear here.',
      'favoritesEmpty': 'Mark a position as favorite to see it here.',
      'shareLastPosition': 'Send last position',
      'shareHint': 'Share with WhatsApp, messages, or other apps.',
      'shareWithApps': 'Share with apps',
      'shareMessage': 'Here is where I parked:',
      'language': 'Language',
      'systemLanguage': 'Automatic',
      'languageAutoHint': 'The app detects your phone language. You can change it anytime.',
      'changingLanguage': 'Changing language...',
      'appearance': 'Appearance',
      'appearanceHint': 'Choose light, dark, or automatic theme.',
      'systemTheme': 'System',
      'lightTheme': 'Light',
      'darkTheme': 'Dark',
      'colors': 'Colors',
      'colorsHint': 'Choose the main app color.',
      'applyingChange': 'Applying change...',
      'loadingMap': 'Loading map...',
      'createdBy': 'Created by Reynoso Studios',
      'advertising': 'Advertising',
      'noSavedLocation': 'No saved location.',
      'gpsOff': 'GPS is off. Enable location services and try again.',
      'permissionDenied': 'Location permission denied. It is needed to save your car.',
      'permissionDeniedForever': 'Location permission is blocked. Enable it in Android settings.',
      'mapsError': 'Google Maps could not be opened.',
      'meters': '{value} m',
      'kilometers': '{value} km',
    },
    'es': {
      'tagline': 'Encuentro mi coche',
      'home': 'Inicio',
      'history': 'Historial',
      'favorites': 'Favoritos',
      'share': 'Compartir',
      'settings': 'Ajustes',
      'savePosition': 'Guardar posicion del coche',
      'savePositionHint': 'Guarda la posicion precisa de tu coche.',
      'findMyCar': 'Encontrar mi coche',
      'findHint': 'Abre el mapa interno con tu coche y tu posicion actual.',
      'findDisabled': 'Primero guarda la posicion de tu coche.',
      'positionSaved': 'Posicion guardada.',
      'savingShort': 'Guardando posicion...',
      'savingCarPosition': 'Guardando posicion del coche',
      'searchingGps': 'Buscando la mejor senal GPS...',
      'savedDetailsTitle': 'Agregar detalles (opcional)',
      'savedDetailsSubtitle': 'Puedes agregar nota, foto o favorito. Util en parkings de varios pisos.',
      'savedPositionData': 'Posicion guardada',
      'note': 'Nota',
      'noteHint': 'Ej. Planta B, fila 12, entrada norte',
      'addPhoto': 'Foto del parking',
      'favorite': 'Favorito',
      'done': 'Listo',
      'distance': 'Distancia',
      'accuracy': 'Precision',
      'savedAt': 'Guardado el',
      'openGoogleMaps': 'Ir a Google Maps',
      'notePhoto': 'Nota o foto',
      'noDetailsTitle': 'No hay detalles guardados',
      'noDetailsBody': 'Puedes agregar una nota o foto al guardar la posicion.',
      'photoUnavailable': 'Foto no disponible.',
      'car': 'Coche',
      'currentPositionUnavailable': 'Posicion actual no disponible',
      'historyEmpty': 'Las posiciones guardadas apareceran aqui.',
      'favoritesEmpty': 'Marca una posicion como favorita para verla aqui.',
      'shareLastPosition': 'Enviar ultima posicion',
      'shareHint': 'Comparte con WhatsApp, mensajes u otras apps.',
      'shareWithApps': 'Compartir con apps',
      'shareMessage': 'Aqui aparque:',
      'language': 'Idioma',
      'systemLanguage': 'Automatico',
      'languageAutoHint': 'La app detecta el idioma del telefono. Puedes cambiarlo cuando quieras.',
      'changingLanguage': 'Cambiando idioma...',
      'appearance': 'Apariencia',
      'appearanceHint': 'Elige tema claro, oscuro o automatico.',
      'systemTheme': 'Sistema',
      'lightTheme': 'Claro',
      'darkTheme': 'Oscuro',
      'colors': 'Colores',
      'colorsHint': 'Elige el color principal de la app.',
      'applyingChange': 'Aplicando cambio...',
      'loadingMap': 'Cargando mapa...',
      'createdBy': 'Created by Reynoso Studios',
      'advertising': 'Publicidad',
      'noSavedLocation': 'No hay posicion guardada.',
      'gpsOff': 'GPS desactivado. Activa la ubicacion e intentalo de nuevo.',
      'permissionDenied': 'Permiso de ubicacion denegado. Es necesario para guardar el coche.',
      'permissionDeniedForever': 'Permiso de ubicacion bloqueado. Activalo en ajustes de Android.',
      'mapsError': 'No se puede abrir Google Maps.',
      'meters': '{value} m',
      'kilometers': '{value} km',
    },
    'fr': {
      'tagline': 'Je retrouve ma voiture',
      'home': 'Accueil',
      'history': 'Historique',
      'favorites': 'Favoris',
      'share': 'Partager',
      'settings': 'Reglages',
      'savePosition': 'Memoriser la position auto',
      'savePositionHint': 'Enregistre la position precise de votre voiture.',
      'findMyCar': 'Trouver ma voiture',
      'findHint': 'Ouvre la carte interne avec votre voiture et votre position.',
      'findDisabled': 'Enregistrez d abord la position de votre voiture.',
      'positionSaved': 'Position enregistree.',
      'savingShort': 'Enregistrement...',
      'savingCarPosition': 'Enregistrement position auto',
      'searchingGps': 'Recherche du meilleur signal GPS...',
      'savedDetailsTitle': 'Ajouter des details (facultatif)',
      'savedDetailsSubtitle': 'Ajoutez note, photo ou favori. Utile dans les parkings a etages.',
      'savedPositionData': 'Position enregistree',
      'note': 'Note',
      'noteHint': 'Ex. Niveau B, rangee 12, entree nord',
      'addPhoto': 'Photo parking',
      'favorite': 'Favori',
      'done': 'Termine',
      'distance': 'Distance',
      'accuracy': 'Precision',
      'savedAt': 'Enregistre le',
      'openGoogleMaps': 'Aller sur Google Maps',
      'notePhoto': 'Note ou photo',
      'noDetailsTitle': 'Aucun detail enregistre',
      'noDetailsBody': 'Vous pouvez ajouter une note ou une photo pendant l enregistrement.',
      'photoUnavailable': 'Photo indisponible.',
      'car': 'Auto',
      'currentPositionUnavailable': 'Position actuelle indisponible',
      'historyEmpty': 'Les positions enregistrees apparaitront ici.',
      'favoritesEmpty': 'Marquez une position comme favori pour la voir ici.',
      'shareLastPosition': 'Envoyer derniere position',
      'shareHint': 'Partagez avec WhatsApp, messages ou autres apps.',
      'shareWithApps': 'Partager avec apps',
      'shareMessage': 'Voici ou je me suis gare:',
      'language': 'Langue',
      'systemLanguage': 'Automatique',
      'languageAutoHint': 'L app detecte la langue du telephone. Vous pouvez la changer.',
      'changingLanguage': 'Changement de langue...',
      'appearance': 'Apparence',
      'appearanceHint': 'Choisissez theme clair, sombre ou automatique.',
      'systemTheme': 'Systeme',
      'lightTheme': 'Clair',
      'darkTheme': 'Sombre',
      'colors': 'Couleurs',
      'colorsHint': 'Choisissez la couleur principale de l app.',
      'applyingChange': 'Application...',
      'loadingMap': 'Chargement carte...',
      'createdBy': 'Created by Reynoso Studios',
      'advertising': 'Publicite',
      'noSavedLocation': 'Aucune position enregistree.',
      'gpsOff': 'GPS desactive. Activez la localisation et reessayez.',
      'permissionDenied': 'Autorisation de localisation refusee. Elle est necessaire.',
      'permissionDeniedForever': 'Autorisation bloquee. Activez-la dans les reglages Android.',
      'mapsError': 'Impossible d ouvrir Google Maps.',
      'meters': '{value} m',
      'kilometers': '{value} km',
    },
    'de': {
      'tagline': 'Ich finde mein Auto',
      'home': 'Start',
      'history': 'Verlauf',
      'favorites': 'Favoriten',
      'share': 'Teilen',
      'settings': 'Einstellungen',
      'savePosition': 'Autoposition speichern',
      'savePositionHint': 'Speichere die genaue Position deines Autos.',
      'findMyCar': 'Mein Auto finden',
      'findHint': 'Oeffnet die Karte mit Auto und aktueller Position.',
      'findDisabled': 'Speichere zuerst die Position deines Autos.',
      'positionSaved': 'Position gespeichert.',
      'savingShort': 'Position speichern...',
      'savingCarPosition': 'Autoposition wird gespeichert',
      'searchingGps': 'Suche bestes GPS-Signal...',
      'savedDetailsTitle': 'Details hinzufuegen (optional)',
      'savedDetailsSubtitle': 'Notiz, Foto oder Favorit helfen in grossen Parkhaeusern.',
      'savedPositionData': 'Gespeicherte Position',
      'note': 'Notiz',
      'noteHint': 'Z. B. Ebene B, Reihe 12, Nordeingang',
      'addPhoto': 'Parkfoto',
      'favorite': 'Favorit',
      'done': 'Fertig',
      'distance': 'Distanz',
      'accuracy': 'Genauigkeit',
      'savedAt': 'Gespeichert am',
      'openGoogleMaps': 'Zu Google Maps',
      'notePhoto': 'Notiz oder Foto',
      'noDetailsTitle': 'Keine Details gespeichert',
      'noDetailsBody': 'Du kannst beim Speichern eine Notiz oder ein Foto hinzufuegen.',
      'photoUnavailable': 'Foto nicht verfuegbar.',
      'car': 'Auto',
      'currentPositionUnavailable': 'Aktuelle Position nicht verfuegbar',
      'historyEmpty': 'Gespeicherte Positionen erscheinen hier.',
      'favoritesEmpty': 'Markiere eine Position als Favorit.',
      'shareLastPosition': 'Letzte Position senden',
      'shareHint': 'Teile mit WhatsApp, Nachrichten oder anderen Apps.',
      'shareWithApps': 'Mit Apps teilen',
      'shareMessage': 'Hier habe ich geparkt:',
      'language': 'Sprache',
      'systemLanguage': 'Automatisch',
      'languageAutoHint': 'Die App erkennt die Telefonsprache. Du kannst sie aendern.',
      'changingLanguage': 'Sprache wechseln...',
      'appearance': 'Darstellung',
      'appearanceHint': 'Waehle hell, dunkel oder automatisch.',
      'systemTheme': 'System',
      'lightTheme': 'Hell',
      'darkTheme': 'Dunkel',
      'colors': 'Farben',
      'colorsHint': 'Waehle die Hauptfarbe der App.',
      'applyingChange': 'Aenderung anwenden...',
      'loadingMap': 'Karte laden...',
      'createdBy': 'Created by Reynoso Studios',
      'advertising': 'Werbung',
      'noSavedLocation': 'Keine Position gespeichert.',
      'gpsOff': 'GPS ist aus. Aktiviere Standortdienste und versuche es erneut.',
      'permissionDenied': 'Standortberechtigung verweigert. Sie wird benoetigt.',
      'permissionDeniedForever': 'Standortberechtigung blockiert. Aktiviere sie in Android.',
      'mapsError': 'Google Maps kann nicht geoeffnet werden.',
      'meters': '{value} m',
      'kilometers': '{value} km',
    },
    'zh': {
      'tagline': '找到我的车',
      'home': '首页',
      'history': '历史',
      'favorites': '收藏',
      'share': '分享',
      'settings': '设置',
      'savePosition': '保存车辆位置',
      'savePositionHint': '保存车辆的精确位置。',
      'findMyCar': '找到我的车',
      'findHint': '在应用内地图查看车辆和当前位置。',
      'findDisabled': '请先保存车辆位置。',
      'positionSaved': '位置已保存。',
      'savingShort': '正在保存位置...',
      'savingCarPosition': '正在保存车辆位置',
      'searchingGps': '正在寻找最佳 GPS 信号...',
      'savedDetailsTitle': '添加详情（可选）',
      'savedDetailsSubtitle': '可添加备注、照片或收藏，适合大型停车场。',
      'savedPositionData': '已保存位置',
      'note': '备注',
      'noteHint': '例如 B 层，12 排，北入口',
      'addPhoto': '停车照片',
      'favorite': '收藏',
      'done': '完成',
      'distance': '距离',
      'accuracy': '精度',
      'savedAt': '保存时间',
      'openGoogleMaps': '打开 Google Maps',
      'notePhoto': '备注或照片',
      'noDetailsTitle': '没有保存详情',
      'noDetailsBody': '保存位置时可以添加备注或照片。',
      'photoUnavailable': '照片不可用。',
      'car': '车辆',
      'currentPositionUnavailable': '当前位置不可用',
      'historyEmpty': '保存的位置会显示在这里。',
      'favoritesEmpty': '收藏一个位置后会显示在这里。',
      'shareLastPosition': '发送最后位置',
      'shareHint': '通过 WhatsApp、短信或其他应用分享。',
      'shareWithApps': '通过应用分享',
      'shareMessage': '我把车停在这里：',
      'language': '语言',
      'systemLanguage': '自动',
      'languageAutoHint': '应用会检测手机语言，也可以手动更改。',
      'colors': '颜色',
      'colorsHint': '选择应用主色。',
      'noSavedLocation': '没有保存的位置。',
      'gpsOff': 'GPS 已关闭。请开启定位服务后重试。',
      'permissionDenied': '定位权限被拒绝。保存车辆需要此权限。',
      'permissionDeniedForever': '定位权限已被阻止。请在 Android 设置中开启。',
      'mapsError': '无法打开 Google Maps。',
      'meters': '{value} m',
      'kilometers': '{value} km',
    },
    'ar': {
      'tagline': 'اعثر على سيارتي',
      'home': 'الرئيسية',
      'history': 'السجل',
      'favorites': 'المفضلة',
      'share': 'مشاركة',
      'settings': 'الإعدادات',
      'savePosition': 'حفظ موقع السيارة',
      'savePositionHint': 'احفظ موقع سيارتك بدقة عالية.',
      'findMyCar': 'اعثر على سيارتي',
      'findHint': 'افتح الخريطة داخل التطبيق مع موقع السيارة وموقعك.',
      'findDisabled': 'احفظ موقع السيارة اولا.',
      'positionSaved': 'تم حفظ الموقع.',
      'savingShort': 'جار حفظ الموقع...',
      'savingCarPosition': 'جار حفظ موقع السيارة',
      'searchingGps': 'جار البحث عن افضل اشارة GPS...',
      'savedDetailsTitle': 'اضافة تفاصيل (اختياري)',
      'savedDetailsSubtitle': 'يمكنك اضافة ملاحظة او صورة او مفضلة.',
      'savedPositionData': 'الموقع المحفوظ',
      'note': 'ملاحظة',
      'noteHint': 'مثال: الطابق B، الصف 12',
      'addPhoto': 'صورة الموقف',
      'favorite': 'مفضل',
      'done': 'تم',
      'distance': 'المسافة',
      'accuracy': 'الدقة',
      'savedAt': 'تم الحفظ في',
      'openGoogleMaps': 'اذهب الى Google Maps',
      'notePhoto': 'ملاحظة او صورة',
      'noDetailsTitle': 'لا توجد تفاصيل محفوظة',
      'noDetailsBody': 'يمكنك اضافة ملاحظة او صورة عند حفظ الموقع.',
      'photoUnavailable': 'الصورة غير متاحة.',
      'car': 'السيارة',
      'currentPositionUnavailable': 'الموقع الحالي غير متاح',
      'historyEmpty': 'ستظهر المواقع المحفوظة هنا.',
      'favoritesEmpty': 'ضع موقعا في المفضلة ليظهر هنا.',
      'shareLastPosition': 'ارسال اخر موقع',
      'shareHint': 'شارك عبر واتساب او الرسائل او تطبيقات اخرى.',
      'shareWithApps': 'مشاركة مع التطبيقات',
      'shareMessage': 'هذا مكان ركن السيارة:',
      'language': 'اللغة',
      'systemLanguage': 'تلقائي',
      'languageAutoHint': 'يكتشف التطبيق لغة الهاتف ويمكنك تغييرها.',
      'colors': 'الألوان',
      'colorsHint': 'اختر اللون الرئيسي للتطبيق.',
      'noSavedLocation': 'لا يوجد موقع محفوظ.',
      'gpsOff': 'GPS متوقف. فعل خدمات الموقع وحاول مجددا.',
      'permissionDenied': 'تم رفض اذن الموقع. نحتاجه لحفظ السيارة.',
      'permissionDeniedForever': 'اذن الموقع محظور. فعله من اعدادات Android.',
      'mapsError': 'تعذر فتح Google Maps.',
      'meters': '{value} م',
      'kilometers': '{value} كم',
    },
  };

  String value(String key) {
    final language = _strings[locale.languageCode] ?? _strings['it']!;
    return language[key] ?? _strings['it']![key] ?? key;
  }

  String get tagline => value('tagline');
  String get home => value('home');
  String get history => value('history');
  String get favorites => value('favorites');
  String get share => value('share');
  String get settings => value('settings');
  String get savePosition => value('savePosition');
  String get savePositionHint => value('savePositionHint');
  String get findMyCar => value('findMyCar');
  String get findHint => value('findHint');
  String get findDisabled => value('findDisabled');
  String get positionSaved => value('positionSaved');
  String get savingShort => value('savingShort');
  String get savingCarPosition => value('savingCarPosition');
  String get searchingGps => value('searchingGps');
  String get savedDetailsTitle => value('savedDetailsTitle');
  String get savedDetailsSubtitle => value('savedDetailsSubtitle');
  String get savedPositionData => value('savedPositionData');
  String get note => value('note');
  String get noteHint => value('noteHint');
  String get addPhoto => value('addPhoto');
  String get favorite => value('favorite');
  String get done => value('done');
  String get distance => value('distance');
  String get accuracy => value('accuracy');
  String get savedAt => value('savedAt');
  String get openGoogleMaps => value('openGoogleMaps');
  String get notePhoto => value('notePhoto');
  String get noDetailsTitle => value('noDetailsTitle');
  String get noDetailsBody => value('noDetailsBody');
  String get photoUnavailable => value('photoUnavailable');
  String get car => value('car');
  String get currentPositionUnavailable => value('currentPositionUnavailable');
  String get historyEmpty => value('historyEmpty');
  String get favoritesEmpty => value('favoritesEmpty');
  String get shareLastPosition => value('shareLastPosition');
  String get shareHint => value('shareHint');
  String get shareWithApps => value('shareWithApps');
  String get shareMessage => value('shareMessage');
  String get language => value('language');
  String get systemLanguage => value('systemLanguage');
  String get languageAutoHint => value('languageAutoHint');
  String get changingLanguage => value('changingLanguage');
  String get appearance => value('appearance');
  String get appearanceHint => value('appearanceHint');
  String get systemTheme => value('systemTheme');
  String get lightTheme => value('lightTheme');
  String get darkTheme => value('darkTheme');
  String get colors => value('colors');
  String get colorsHint => value('colorsHint');
  String get applyingChange => value('applyingChange');
  String get loadingMap => value('loadingMap');
  String get createdBy => value('createdBy');
  String get advertising => value('advertising');
  String get noSavedLocation => value('noSavedLocation');
  String meters(int value) => this.value('meters').replaceAll('{value}', '$value');
  String kilometers(String value) => this.value('kilometers').replaceAll('{value}', value);
}

class LanguageOption {
  const LanguageOption(this.locale, this.label);

  final Locale locale;
  final String label;
}

class _AppTextDelegate extends LocalizationsDelegate<AppText> {
  const _AppTextDelegate();

  @override
  bool isSupported(Locale locale) {
    return AppText.supportedLocales.any(
      (supported) => supported.languageCode == locale.languageCode,
    );
  }

  @override
  Future<AppText> load(Locale locale) async => AppText(locale);

  @override
  bool shouldReload(_AppTextDelegate old) => false;
}
