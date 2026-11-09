package com.example.nux_wallet

import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

// Jembatan Bluetooth Classic MILIK SENDIRI untuk layar Pengaturan
// Printer: status adapter, menyalakan Bluetooth, penemuan
// perangkat yang belum terpasang (discovery), dan pemasangan
// (bonding) dari dalam aplikasi.
//
// Berkas ini menggantikan paket flutter_blue_classic yang
// berlisensi GPL-3.0 — satu-satunya dependensi copyleft di
// aplikasi. Permukaan yang dipakai layar itu kecil, jadi
// ditulis ulang di sini langsung di atas API Android bawaan
// (BluetoothAdapter.startDiscovery / BluetoothDevice.createBond);
// tidak ada kode paket lama yang disalin, hanya perilaku luarnya
// yang disamai. Daftar perangkat yang SUDAH terpasang dan
// transport cetaknya sendiri sejak dulu ditangani paket
// print_bluetooth_thermal (BSD-3-Clause) — tidak berubah.
class BluetoothKlasik(
    private val konteksApp: Context,
    private val activity: Activity,
) {
    private fun adapter(): BluetoothAdapter? {
        val pengelola =
            konteksApp.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        return pengelola?.adapter
    }

    // Pasang kedua saluran ke mesin. Dipanggil dari
    // MainActivity.configureFlutterEngine — menempel ulang
    // (mesin-cache) memasang handler baru menggantikan yang lama;
    // keadaan bersama (penerima siaran + penunggu bonding) tinggal
    // di companion object supaya tidak ikut berlipat.
    fun pasang(messenger: BinaryMessenger) {
        EventChannel(messenger, SALURAN_PERISTIWA).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(argumen: Any?, sink: EventChannel.EventSink?) {
                    sinkPeristiwa = sink
                    daftarkanPenerima(konteksApp)
                    // Samakan keadaan awal: sisi Dart langsung tahu
                    // Bluetooth menyala atau tidak tanpa menunggu
                    // perubahan pertama.
                    val menyala = try {
                        adapter()?.isEnabled == true
                    } catch (e: SecurityException) {
                        false
                    }
                    sink?.success(
                        mapOf("jenis" to "adapter", "menyala" to menyala),
                    )
                }

                override fun onCancel(argumen: Any?) {
                    sinkPeristiwa = null
                    lepaskanPenerima(konteksApp)
                }
            },
        )
        MethodChannel(messenger, SALURAN_METODE).setMethodCallHandler { panggilan, hasil ->
            try {
                when (panggilan.method) {
                    "menyala" -> hasil.success(adapter()?.isEnabled == true)
                    "nyalakan" -> {
                        // Dialog konfirmasi sistem menyalakan
                        // Bluetooth — perlu activity terdepan.
                        // Hasilnya tiba lewat peristiwa adapter.
                        activity.startActivity(
                            Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE),
                        )
                        hasil.success(true)
                    }
                    "mulaiPindai" -> {
                        val a = adapter()
                        hasil.success(a != null && a.isEnabled && a.startDiscovery())
                    }
                    "berhentiPindai" -> {
                        val a = adapter()
                        if (a != null && a.isDiscovering) a.cancelDiscovery()
                        hasil.success(true)
                    }
                    "pasang" -> {
                        val alamat = panggilan.argument<String>("alamat")
                        val a = adapter()
                        if (alamat.isNullOrEmpty() || a == null) {
                            hasil.success(false)
                        } else {
                            mulaiBonding(a, alamat, hasil)
                        }
                    }
                    else -> hasil.notImplemented()
                }
            } catch (e: SecurityException) {
                hasil.error("IZIN", e.message, null)
            }
        }
    }

    // Bonding bersifat asinkron: createBond() hanya MEMULAI, hasil
    // akhirnya tiba sebagai siaran ACTION_BOND_STATE_CHANGED.
    // Satu bonding pada satu waktu (layar juga menguncinya);
    // penunggu disimpan di companion object dan diselesaikan
    // penerima siaran. Batas 60 detik: dialog pemasangan sistem
    // yang tidak dijawab tidak boleh menggantung panggilan ini
    // selamanya.
    private fun mulaiBonding(
        adapter: BluetoothAdapter,
        alamat: String,
        hasil: MethodChannel.Result,
    ) {
        val perangkat = adapter.getRemoteDevice(alamat)
        if (perangkat.bondState == BluetoothDevice.BOND_BONDED) {
            hasil.success(true)
            return
        }
        if (alamatBondDituju != null) {
            hasil.success(false)
            return
        }
        alamatBondDituju = alamat
        hasilBond = hasil
        Handler(Looper.getMainLooper()).postDelayed({
            if (alamatBondDituju == alamat) selesaikanBonding(false)
        }, 60_000)
        if (!perangkat.createBond()) selesaikanBonding(false)
    }

    companion object {
        private const val SALURAN_METODE = "nux_wallet/bluetooth_klasik"
        private const val SALURAN_PERISTIWA = "nux_wallet/bluetooth_klasik/peristiwa"

        private var sinkPeristiwa: EventChannel.EventSink? = null
        private var penerimaTerpasang = false
        private var alamatBondDituju: String? = null
        private var hasilBond: MethodChannel.Result? = null

        private fun selesaikanBonding(berhasil: Boolean) {
            val hasil = hasilBond
            alamatBondDituju = null
            hasilBond = null
            hasil?.success(berhasil)
        }

        private fun teksBond(keadaan: Int): String = when (keadaan) {
            BluetoothDevice.BOND_BONDED -> "terpasang"
            BluetoothDevice.BOND_BONDING -> "proses"
            else -> "belum"
        }

        // Satu-satunya penerima siaran Bluetooth aplikasi:
        // menerjemahkan siaran sistem menjadi peristiwa untuk
        // sisi Dart lewat sink yang sedang aktif (bila ada).
        private val penerima = object : BroadcastReceiver() {
            override fun onReceive(konteks: Context?, intent: Intent?) {
                val sink = sinkPeristiwa
                when (intent?.action) {
                    BluetoothAdapter.ACTION_STATE_CHANGED -> {
                        val menyala = intent.getIntExtra(
                            BluetoothAdapter.EXTRA_STATE,
                            BluetoothAdapter.ERROR,
                        ) == BluetoothAdapter.STATE_ON
                        sink?.success(
                            mapOf("jenis" to "adapter", "menyala" to menyala),
                        )
                    }
                    BluetoothAdapter.ACTION_DISCOVERY_STARTED ->
                        sink?.success(mapOf("jenis" to "pindai", "aktif" to true))
                    BluetoothAdapter.ACTION_DISCOVERY_FINISHED ->
                        sink?.success(mapOf("jenis" to "pindai", "aktif" to false))
                    BluetoothDevice.ACTION_FOUND -> {
                        val perangkat: BluetoothDevice? =
                            @Suppress("DEPRECATION")
                            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
                        if (perangkat != null && sink != null) {
                            val nama = try {
                                perangkat.name
                            } catch (e: SecurityException) {
                                null
                            }
                            val bond = try {
                                perangkat.bondState
                            } catch (e: SecurityException) {
                                BluetoothDevice.BOND_NONE
                            }
                            sink.success(
                                mapOf(
                                    "jenis" to "perangkat",
                                    "alamat" to perangkat.address,
                                    "nama" to nama,
                                    "bond" to teksBond(bond),
                                ),
                            )
                        }
                    }
                    BluetoothDevice.ACTION_BOND_STATE_CHANGED -> {
                        val perangkat: BluetoothDevice? =
                            @Suppress("DEPRECATION")
                            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
                        if (perangkat != null &&
                            perangkat.address == alamatBondDituju
                        ) {
                            when (perangkat.bondState) {
                                BluetoothDevice.BOND_BONDED ->
                                    selesaikanBonding(true)
                                BluetoothDevice.BOND_NONE ->
                                    selesaikanBonding(false)
                            }
                        }
                    }
                }
            }
        }

        private fun daftarkanPenerima(konteks: Context) {
            if (penerimaTerpasang) return
            val saringan = IntentFilter().apply {
                addAction(BluetoothAdapter.ACTION_STATE_CHANGED)
                addAction(BluetoothAdapter.ACTION_DISCOVERY_STARTED)
                addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED)
                addAction(BluetoothDevice.ACTION_FOUND)
                addAction(BluetoothDevice.ACTION_BOND_STATE_CHANGED)
            }
            konteks.applicationContext.registerReceiver(penerima, saringan)
            penerimaTerpasang = true
        }

        private fun lepaskanPenerima(konteks: Context) {
            if (!penerimaTerpasang) return
            try {
                konteks.applicationContext.unregisterReceiver(penerima)
            } catch (e: IllegalArgumentException) {
                // Sudah terlepas di jalur lain — keadaan bersama
                // tetap dibetulkan di bawah.
            }
            penerimaTerpasang = false
        }
    }
}
