package com.example.gps_speedometer

import android.app.PictureInPictureParams
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothSocket
import android.os.Build
import android.util.Rational
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.InputStream
import java.io.OutputStream
import java.util.UUID

class MainActivity: FlutterActivity() {
    private val WAKELOCK_CHANNEL = "com.example.gps_speedometer/wakelock"
    private val PIP_CHANNEL = "com.example.gps_speedometer/pip"
    private val OBD_CHANNEL = "com.example.gps_speedometer/obd"

    private val SPP_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    private var bluetoothSocket: BluetoothSocket? = null
    private var obdOutputStream: OutputStream? = null
    private var obdInputStream: InputStream? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WAKELOCK_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "enable" -> {
                    activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    result.success(true)
                }
                "disable" -> {
                    activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PIP_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "enterPip" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        try {
                            val params = PictureInPictureParams.Builder()
                                .setAspectRatio(Rational(1, 1))
                                .build()
                            enterPictureInPictureMode(params)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("PIP_ERROR", e.message, null)
                        }
                    } else {
                        result.error("UNSUPPORTED", "PiP requires Android 8.0+", null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, OBD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getPairedDevices" -> {
                    try {
                        val adapter = BluetoothAdapter.getDefaultAdapter()
                        if (adapter == null) {
                            result.success(emptyList<Map<String, String>>())
                            return@setMethodCallHandler
                        }
                        val paired = adapter.bondedDevices ?: emptySet()
                        val list = paired.map { d ->
                            mapOf("name" to (d.name ?: "Unknown"), "address" to d.address)
                        }
                        result.success(list)
                    } catch (e: Exception) {
                        result.error("BLUETOOTH_ERROR", e.message, null)
                    }
                }
                "connect" -> {
                    val address = call.argument<String>("address")
                    if (address.isNullOrEmpty()) {
                        result.error("INVALID_ARGS", "Address is required", null)
                        return@setMethodCallHandler
                    }
                    Thread {
                        try {
                            val adapter = BluetoothAdapter.getDefaultAdapter()
                            val device = adapter?.getRemoteDevice(address)
                            adapter?.cancelDiscovery()
                            bluetoothSocket?.close()
                            
                            val socket = device?.createRfcommSocketToServiceRecord(SPP_UUID)
                            socket?.connect()
                            bluetoothSocket = socket
                            obdOutputStream = socket?.outputStream
                            obdInputStream = socket?.inputStream

                            // Initial ELM327 setup commands
                            obdOutputStream?.write("ATZ\r".toByteArray())
                            Thread.sleep(300)
                            obdOutputStream?.write("ATE0\r".toByteArray())
                            Thread.sleep(150)
                            obdOutputStream?.write("ATL0\r".toByteArray())
                            Thread.sleep(150)
                            obdOutputStream?.write("ATSP0\r".toByteArray())
                            Thread.sleep(200)

                            runOnUiThread { result.success(true) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("CONNECT_FAILED", e.message, null) }
                        }
                    }.start()
                }
                "disconnect" -> {
                    try {
                        obdOutputStream?.close()
                        obdInputStream?.close()
                        bluetoothSocket?.close()
                        bluetoothSocket = null
                        obdOutputStream = null
                        obdInputStream = null
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("DISCONNECT_ERROR", e.message, null)
                    }
                }
                "queryPid" -> {
                    val pid = call.argument<String>("pid") ?: "010C"
                    val out = obdOutputStream
                    val input = obdInputStream
                    if (out == null || input == null) {
                        result.error("NOT_CONNECTED", "OBD socket not connected", null)
                        return@setMethodCallHandler
                    }
                    Thread {
                        try {
                            out.write("$pid\r".toByteArray())
                            val buffer = ByteArray(256)
                            val bytesRead = input.read(buffer)
                            val response = if (bytesRead > 0) String(buffer, 0, bytesRead).trim() else ""
                            runOnUiThread { result.success(response) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("QUERY_ERROR", e.message, null) }
                        }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }
    }
}
