import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nux_wallet/services/wallet_seed_store.dart';

/// Kanal plugin flutter_secure_storage (lihat
/// flutter_secure_storage_platform_interface).
const _channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

/// Seed uji 64 byte + satu seed lain untuk kasus "nilai berbeda".
final _seedA = List<int>.generate(64, (i) => i);
final _seedB = List<int>.generate(64, (i) => 255 - i);

const _mnemonicA =
    'legal winner thank year wave sausage worth useful legal winner thank yellow';
const _mnemonicB =
    'letter advice cage absurd amount doctor acoustic avoid letter advice cage above';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Isi tiruan Keystore/Keychain: kunci simpanan → nilai string.
  final fakeSecure = <String, String>{};

  /// Saklar injeksi kegagalan Keystore.
  var failReads = false;
  var failWrites = false;
  var corruptWrites = false;

  late Directory tempDir;

  WalletSeedStore store({bool? isTestnet}) =>
      WalletSeedStore(supportDir: tempDir, isTestnet: isTestnet);

  File plainSeedFile({bool mainnet = false}) => File(
    '${tempDir.path}/${mainnet ? 'lsp_seed_mainnet.bin' : 'lsp_seed.bin'}',
  );

  File plainMnemonicFile({bool mainnet = false}) => File(
    '${tempDir.path}/${mainnet ? 'wallet_mnemonic_mainnet.txt' : 'wallet_mnemonic.txt'}',
  );

  Future<void> writePlainSeed(List<int> bytes, {bool mainnet = false}) async {
    await plainSeedFile(mainnet: mainnet).writeAsBytes(bytes, flush: true);
  }

  Future<void> writePlainMnemonic(String text, {bool mainnet = false}) async {
    await plainMnemonicFile(mainnet: mainnet).writeAsString(text, flush: true);
  }

  setUp(() async {
    fakeSecure.clear();
    failReads = false;
    failWrites = false;
    corruptWrites = false;
    tempDir = await Directory.systemTemp.createTemp('wallet_seed_store_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          final args = (call.arguments as Map?)?.cast<String, Object?>();
          final key = args?['key'] as String?;
          switch (call.method) {
            case 'read':
              if (failReads) {
                throw PlatformException(code: 'KEYSTORE_UNAVAILABLE');
              }
              return fakeSecure[key];
            case 'write':
              if (failWrites) {
                throw PlatformException(code: 'KEYSTORE_UNAVAILABLE');
              }
              final value = args?['value'] as String?;
              if (value == null) {
                fakeSecure.remove(key);
              } else if (corruptWrites) {
                fakeSecure[key!] = 'nilai-korup';
              } else {
                fakeSecure[key!] = value;
              }
              return null;
            case 'delete':
              fakeSecure.remove(key);
              return null;
            default:
              throw UnimplementedError(
                'Panggilan secure storage tak terduga: ${call.method}',
              );
          }
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('WalletSeedStore', () {
    test(
      'instalasi baru: simpan ke secure storage, tanpa berkas biasa',
      () async {
        final s = store(isTestnet: true);
        await s.saveSeed(_seedA);
        await s.saveMnemonic(_mnemonicA);

        expect(fakeSecure['lsp_seed'], base64Encode(_seedA));
        expect(fakeSecure['wallet_mnemonic'], _mnemonicA);
        expect(await plainSeedFile().exists(), isFalse);
        expect(await plainMnemonicFile().exists(), isFalse);
        expect(await s.loadSeed(), _seedA);
        expect(await s.loadMnemonic(), _mnemonicA);
      },
    );

    test('migrasi: berkas biasa pindah ke secure, berkas dihapus', () async {
      await writePlainSeed(_seedA);
      await writePlainMnemonic(_mnemonicA);
      final s = store(isTestnet: true);

      await s.migrateFromPlainFiles();

      expect(fakeSecure['lsp_seed'], base64Encode(_seedA));
      expect(fakeSecure['wallet_mnemonic'], _mnemonicA);
      expect(await plainSeedFile().exists(), isFalse);
      expect(await plainMnemonicFile().exists(), isFalse);
      expect(await s.loadSeed(), _seedA);
      expect(await s.loadMnemonic(), _mnemonicA);
    });

    test('migrasi idempotent: jalan kedua no-op', () async {
      await writePlainSeed(_seedA);
      await writePlainMnemonic(_mnemonicA);
      final s = store(isTestnet: true);
      await s.migrateFromPlainFiles();
      final afterFirst = Map<String, String>.of(fakeSecure);

      await s.migrateFromPlainFiles();

      expect(fakeSecure, afterFirst);
      expect(await s.loadSeed(), _seedA);
    });

    test('secure sudah terisi + berkas biasa ada: berkas dihapus, '
        'secure dipertahankan', () async {
      final s = store(isTestnet: true);
      await s.saveSeed(_seedA);
      await s.saveMnemonic(_mnemonicA);
      // Berkas lama tertinggal (mis. penghapusan migrasi gagal).
      await writePlainSeed(_seedA);
      await writePlainMnemonic(_mnemonicA);

      await s.migrateFromPlainFiles();

      expect(await plainSeedFile().exists(), isFalse);
      expect(await plainMnemonicFile().exists(), isFalse);
      expect(await s.loadSeed(), _seedA);
      expect(await s.loadMnemonic(), _mnemonicA);
    });

    test('secure beda (hasil restore) + berkas lama: berkas dihapus, '
        'secure baru dipertahankan', () async {
      final s = store(isTestnet: true);
      await s.saveSeed(_seedB);
      await s.saveMnemonic(_mnemonicB);
      // Berkas lama dari dompet sebelum restore.
      await writePlainSeed(_seedA);
      await writePlainMnemonic(_mnemonicA);

      await s.migrateFromPlainFiles();

      expect(await plainSeedFile().exists(), isFalse);
      expect(await plainMnemonicFile().exists(), isFalse);
      expect(await s.loadSeed(), _seedB);
      expect(await s.loadMnemonic(), _mnemonicB);
    });

    test('gagal tulis secure saat simpan: fallback berkas biasa, '
        'dompet tetap jalan + migrasi berikutnya berhasil', () async {
      failWrites = true;
      final s = store(isTestnet: true);

      await s.saveSeed(_seedA);
      await s.saveMnemonic(_mnemonicA);

      expect(fakeSecure, isEmpty);
      expect(await plainSeedFile().exists(), isTrue);
      expect(await s.loadSeed(), _seedA);
      expect(await s.loadMnemonic(), _mnemonicA);

      failWrites = false;
      await s.migrateFromPlainFiles();

      expect(fakeSecure['lsp_seed'], base64Encode(_seedA));
      expect(await plainSeedFile().exists(), isFalse);
    });

    test('gagal baca secure: loadSeed fallback ke berkas biasa', () async {
      await writePlainSeed(_seedA);
      failReads = true;
      final s = store(isTestnet: true);

      expect(await s.loadSeed(), _seedA);
    });

    test('migrasi gagal (secure mati): berkas dipertahankan, '
        'dompet tetap jalan', () async {
      await writePlainSeed(_seedA);
      await writePlainMnemonic(_mnemonicA);
      failReads = true;
      failWrites = true;
      final s = store(isTestnet: true);

      // Tidak melempar (fail-open).
      await s.migrateFromPlainFiles();

      expect(await plainSeedFile().exists(), isTrue);
      expect(await plainMnemonicFile().exists(), isTrue);
      expect(fakeSecure, isEmpty);
      expect(await s.loadSeed(), _seedA);

      failReads = false;
      failWrites = false;
      await s.migrateFromPlainFiles();
      expect(fakeSecure['lsp_seed'], base64Encode(_seedA));
      expect(await plainSeedFile().exists(), isFalse);
    });

    test('baca-balik tidak cocok saat simpan seed: melempar, '
        'tanpa berkas biasa', () async {
      corruptWrites = true;
      final s = store(isTestnet: true);

      await expectLater(s.saveSeed(_seedA), throwsStateError);
      expect(await plainSeedFile().exists(), isFalse);
    });

    test('baca-balik tidak cocok saat simpan frasa: melempar', () async {
      corruptWrites = true;
      final s = store(isTestnet: true);

      await expectLater(s.saveMnemonic(_mnemonicA), throwsStateError);
      expect(await plainMnemonicFile().exists(), isFalse);
    });

    test('pemisahan jaringan: kunci testnet dan mainnet tidak '
        'bertabrakan', () async {
      final testnet = store(isTestnet: true);
      final mainnet = store(isTestnet: false);
      await testnet.saveSeed(_seedA);
      await testnet.saveMnemonic(_mnemonicA);
      await mainnet.saveSeed(_seedB);
      await mainnet.saveMnemonic(_mnemonicB);

      expect(fakeSecure['lsp_seed'], base64Encode(_seedA));
      expect(fakeSecure['lsp_seed_mainnet'], base64Encode(_seedB));
      expect(fakeSecure['wallet_mnemonic'], _mnemonicA);
      expect(fakeSecure['wallet_mnemonic_mainnet'], _mnemonicB);
      expect(await testnet.loadSeed(), _seedA);
      expect(await mainnet.loadSeed(), _seedB);
      expect(await testnet.loadMnemonic(), _mnemonicA);
      expect(await mainnet.loadMnemonic(), _mnemonicB);
    });

    test('migrasi testnet tidak menyentuh berkas mainnet', () async {
      await writePlainSeed(_seedA);
      await writePlainSeed(_seedB, mainnet: true);
      await store(isTestnet: true).migrateFromPlainFiles();

      expect(fakeSecure['lsp_seed'], base64Encode(_seedA));
      expect(fakeSecure.containsKey('lsp_seed_mainnet'), isFalse);
      expect(await plainSeedFile().exists(), isFalse);
      expect(await plainSeedFile(mainnet: true).exists(), isTrue);
    });

    test('berkas seed 32 byte: bukan dompet, dihapus migrasi', () async {
      await writePlainSeed(List<int>.filled(32, 9));
      final s = store(isTestnet: true);

      expect(await s.loadSeed(), isNull);

      await s.migrateFromPlainFiles();

      expect(await plainSeedFile().exists(), isFalse);
      expect(fakeSecure, isEmpty);
    });

    test('berkas seed panjang korup: loadSeed melempar, migrasi '
        'tidak menyentuh', () async {
      await writePlainSeed(List<int>.filled(10, 7));
      final s = store(isTestnet: true);

      Object? caught;
      try {
        await s.loadSeed();
        fail('seharusnya melempar');
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<SeedCorruptException>());
      expect((caught as SeedCorruptException).length, 10);
      expect(caught.path, contains('lsp_seed.bin'));

      await s.migrateFromPlainFiles();
      expect(await plainSeedFile().exists(), isTrue);
    });

    test('nilai secure korup + berkas biasa sah: fallback berkas, '
        'migrasi memperbaiki secure', () async {
      fakeSecure['lsp_seed'] = 'bukan-base64!!!';
      await writePlainSeed(_seedA);
      final s = store(isTestnet: true);

      expect(await s.loadSeed(), _seedA);

      await s.migrateFromPlainFiles();

      expect(fakeSecure['lsp_seed'], base64Encode(_seedA));
      expect(await plainSeedFile().exists(), isFalse);
    });

    test('nilai secure base64 panjang salah + berkas biasa sah: '
        'fallback berkas', () async {
      fakeSecure['lsp_seed'] = base64Encode(List<int>.filled(10, 7));
      await writePlainSeed(_seedA);
      final s = store(isTestnet: true);

      expect(await s.loadSeed(), _seedA);
    });

    test('nilai secure korup tanpa berkas biasa: loadSeed melempar', () async {
      fakeSecure['lsp_seed'] = 'bukan-base64!!!';
      final s = store(isTestnet: true);

      Object? caught;
      try {
        await s.loadSeed();
        fail('seharusnya melempar');
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<SeedCorruptException>());
      expect((caught as SeedCorruptException).path, isNull);
    });

    test('clearAll menghapus secure + sisa berkas biasa', () async {
      final s = store(isTestnet: true);
      await s.saveSeed(_seedA);
      await s.saveMnemonic(_mnemonicA);
      await writePlainSeed(_seedA);
      await writePlainMnemonic(_mnemonicA);

      await s.clearAll();

      expect(fakeSecure, isEmpty);
      expect(await plainSeedFile().exists(), isFalse);
      expect(await plainMnemonicFile().exists(), isFalse);
      expect(await s.loadSeed(), isNull);
      expect(await s.loadMnemonic(), isNull);
    });

    test('migrasi frasa: berkas kosong dihapus tanpa simpanan', () async {
      await writePlainMnemonic('   ');
      final s = store(isTestnet: true);

      await s.migrateFromPlainFiles();

      expect(await plainMnemonicFile().exists(), isFalse);
      expect(fakeSecure, isEmpty);
      expect(await s.loadMnemonic(), isNull);
    });

    test('frasa di secure diutamakan atas berkas biasa', () async {
      final s = store(isTestnet: true);
      await s.saveMnemonic(_mnemonicA);
      await writePlainMnemonic(_mnemonicB);

      expect(await s.loadMnemonic(), _mnemonicA);

      await s.migrateFromPlainFiles();
      expect(await plainMnemonicFile().exists(), isFalse);
      expect(await s.loadMnemonic(), _mnemonicA);
    });
  });
}
