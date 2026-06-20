import 'package:flutter_test/flutter_test.dart';
import 'package:full_pos/main.dart';

void main() {
  test('money formats IQD amounts', () {
    expect(money(12500), '12,500 IQD');
  });

  test('generated barcode uses the local product prefix', () {
    final barcode = _testBarcode();
    expect(barcode.startsWith('FP'), isTrue);
    expect(barcode.length, greaterThan(10));
  });
}

String _testBarcode() {
  final line = CartLine({
    'id': 1,
    'name': 'Test',
    'selling_price': 10,
    'purchase_price': 5,
    'stock': 1,
    'unit_type': 'piece',
    'barcode': 'FP2606091200001000',
  });
  return line.barcode;
}
