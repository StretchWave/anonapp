import 'package:anonapp/core/services/session_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SessionStorageService', () {
    test('computeSessionKey derives correct key from Supabase URL', () {
      const url = 'https://abcdefghijklm.supabase.co';
      final key = SessionStorageService.computeSessionKey(url);
      expect(key, equals('sb-abcdefghijklm-auth-token'));
    });

    test('isRememberLoginEnabled defaults to true', () async {
      final enabled = await SessionStorageService.isRememberLoginEnabled();
      expect(enabled, isTrue);
    });

    test('setRememberLogin updates preference and migrates token', () async {
      const sessionKey = 'sb-testproject-auth-token';
      const fakeToken = '{"access_token":"fake_jwt_token_123"}';

      // 1. Initially set a token in persistent prefs
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(sessionKey, fakeToken);

      // 2. Set remember login to false
      await SessionStorageService.setRememberLogin(
        false,
        persistSessionKey: sessionKey,
      );
      final enabled = await SessionStorageService.isRememberLoginEnabled();
      expect(enabled, isFalse);

      // Persistent prefs must be cleared
      expect(prefs.containsKey(sessionKey), isFalse);

      // 3. Set remember login back to true
      await SessionStorageService.setRememberLogin(
        true,
        persistSessionKey: sessionKey,
      );
      final reEnabled = await SessionStorageService.isRememberLoginEnabled();
      expect(reEnabled, isTrue);

      // Persistent prefs must have the restored token
      expect(prefs.getString(sessionKey), equals(fakeToken));
    });
  });

  group('AnonAppLocalStorage', () {
    const sessionKey = 'sb-testproject-auth-token';
    const fakeToken = '{"access_token":"secret_jwt_xyz"}';

    test(
      'persists in persistent storage when remember login is true',
      () async {
        await SessionStorageService.setRememberLogin(
          true,
          persistSessionKey: sessionKey,
        );
        final storage = AnonAppLocalStorage(persistSessionKey: sessionKey);
        await storage.initialize();

        await storage.persistSession(fakeToken);

        expect(await storage.hasAccessToken(), isTrue);
        expect(await storage.accessToken(), equals(fakeToken));

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(sessionKey), equals(fakeToken));
      },
    );

    test(
      'persists only in ephemeral storage when remember login is false',
      () async {
        await SessionStorageService.setRememberLogin(
          false,
          persistSessionKey: sessionKey,
        );
        final storage = AnonAppLocalStorage(persistSessionKey: sessionKey);
        await storage.initialize();

        await storage.persistSession(fakeToken);

        expect(await storage.hasAccessToken(), isTrue);
        expect(await storage.accessToken(), equals(fakeToken));

        // Persistent storage MUST NOT contain the token!
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.containsKey(sessionKey), isFalse);
      },
    );

    test('removePersistedSession wipes all session storage', () async {
      final storage = AnonAppLocalStorage(persistSessionKey: sessionKey);
      await storage.initialize();

      await storage.persistSession(fakeToken);
      await storage.removePersistedSession();

      expect(await storage.hasAccessToken(), isFalse);
      expect(await storage.accessToken(), isNull);
    });
  });
}
