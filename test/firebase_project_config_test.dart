import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_mobile/firebase_options.dart';

void main() {
  test('all client platforms use the admin Firebase project', () {
    final options = [
      DefaultFirebaseOptions.web,
      DefaultFirebaseOptions.android,
      DefaultFirebaseOptions.ios,
      DefaultFirebaseOptions.macos,
      DefaultFirebaseOptions.windows,
    ];

    for (final option in options) {
      expect(option.projectId, 'product-system-app-8a06e');
      expect(
        option.databaseURL,
        'https://product-system-app-8a06e-default-rtdb.firebaseio.com',
      );
    }

    expect(DefaultFirebaseOptions.web.appId, contains(':web:'));
    expect(DefaultFirebaseOptions.android.appId, contains(':android:'));
    expect(DefaultFirebaseOptions.ios.appId, contains(':ios:'));
    expect(DefaultFirebaseOptions.macos.appId, contains(':ios:'));
    expect(DefaultFirebaseOptions.windows.appId, contains(':web:'));
  });

  test('FlutterFire manifest matches the generated Firebase options', () {
    final config =
        jsonDecode(File('firebase.json').readAsStringSync())
            as Map<String, dynamic>;
    final flutter = config['flutter'] as Map<String, dynamic>;
    final platforms = flutter['platforms'] as Map<String, dynamic>;
    final android = platforms['android'] as Map<String, dynamic>;
    final dart = platforms['dart'] as Map<String, dynamic>;
    final options = dart['lib/firebase_options.dart'] as Map<String, dynamic>;
    final configurations = options['configurations'] as Map<String, dynamic>;

    expect(android['default']['projectId'], 'product-system-app-8a06e');
    expect(android['default']['appId'], DefaultFirebaseOptions.android.appId);
    expect(options['projectId'], 'product-system-app-8a06e');
    expect(configurations['android'], DefaultFirebaseOptions.android.appId);
    expect(configurations['ios'], DefaultFirebaseOptions.ios.appId);
    expect(configurations['macos'], DefaultFirebaseOptions.macos.appId);
    expect(configurations['web'], DefaultFirebaseOptions.web.appId);
    expect(configurations['windows'], DefaultFirebaseOptions.windows.appId);
  });
}
