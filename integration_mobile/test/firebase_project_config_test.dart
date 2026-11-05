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
  });
}
