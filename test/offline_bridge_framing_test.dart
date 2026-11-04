import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nux_wallet/services/offline_bridge.dart';

/// Uji pembingkaian aliran jembatan offline: potongan socket
/// harus kembali utuh di sisi seberang walau ukuran potongan
/// kirim dan terima tidak sama.
void main() {
  Uint8List sample(int length) =>
      Uint8List.fromList(List<int>.generate(length, (i) => i % 251));

  group('LengthPrefixFramer/Deframer', () {
    test('data kosong tidak menghasilkan bingkai', () {
      expect(LengthPrefixFramer.encode(Uint8List(0)), isEmpty);
      final deframer = LengthPrefixDeframer();
      expect(deframer.feed(Uint8List(0)), isEmpty);
    });

    test('satu pesan kecil pulang-pergi utuh', () {
      final data = sample(100);
      final frames = LengthPrefixFramer.encode(data);
      expect(frames, hasLength(1));
      expect(frames.single.length, LengthPrefixFramer.headerSize + data.length);
      final deframer = LengthPrefixDeframer();
      expect(deframer.feed(frames.single), [data]);
    });

    test('pesan besar dipotong per batas bingkai', () {
      final data = sample(LengthPrefixFramer.maxPayloadPerFrame * 2 + 5);
      final frames = LengthPrefixFramer.encode(data);
      expect(frames, hasLength(3));
      for (final frame in frames) {
        expect(
          frame.length,
          lessThanOrEqualTo(
            LengthPrefixFramer.headerSize +
                LengthPrefixFramer.maxPayloadPerFrame,
          ),
        );
      }
      final deframer = LengthPrefixDeframer();
      final out = <Uint8List>[];
      for (final frame in frames) {
        out.addAll(deframer.feed(frame));
      }
      expect(out, hasLength(3));
      expect(out.expand((e) => e).toList(), data);
    });

    test('payload terpotong di tengah diterima bertahap', () {
      final data = sample(50);
      final wire = LengthPrefixFramer.encode(data).single;
      final deframer = LengthPrefixDeframer();
      // Potong di tengah header dan di tengah muatan.
      expect(deframer.feed(wire.sublist(0, 2)), isEmpty);
      expect(deframer.feed(wire.sublist(2, 10)), isEmpty);
      expect(deframer.feed(wire.sublist(10)), [data]);
    });

    test('dua bingkai dalam satu payload terbaca keduanya', () {
      final a = sample(10);
      final b = sample(20);
      final wire = Uint8List.fromList([
        ...LengthPrefixFramer.encode(a).single,
        ...LengthPrefixFramer.encode(b).single,
      ]);
      final deframer = LengthPrefixDeframer();
      expect(deframer.feed(wire), [a, b]);
    });

    test('panjang bingkai tidak wajar ditolak', () {
      final deframer = LengthPrefixDeframer();
      final corrupt = Uint8List(8);
      ByteData.view(corrupt.buffer)
          .setUint32(0, LengthPrefixDeframer.maxFramePayload + 1, Endian.big);
      expect(() => deframer.feed(corrupt), throwsFormatException);
    });
  });
}
