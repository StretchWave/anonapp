import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/routing/app_router.dart';
import 'core/services/presence/presence_provider.dart';
import 'core/theme/app_theme.dart';
import 'features/messages/presentation/providers/notification_provider.dart';

/// Root application widget.
class AnonApp extends ConsumerWidget {
  const AnonApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    // Activates message notifications on Android and iOS (no-op on Web)
    ref.watch(messageNotificationListenerProvider);

    // Activates real-time presence & online/offline tracking across Web and Mobile
    ref.watch(presenceSyncProvider);

    return MaterialApp.router(
      title: 'AnonApp',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark, // Default to dark; user preference in Phase 8+
      routerConfig: router,
    );
  }
}
