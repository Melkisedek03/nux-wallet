/// Konfigurasi koneksi ke LSP Nusacoin (MVP).
///
/// Nilai testnet diambil dari BUILD_MACOS.md. Untuk mainnet nanti:
/// ganti ke parameter mainnet dan set [isTestnet] = false.
class AppConfig {
  /// Alamat P2P node LSP, format "host:port" (subdomain, DNS-only).
  static const String lspAddress = 'lsp.taobot.org:9738';

  /// Public key (node id) node LSP — server testnet di VPS
  /// (stabil, diturunkan dari seed.bin yang persisten sejak 19 Okt 2026).
  static const String lspNodeId =
      '02b69d63f7f07765257d729b4141426abff80a91088eb439ec6f2e9669b6423549';

  /// Token akses LSPS2 (bLIP-52) yang dibagikan operator.
  static const String lspToken = 'nux-lsp-test-token';

  /// URL server Electrum (electrs) untuk chain data.
  static const String electrumUrl = 'tcp://lsp.taobot.org:60009';

  /// URL berkas registri direktori toko untuk tab Jelajah — satu berkas
  /// JSON statis terkurasi tim (pola yang sama dengan berkas fallback
  /// OTA PUNDI: tanpa server khusus, tanpa akun, tanpa pelacakan).
  /// Nilai ini adalah pola aset rilis repo ini; lokasi hosting final
  /// adalah keputusan tim — menggantinya cukup mengubah konstanta ini.
  static const String jelajahRegistryUrl =
      'https://github.com/Nusanian/nux-wallet/releases/download/Data/jelajah-registry.json';

  /// Ticker publik CoinPaprika — kuotasi LANGSUNG NUX/IDR untuk
  /// seksi Info Pasar tab Jelajah, satu panggilan. Menggantikan dua
  /// hop lama (candle qutrade NUX/USDT + kurs Indodax USDT/IDR):
  /// satu sumber lebih sedikit untuk gagal, dan harga rupiah tidak
  /// lagi bergantung pada kurs konversi. Kuotasi NUX/USDT
  /// CoinPaprika menjawab HTTP 400 — selalu pakai kuotasi IDR
  /// langsung ini, tanpa kunci API.
  static const String coinpaprikaTickerUrl =
      'https://api.coinpaprika.com/v1/tickers/nux-nusacoin?quotes=IDR';

  /// Basis REST electrs publik milik tim — statistik jaringan ringan
  /// (tinggi blok terkini) untuk tab Jelajah.
  static const String electrsRestBase = 'https://apinux.taobot.org';

  /// true = testnet Nusacoin, false = mainnet (Network.nusacoin).
  static const bool isTestnet = true;

  /// true kalau [lspNodeId] sudah diisi nilai aslinya.
  static bool get lspConfigured =>
      lspNodeId.isNotEmpty && lspNodeId != 'GANTI_DENGAN_NODE_ID_LSP';
}
