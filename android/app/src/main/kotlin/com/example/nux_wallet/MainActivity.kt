package com.example.nux_wallet

import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageInstaller
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

// Saluran MethodChannel untuk fitur update OTA (port dari
// nusan-catcher; lihat lib/services/update_service.dart):
// - "jalurApk": kembalikan path APK aplikasi yang sedang terpasang
//   (dipakai sisi Dart untuk menghitung SHA-256).
// - "abiTerpasang": kembalikan ABI APK yang terpasang ('arm64-v8a',
//   'armeabi-v7a', 'x86_64', atau 'unknown') dari nama folder lib
//   native-nya — dipakai sisi Dart memilih entri OTA yang sesuai
//   (bukan kemampuan perangkat: HP 64-bit yang memasang APK v7a
//   tetap di jalur v7a; emulator x86_64 di jalur x86_64).
// - "pasangApk": pasang APK hasil unduhan lewat sesi
//   PackageInstaller (tanpa intent implisit, jadi TANPA jendela
//   "Open with" — yang muncul langsung dialog konfirmasi sistem).
//   Hasil instalasi dibaca PenerimaStatusPasang: sukses membuka
//   kembali aplikasi, gagal mencoba jalur intent lama lalu
//   menampilkan penyebabnya — jadi kegagalan tidak hilang diam-diam.
class MainActivity : FlutterActivity() {
    private val saluranOta = "nux_wallet/ota"
    private val saluranJembatan = "nux_wallet/jembatan"

    // Mesin Flutter TIDAK dihancurkan bersama activity: jembatan
    // offline dan node berjalan di mesin ini, dan keduanya harus
    // tetap hidup saat tampilan aplikasi ditutup (layanan latar
    // depan JembatanLatarService menjaga prosesnya). Menutup
    // tampilan kini hanya menutup tampilan; proses — dan di
    // dalamnya node — hidup sampai sistem merebutnya kembali atau
    // sesi diakhiri. Ini sejalan dengan sikap aplikasi yang memang
    // menjaga layar menyala agar dompet siap menerima pembayaran.
    override fun shouldDestroyEngineWithHost(): Boolean = false

    // Babak KEDUA pola mesin-cache: activity selalu menempel ke
    // mesin yang dibuat ElnuxApplication saat proses lahir dan
    // disimpan di FlutterEngineCache dengan ID yang sama (lihat
    // ElnuxApplication). Baris ini TIDAK boleh ada tanpa babak
    // pertamanya: ID yang tidak ditemukan di cache membuat
    // kerangka melempar IllegalStateException di onCreate —
    // aplikasi gugur sebelum Dart hidup (kejadian build 101).
    override fun getCachedEngineId(): String = ElnuxApplication.ID_MESIN

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Saluran layanan latar jembatan offline (tahap produksi B):
        // sisi Dart memulai/menghentikan JembatanLatarService
        // mengikuti niat sesi (lihat lib/services/offline_bridge.dart).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, saluranJembatan)
            .setMethodCallHandler { panggilan, hasil ->
                when (panggilan.method) {
                    "mulaiLayanan" -> {
                        JembatanLatarService.mulai(this)
                        hasil.success(true)
                    }
                    "berhentiLayanan" -> {
                        JembatanLatarService.berhenti(this)
                        hasil.success(true)
                    }
                    else -> hasil.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, saluranOta)
            .setMethodCallHandler { panggilan, hasil ->
                when (panggilan.method) {
                    "jalurApk" -> {
                        hasil.success(applicationInfo.sourceDir)
                    }
                    "abiTerpasang" -> {
                        val namaDir = File(applicationInfo.nativeLibraryDir).name
                        hasil.success(
                            when (namaDir) {
                                "arm64" -> "arm64-v8a"
                                "arm" -> "armeabi-v7a"
                                "x86_64" -> "x86_64"
                                else -> "unknown"
                            },
                        )
                    }
                    "pasangApk" -> {
                        val jalur = panggilan.argument<String>("jalur")
                        if (jalur.isNullOrEmpty()) {
                            hasil.error("ARGUMEN", "Jalur berkas APK kosong", null)
                            return@setMethodCallHandler
                        }
                        try {
                            pasangLewatSesi(File(jalur))
                            hasil.success(true)
                        } catch (e: Exception) {
                            // Jaring pengaman sinkron: bila pembuatan
                            // atau commit sesi gagal, kembali ke intent
                            // (lihat pasangLewatIntent di
                            // PenerimaStatusPasang.kt). Kegagalan sesi
                            // yang terjadi BELAKANGAN ditangani
                            // PenerimaStatusPasang, bukan di sini —
                            // termasuk STATUS_PENDING_USER_ACTION yang
                            // BUKAN gagal dan tidak boleh dialihkan ke
                            // fallback.
                            try {
                                pasangLewatIntent(this, jalur)
                                hasil.success(true)
                            } catch (e2: Exception) {
                                hasil.error("PASANG", e2.message, null)
                            }
                        }
                    }
                    else -> hasil.notImplemented()
                }
            }
    }

    // Pasang APK lewat PackageInstaller Session API: sesi dibuat,
    // APK dialirkan ke sesi, lalu commit menampilkan langsung
    // dialog konfirmasi sistem (Update) — tanpa lempar intent ke
    // aplikasi lain, jadi tidak ada jendela "Open with".
    // Status instalasi dikirim sistem ke PenerimaStatusPasang lewat
    // PendingIntent siaran: sukses membuka kembali aplikasi, gagal
    // mencoba jalur intent lama lalu menampilkan penyebabnya.
    // PendingIntent status WAJIB FLAG_MUTABLE (bukan IMMUTABLE):
    // sistem mengisi extra hasil ke intent itu, dan pengisian gagal
    // bila intent-nya immutable. Jalur APK ikut dibawa di extra
    // "jalur_apk" supaya receiver bisa menjalankan fallback.
    private fun pasangLewatSesi(apk: File) {
        val pemasang = packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(
            PackageInstaller.SessionParams.MODE_FULL_INSTALL,
        )
        val idSesi = pemasang.createSession(params)
        pemasang.openSession(idSesi).use { sesi ->
            val keluar = sesi.openWrite("paket", 0, apk.length())
            keluar.use { stream ->
                FileInputStream(apk).use { masuk -> masuk.copyTo(stream) }
                sesi.fsync(stream)
            }
            val niatStatus = Intent(this, PenerimaStatusPasang::class.java).apply {
                putExtra("jalur_apk", apk.absolutePath)
            }
            val pengirim = PendingIntent.getBroadcast(
                this,
                idSesi,
                niatStatus,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
            ).intentSender
            sesi.commit(pengirim)
        }
    }
}
