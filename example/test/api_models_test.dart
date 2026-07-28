import 'package:flutter_test/flutter_test.dart';
import 'package:xelis_flutter/src/api/models/wallet_dtos.dart';
import 'package:xelis_flutter/src/api/precomputed_tables.dart';

// The example intentionally tests the plugin's generated API.
// ignore_for_file: implementation_imports

void main() {
  test('HistoryPageFilter supports value equality and copyWith', () {
    final filter = HistoryPageFilter(
      page: BigInt.one,
      address: 'address',
      contract: 'contract',
      acceptIncoming: true,
      acceptOutgoing: false,
      acceptCoinbase: false,
      acceptBurn: false,
      acceptBlob: true,
    );

    final updated = filter.copyWith(page: BigInt.two);

    expect(filter.page, BigInt.one);
    expect(updated.page, BigInt.two);
    expect(updated.address, filter.address);
    expect(updated.acceptBlob, isTrue);
    expect(filter, isNot(updated));
  });

  test('Precomputed table variants have stable value equality', () {
    expect(
      const PrecomputedTableType.l1Low(),
      equals(const PrecomputedTableType.l1Low()),
    );
    expect(
      PrecomputedTableType.custom(BigInt.from(20)),
      isNot(PrecomputedTableType.custom(BigInt.from(21))),
    );
  });
}
