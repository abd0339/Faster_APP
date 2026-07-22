import 'package:faster_app/dev/dev_launcher.DART';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'core/services/api_service.dart';
import 'core/services/storage_service.dart';
import 'core/router/app_router.dart';
import 'features/auth/bloc/auth_bloc.dart';
import 'features/auth/bloc/auth_event.dart';
import 'features/customer/screens/public_tracking_screen.dart';
import 'shared/theme/app_theme.dart';
import 'core/constants/app_colors.dart';
import 'dev/dev_launcher.DART';

// ─── DEV MODE FLAG ────────────────────────────────────
// Set with: flutter run --dart-define=DEV_MODE=true
// In production: DEV_MODE is always false (default)
// NEVER ship with DEV_MODE=true
const bool kDevMode = bool.fromEnvironment(
  'DEV_MODE',
  defaultValue: false,
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // FIX: enables real browser paths (faster-app.org/tracking/...)
  // instead of Flutter web's default hash-based URLs
  // (faster-app.org/#/tracking/...). Required for the public
  // tracking link — the backend puts a real path into the
  // WhatsApp/SMS message, so the app must be able to read it.
  if (kIsWeb) {
    usePathUrlStrategy();
  }

  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    // .env not found — using defaults
  }

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  if (kIsWeb) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );
  } else {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: AppColors.background,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );
  }

  // ─── Initialize services ──────────────────────────
  await ApiService.instance.init();

  // ─── FIX: check for a public tracking link FIRST ──
  // A customer clicking the WhatsApp/SMS tracking link
  // (faster-app.org/tracking/public/FST-XXXX) must see
  // the tracking page directly — no login, no auth
  // state, nothing else. This check happens before any
  // session/auth setup on purpose, since it must work
  // identically whether or not the visitor has ever
  // used the app before.
  final trackingCode = _extractPublicTrackingCode();
  if (trackingCode != null) {
    runApp(_PublicTrackingApp(trackingCode: trackingCode));
    return;
  }

  // ─── Check existing session ───────────────────────
  final isLoggedIn = await StorageService.instance.isLoggedIn();
  final role = await StorageService.instance.getRole();

  runApp(FasterApp(
    isLoggedIn: isLoggedIn,
    role: role,
  ));
}

// ─── Extract tracking code from the current browser URL ──
// Matches /tracking/public/{code} with or without a
// trailing slash. Returns null for every other URL (normal
// app boot) or on non-web platforms (Uri.base is meaningless
// there, so this simply never matches).
String? _extractPublicTrackingCode() {
  if (!kIsWeb) return null;
  final path = Uri.base.path;
  final match = RegExp(r'^/tracking/public/([^/]+)/?$').firstMatch(path);
  return match?.group(1);
}

// ─── Minimal, isolated app for anonymous tracking visitors ─
// Deliberately does NOT set up AuthBloc/BlocProvider at all —
// this visitor may have never used the app and shouldn't
// touch any auth machinery just to see their delivery status.
class _PublicTrackingApp extends StatelessWidget {
  final String trackingCode;
  const _PublicTrackingApp({required this.trackingCode});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Faster — Track Your Order',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: PublicTrackingScreen(trackingCode: trackingCode),
    );
  }
}

class FasterApp extends StatelessWidget {
  final bool isLoggedIn;
  final String? role;

  const FasterApp({
    super.key,
    required this.isLoggedIn,
    this.role,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) {
        final bloc = AuthBloc();
        // Auto-check session on startup
        bloc.add(CheckAuthStatus());
        return bloc;
      },
      child: MaterialApp(
        title: 'Faster',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        // DEV_MODE=true → show dev launcher (no login needed)
        // DEV_MODE=false (default) → normal app flow
        home: kDevMode ? DevLauncher() : const AppRouter(),
      ),
    );
  }
}
