import 'dart:convert';
import 'dart:io';

/// Kirim teks ke Telegram lewat Bot API resmi (permintaan
/// NUX 5 Nov 2026): laporan shift terkirim ke Telegram owner
/// saat kasir menutup shift — langsung dari aplikasi, tanpa
/// server perantara apa pun. Token bot dibuat owner sendiri
/// di BotFather; token + id chat tujuan diatur di Pengaturan
/// Toko (layar bergerbang PIN admin).
///
/// Mengembalikan true hanya bila Telegram menjawab ok.
/// Semua kegagalan (jaringan mati, token salah, chat tidak
/// ditemukan) → false; pengiriman laporan TIDAK PERNAH boleh
/// menggagalkan atau menahan penutupan shift itu sendiri.
Future<bool> sendTelegramMessage({
  required String botToken,
  required String chatId,
  required String text,
  Duration timeout = const Duration(seconds: 15),
}) async {
  final token = botToken.trim();
  final chat = chatId.trim();
  if (token.isEmpty || chat.isEmpty || text.trim().isEmpty) return false;
  HttpClient? client;
  try {
    client = HttpClient();
    client.connectionTimeout = timeout;
    final uri = Uri.parse('https://api.telegram.org/bot$token/sendMessage');
    final request = await client.postUrl(uri).timeout(timeout);
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({'chat_id': chat, 'text': text}));
    final response = await request.close().timeout(timeout);
    if (response.statusCode != 200) {
      await response.drain<void>();
      return false;
    }
    final body = await response.transform(utf8.decoder).join();
    try {
      final decoded = jsonDecode(body);
      return decoded is Map && decoded['ok'] == true;
    } catch (_) {
      return false;
    }
  } catch (_) {
    return false;
  } finally {
    client?.close(force: true);
  }
}
