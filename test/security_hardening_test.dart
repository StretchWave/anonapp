import 'package:anonapp/core/errors/app_exception.dart';
import 'package:anonapp/core/errors/error_handler.dart';
import 'package:anonapp/features/auth/domain/models/user_profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

void main() {
  group('Security Hardening & Privacy Tests', () {
    test(
      'UserProfile deserializes public RPC payload without leaking private fields',
      () {
        final publicJson = {
          'id': '11111111-2222-3333-4444-555555555555',
          'username': 'shadow_runner',
          'display_name': 'Shadow Runner',
          'avatar': 'cyber_fox',
          'bio': 'Encrypted anonymity test',
          'interests': ['Security', 'Tech'],
          'persona': 'NightCoder',
          'online_status_visible': false,
          'last_seen':
              null, // Masked by RPC when online_status_visible is false
          'created_at': '2026-09-08T12:00:00Z',
        };

        final profile = UserProfile.fromJson(publicJson);
        expect(profile.id, equals('11111111-2222-3333-4444-555555555555'));
        expect(profile.username, equals('shadow_runner'));
        expect(profile.contactCode, isNull); // Contact code must not be exposed
        expect(profile.lastSeen, isNull);
        expect(profile.onlineStatusVisible, isFalse);
      },
    );

    test(
      'ErrorHandler maps custom PL/pgSQL block errors to PermissionException',
      () {
        const postgrestError = sb.PostgrestException(
          message:
              'Cannot start conversation: this user is blocked or unavailable.',
          code: 'P0001',
        );

        final appException = ErrorHandler.handle(postgrestError);
        expect(appException, isA<PermissionException>());
        expect(appException.message, contains('unavailable or blocked'));
      },
    );

    test(
      'ErrorHandler maps unauthorized PL/pgSQL errors to PermissionException',
      () {
        const postgrestError = sb.PostgrestException(
          message: 'Unauthorized: Caller must participate in the conversation.',
          code: '42501',
        );

        final appException = ErrorHandler.handle(postgrestError);
        expect(appException, isA<PermissionException>());
      },
    );

    test(
      'Contact code format validation strictly enforces 8-character alphanumeric constraint',
      () {
        final validRegex = RegExp(r'^[A-Z0-9]{8}$');

        expect(validRegex.hasMatch('A7K9X2PQ'), isTrue);
        expect(validRegex.hasMatch('99ZZ88AA'), isTrue);
        expect(validRegex.hasMatch('abc'), isFalse); // too short
        expect(validRegex.hasMatch('A7K9-X2PQ'), isFalse); // contains hyphen
        expect(validRegex.hasMatch('A7K9X2PQ1'), isFalse); // too long
        expect(validRegex.hasMatch('A7K9 X2P'), isFalse); // contains space
        expect(validRegex.hasMatch('A7K9;DROP'), isFalse); // injection attempt
      },
    );
  });
}
