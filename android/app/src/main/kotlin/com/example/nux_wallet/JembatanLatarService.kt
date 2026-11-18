package com.example.nux_wallet

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.BitmapFactory
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

// Layanan latar depan jembatan offline (tahap produksi B): menjaga
// PROSES aplikasi tetap hidup selama sesi offline aktif, supaya
// jembatan Nearby + node (yang berjalan di mesin Flutter pada
// proses yang sama) tidak mati saat pengguna berpindah layar,
// mengunci HP, atau menutup tampilan aplikasi dari recents.
//
// Layanan ini TIDAK menjalankan logika jembatan — ia hanya:
// 1. Menampilkan notifikasi menetap (syarat layanan latar depan),
//    yang ketukannya membuka kembali aplikasi.
// 2. Memegang kunci bangun parsial selama sesi aktif supaya CPU
//    tidak tidur di tengah aliran byte Lightning. Kunci dilepas
//    saat layanan berhenti (sesi diakhiri dari sisi Dart).
// 3. START_STICKY: bila sistem tetap membunuhnya, layanan dibuat
//    ulang oleh sistem pada kesempatan pertama.
//
// Dimulai/dihentikan dari sisi Dart lewat saluran MethodChannel
// "nux_wallet/jembatan" di MainActivity, mengikuti siklus niat
// sesi OfflineBridgeService (lihat lib/services/offline_bridge.dart).
class JembatanLatarService : Service() {

    private var kunciBangun: PowerManager.WakeLock? = null

    override fun onCreate() {
        super.onCreate()
        buatKanalNotifikasi()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val ketukBuka = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        // Ikon kecil HARUS siluet putih-transparan (aturan Android
        // sejak v5: sistem hanya membaca bentuk alpha-nya lalu
        // mewarnainya; gambar berwarna berlatar solid digambar
        // sebagai kotak penuh — di Android 12 tampil kotak hitam).
        // Bentuk lama memakai applicationInfo.icon (launcher icon
        // berwarna) sehingga logonya tidak pernah tampil — padahal
        // siluet N+petir putihnya sudah disiapkan 27 Okt 2026 di
        // res/drawable-*/ic_notification.png dan tidak pernah
        // dipakai. Ikon besar menampilkan logo ELNUX berwarna di
        // sisi kanan notifikasi (ikon kecil tidak bisa berwarna).
        val notifikasi: Notification = NotificationCompat.Builder(this, KANAL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setLargeIcon(
                BitmapFactory.decodeResource(resources, R.mipmap.ic_launcher),
            )
            .setContentTitle("Mode Offline ELNUX aktif")
            .setContentText(
                "Mode Offline aktif — tetap terhubung dengan perangkat di dekatmu.",
            )
            .setOngoing(true)
            .setContentIntent(ketukBuka)
            .build()
        // Android 14+ mewajibkan tipe layanan disebut eksplisit
        // saat startForeground; tipe connectedDevice sesuai sifat
        // jembatan (koneksi Bluetooth/Wi-Fi ke perangkat lain) dan
        // cocok dengan deklarasi di AndroidManifest.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(ID_NOTIFIKASI, notifikasi, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
        } else {
            startForeground(ID_NOTIFIKASI, notifikasi)
        }
        if (kunciBangun == null) {
            val daya = getSystemService(Context.POWER_SERVICE) as PowerManager
            kunciBangun = daya.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "elnux:jembatan-offline",
            ).apply { acquire() }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        kunciBangun?.let { if (it.isHeld) it.release() }
        kunciBangun = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun buatKanalNotifikasi() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val kanal = NotificationChannel(
                KANAL_ID,
                "Jembatan Offline",
                // LOW: notifikasi menetap tidak perlu bersuara/bergetar.
                NotificationManager.IMPORTANCE_LOW,
            )
            val manajer = getSystemService(NotificationManager::class.java)
            manajer.createNotificationChannel(kanal)
        }
    }

    companion object {
        private const val KANAL_ID = "jembatan_offline"
        private const val ID_NOTIFIKASI = 19735

        // Kanal notifikasi sekali-pakai "jalur sudah siap" (PR C):
        // IMPORTANCE_DEFAULT supaya bersuara/bergetar sekali, bukan
        // menetap seperti notifikasi layanan latar. ID kanalnya
        // tidak pernah diubah sesudah dibuat (nama kanal tidak bisa
        // diubah tanpa ID baru).
        private const val KANAL_JALUR_SIAP_ID = "jalur_siap"
        private const val ID_NOTIFIKASI_JALUR_SIAP = 19737

        fun mulai(context: Context) {
            ContextCompat.startForegroundService(
                context,
                Intent(context, JembatanLatarService::class.java),
            )
        }

        fun berhenti(context: Context) {
            context.stopService(Intent(context, JembatanLatarService::class.java))
        }

        // Notifikasi sekali-pakai saat sebuah jalur langsung menjadi
        // usable (PR C): judul + isi sudah dilokalisasi di sisi
        // Dart. Ikon dan PendingIntent sama dengan notifikasi
        // layanan latar — ketukannya membuka kembali aplikasi.
        // Dipanggil dari sisi Dart lewat saluran MethodChannel
        // "nux_wallet/jembatan" (method "notifJalurSiap").
        fun notifJalurSiap(context: Context, judul: String, isi: String) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val kanal = NotificationChannel(
                    KANAL_JALUR_SIAP_ID,
                    "Jalur Siap",
                    NotificationManager.IMPORTANCE_DEFAULT,
                )
                val manajer =
                    context.getSystemService(NotificationManager::class.java)
                manajer.createNotificationChannel(kanal)
            }
            val ketukBuka = PendingIntent.getActivity(
                context,
                0,
                Intent(context, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val notifikasi: Notification =
                NotificationCompat.Builder(context, KANAL_JALUR_SIAP_ID)
                    .setSmallIcon(R.drawable.ic_notification)
                    .setLargeIcon(
                        BitmapFactory.decodeResource(
                            context.resources,
                            R.mipmap.ic_launcher,
                        ),
                    )
                    .setContentTitle(judul)
                    .setContentText(isi)
                    .setAutoCancel(true)
                    .setContentIntent(ketukBuka)
                    .build()
            val manajer =
                context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manajer.notify(ID_NOTIFIKASI_JALUR_SIAP, notifikasi)
        }
    }
}
