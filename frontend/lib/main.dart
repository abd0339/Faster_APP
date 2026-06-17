import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'core/services/api_service.dart';
import 'core/services/storage_service.dart';
import 'core/router/app_router.dart';
import 'features/auth/bloc/auth_bloc.dart';
import 'features/auth/bloc/auth_event.dart';
import 'shared/theme/app_theme.dart';
import 'core/constants/app_colors.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  // ─── Check existing session ───────────────────────
  final isLoggedIn = await StorageService.instance.isLoggedIn();
  final role = await StorageService.instance.getRole();

  runApp(FasterApp(
    isLoggedIn: isLoggedIn,
    role: role,
  ));
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
        home: const AppRouter(),
      ),
    );
  }
}
