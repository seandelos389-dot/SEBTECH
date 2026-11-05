import 'package:flutter_test/flutter_test.dart';
import 'package:integration_mobile/main.dart';

void main() {
  const product = {
    'name': 'RTX 4050 Ti',
    'category': 'GPU',
    'price': 12000,
    'stock': 4,
  };

  test(
    'matches product names without regard to case or surrounding spaces',
    () {
      expect(productMatchesSearch(product, '  rtx 4050  '), isTrue);
    },
  );

  test('matches product category and numeric product details', () {
    expect(productMatchesSearch(product, 'gpu'), isTrue);
    expect(productMatchesSearch(product, '12000'), isTrue);
    expect(productMatchesSearch(product, '4'), isTrue);
  });

  test('requires every search term to match', () {
    expect(productMatchesSearch(product, 'RTX GPU'), isTrue);
    expect(productMatchesSearch(product, 'RTX laptop'), isFalse);
  });

  test('an empty search shows every product', () {
    expect(productMatchesSearch(product, '   '), isTrue);
  });
}
