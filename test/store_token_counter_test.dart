import 'package:flutter_test/flutter_test.dart';
import 'package:nux_wallet/services/store_token_counter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('penghitung token harian', () {
    test('tanggal sama: naik satu-satu dari counter tersimpan', () {
      final now = DateTime(2026, 11, 3, 10, 30);
      final first = advanceTokenCounter(
        state: const StoreTokenCounterState(dateKey: '2026-11-03', counter: 14),
        now: now,
      );
      expect(first.issued, 15);
      expect(first.state.counter, 15);
      final second = advanceTokenCounter(state: first.state, now: now);
      expect(second.issued, 16);
    });

    test('tanggal berganti: mulai lagi dari 1', () {
      final advance = advanceTokenCounter(
        state: const StoreTokenCounterState(dateKey: '2026-11-02', counter: 87),
        now: DateTime(2026, 11, 3, 0, 5),
      );
      expect(advance.issued, 1);
      expect(advance.state, const StoreTokenCounterState(
        dateKey: '2026-11-03',
        counter: 1,
      ));
    });

    test('keadaan kosong: terbit 1; kunci tanggal ber-nol di depan', () {
      expect(tokenDateKey(DateTime(2026, 1, 5)), '2026-01-05');
      final advance = advanceTokenCounter(
        state: StoreTokenCounterState.empty,
        now: DateTime(2026, 11, 3, 8, 0),
      );
      expect(advance.issued, 1);
    });

    test('decode rusak fail-open ke keadaan kosong', () {
      expect(decodeTokenCounter(null), StoreTokenCounterState.empty);
      expect(decodeTokenCounter('bukan json'), StoreTokenCounterState.empty);
      expect(
        decodeTokenCounter('{"dateKey":5,"counter":-1}'),
        StoreTokenCounterState.empty,
      );
      const state = StoreTokenCounterState(dateKey: '2026-11-03', counter: 7);
      expect(decodeTokenCounter(encodeTokenCounter(state)), state);
    });

    test('store: next() menerbitkan berurutan & tersimpan', () async {
      SharedPreferences.setMockInitialValues({});
      final store = StoreTokenCounterStore();
      final now = DateTime(2026, 11, 3, 12, 0);
      expect(await store.next(now), 1);
      expect(await store.next(now), 2);
      expect(await StoreTokenCounterStore().next(now), 3);
      // Hari berikutnya mulai lagi dari 1.
      expect(await store.next(DateTime(2026, 11, 4, 9, 0)), 1);
    });
  });
}
