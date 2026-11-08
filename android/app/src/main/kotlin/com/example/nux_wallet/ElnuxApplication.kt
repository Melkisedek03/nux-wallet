package com.example.nux_wallet

import android.app.Application
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.embedding.engine.plugins.util.GeneratedPluginRegister

// Kelas Application ELNUX — babak PERTAMA pola mesin-cache, dan
// pemilik mesin Flutter satu-satunya.
//
// Saat proses lahir, kelas ini membuat mesin Flutter, mendaftarkan
// plugin ke dalamnya, menjalankan entrypoint Dart bawaan, lalu
// memasukkannya ke FlutterEngineCache dengan ID tetap [ID_MESIN].
// MainActivity kemudian meminta mesin itu lewat getCachedEngineId()
// (babak kedua) dan selalu menemukannya, sehingga activity yang
// dibuka kembali menempel ke mesin yang sama — keadaan Dart, node,
// dan jembatan offline lanjut persis dari terakhir, sesuai maksud
// tahap B (mesin hidup selama proses; JembatanLatarService menjaga
// prosesnya).
//
// Babak ini tidak boleh hilang: bila activity meminta ID yang
// tidak ada di cache, kerangka melempar IllegalStateException di
// onCreate dan aplikasi tidak bisa dibuka sama sekali pada proses
// dingin mana pun — persis kejadian build 101, ketika babak kedua
// terpasang sendirian. Kompilasi Kotlin yang bersih TIDAK
// membuktikan kontrak runtime ini; yang membuktikannya adalah
// uji perangkat membuka aplikasi dari proses yang benar-benar mati.
class ElnuxApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        val mesin = FlutterEngine(this)
        // Plugin harus terdaftar sebelum entrypoint Dart berjalan:
        // kode Dart saat boot langsung memakai kanal plugin
        // (path_provider untuk direktori seed, shared_preferences,
        // dan lainnya). Pendaftar bawaan kerangka dipakai di sini —
        // kelas yang sama yang dipanggil alur activity normal
        // untuk memanggil GeneratedPluginRegistrant hasil generate.
        GeneratedPluginRegister.registerGeneratedPlugins(mesin)
        mesin.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint.createDefault(),
        )
        FlutterEngineCache.getInstance().put(ID_MESIN, mesin)
    }

    companion object {
        // ID mesin bersama — satu-satunya sumber kebenaran; dipakai
        // kelas ini saat memasukkan dan MainActivity saat meminta.
        const val ID_MESIN = "elnux_mesin_utama"
    }
}
