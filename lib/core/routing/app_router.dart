import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/auth/presentation/screens/splash_screen.dart';
import '../../features/auth/presentation/screens/welcome_screen.dart';
import '../../features/chat/presentation/screens/chat_screen.dart';
import '../../features/conversations/presentation/screens/main_screen.dart';
import '../../features/discover/presentation/screens/discover_screen.dart';
import '../../features/profile/presentation/screens/bookmarks_screen.dart';
import '../../features/profile/presentation/screens/edit_profile_screen.dart';
import '../../features/profile/presentation/screens/profile_screen.dart';
import '../../features/settings/presentation/screens/appearance_settings_screen.dart';
import '../../features/settings/presentation/screens/blocked_users_screen.dart';
import '../../features/settings/presentation/screens/help_faq_screen.dart';
import '../../features/settings/presentation/screens/privacy_settings_screen.dart';
import '../../features/settings/presentation/screens/security_settings_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';

/// Named route paths.
abstract final class AppRoutes {
  static const String splash = '/';
  static const String welcome = '/welcome';
  static const String login = '/login';
  static const String register = '/register';
  static const String main = '/main';
  static const String chat = '/chat/:conversationId';
  static const String search = '/search';
  static const String profile = '/profile';
  static const String editProfile = '/profile/edit';
  static const String bookmarks = '/profile/bookmarks';
  static const String settings = '/settings';
  static const String privacy = '/settings/privacy';
  static const String appearance = '/settings/appearance';
  static const String security = '/settings/security';
  static const String blocked = '/settings/blocked';
  static const String help = '/settings/help';
}

/// Global navigator key for programmatic deep-linking (e.g. from notification taps).
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// GoRouter configuration with auth-aware redirects.
final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: false,
    redirect: (BuildContext context, GoRouterState state) {
      final isLoading = authState.isLoading;
      final isAuthenticated = authState.valueOrNull ?? false;
      final currentPath = state.matchedLocation;

      // While checking auth on initial startup, stay on splash.
      if (isLoading) {
        return currentPath == AppRoutes.splash ? null : AppRoutes.splash;
      }

      // Once auth is resolved, move away from splash screen.
      if (currentPath == AppRoutes.splash) {
        return isAuthenticated ? AppRoutes.main : AppRoutes.welcome;
      }

      final authRoutes = {
        AppRoutes.welcome,
        AppRoutes.login,
        AppRoutes.register,
      };
      final isAuthRoute = authRoutes.contains(currentPath);

      // If not authenticated and trying to access a protected route, redirect to welcome.
      if (!isAuthenticated && !isAuthRoute) {
        return AppRoutes.welcome;
      }

      // If authenticated and trying to access auth pages, redirect to main.
      if (isAuthenticated && isAuthRoute) {
        return AppRoutes.main;
      }

      // No redirect needed.
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.welcome,
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.register,
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: AppRoutes.main,
        builder: (context, state) => const MainScreen(),
      ),
      GoRoute(
        path: AppRoutes.search,
        builder: (context, state) => const DiscoverScreen(),
      ),
      GoRoute(
        path: AppRoutes.profile,
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(
        path: AppRoutes.editProfile,
        builder: (context, state) => const EditProfileScreen(),
      ),
      GoRoute(
        path: AppRoutes.bookmarks,
        builder: (context, state) => const BookmarksScreen(),
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.privacy,
        builder: (context, state) => const PrivacySettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.appearance,
        builder: (context, state) => const AppearanceSettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.security,
        builder: (context, state) => const SecuritySettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.blocked,
        builder: (context, state) => const BlockedUsersScreen(),
      ),
      GoRoute(
        path: AppRoutes.help,
        builder: (context, state) => const HelpFaqScreen(),
      ),
      GoRoute(
        path: AppRoutes.chat,
        builder: (context, state) {
          final conversationId = state.pathParameters['conversationId'] ?? '';
          final username = state.uri.queryParameters['username'];
          return ChatScreen(
            conversationId: conversationId,
            otherUsername: username,
          );
        },
      ),
    ],
  );
});
