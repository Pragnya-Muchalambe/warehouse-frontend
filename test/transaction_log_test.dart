import 'package:flutter_test/flutter_test.dart';
import 'package:warehouse_poc/models/transaction_log.dart';

void main() {
  TransactionLog buildLog() => TransactionLog(
        id: 'log-1',
        timestamp: DateTime.utc(2026, 8, 27),
        type: LogType.incoming,
        user: 'admin',
        items: const [
          CartItem(id: 'PL-1', name: 'Material', quantityChange: 2),
        ],
        bill: 'bill.jpg',
        billData: 'bill-base64',
        proof: 'proof.jpg',
        proofData: 'proof-base64',
      );

  test('Bill and Proof serialize independently', () {
    final json = buildLog().toJson();
    final restored = TransactionLog.fromJson(json);

    expect(restored.bill, 'bill.jpg');
    expect(restored.billData, 'bill-base64');
    expect(restored.proof, 'proof.jpg');
    expect(restored.proofData, 'proof-base64');
  });

  test('legacy combined attachment is restored as Proof only', () {
    final json = buildLog().toJson()
      ..remove('bill')
      ..remove('billData')
      ..remove('proof')
      ..remove('proofData')
      ..['photo'] = '[PROOF_ATTACHED.jpg]'
      ..['photoData'] = 'legacy-base64';

    final restored = TransactionLog.fromJson(json);

    expect(restored.bill, isNull);
    expect(restored.billData, isNull);
    expect(restored.proof, '[PROOF_ATTACHED.jpg]');
    expect(restored.proofData, 'legacy-base64');
  });

  test('missing attachment fields deserialize without crashing', () {
    final json = buildLog().toJson()
      ..remove('bill')
      ..remove('billData')
      ..remove('proof')
      ..remove('proofData');

    final restored = TransactionLog.fromJson(json);

    expect(restored.bill, isNull);
    expect(restored.proof, isNull);
  });
}
