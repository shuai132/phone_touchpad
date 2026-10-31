package dev.phonetouchpad.core

import org.json.JSONObject
import java.net.URI
import java.net.URLDecoder
import java.nio.charset.StandardCharsets

const val PROTOCOL_VERSION = 1
const val RECEIVER_PORT = 49271

data class Packet(val kind: String, val x: Double = 0.0, val y: Double = 0.0, val fingers: Int = 1,
                  val time: Double? = null, val version: Int? = PROTOCOL_VERSION,
                  val nativeGestures: Boolean? = null, val rejection: String? = null) {
    fun encode(): ByteArray {
        require(x.isFinite() && y.isFinite() && (time == null || time.isFinite()))
        val json = JSONObject().put("kind", kind).put("x", x).put("y", y).put("fingers", fingers)
        version?.let { json.put("version", it) }; time?.let { json.put("time", it) }
        nativeGestures?.let { json.put("nativeGestures", it) }; rejection?.let { json.put("rejection", it) }
        return (json.toString() + "\n").toByteArray(StandardCharsets.UTF_8)
    }
    companion object {
        fun decode(line: String): Packet {
            val json = JSONObject(line)
            return Packet(json.getString("kind"), json.getDouble("x"), json.getDouble("y"), json.getInt("fingers"),
                if (json.has("time")) json.getDouble("time") else null,
                if (json.has("version")) json.getInt("version") else null,
                if (json.has("nativeGestures")) json.getBoolean("nativeGestures") else null,
                if (json.has("rejection")) json.getString("rejection") else null)
        }
    }
}

fun rejectionMessage(reason: String?): String = when (reason) {
    "receiverBusy" -> "此 Mac 已有连接，请先断开现有连接或稍后重试"
    "accessibilityRequired" -> "请在 Mac 菜单栏授权辅助功能，然后重新连接"
    "incompatibleVersion" -> "两端协议版本不兼容，请更新手机和 Mac 应用"
    "pairingRequired" -> "尚未完成配对，请重新连接"
    else -> "Mac 拒绝了连接，请重新配对"
}

fun pairingKey(text: String): ByteArray {
    val normalized = text.trim()
    require(normalized.matches(Regex("[0-9a-fA-F]{64}"))) { "请扫描 Mac 二维码或输入完整配对密钥" }
    return normalized.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
}

data class Invitation(val name: String, val key: String) {
    companion object {
        fun parse(text: String): Invitation {
            require(text.toByteArray(StandardCharsets.UTF_8).size < 2048)
            val uri = URI(text)
            require(uri.scheme == "phonetouchpad" && uri.host == "pair")
            val items = uri.rawQuery.orEmpty().split('&').map { item ->
                val parts = item.split('=', limit = 2)
                require(parts.size == 2)
                URLDecoder.decode(parts[0], "UTF-8") to URLDecoder.decode(parts[1].replace("+", "%2B"), "UTF-8")
            }
            require(items.size == 3 && items.map { it.first }.toSet().size == 3)
            val values = items.toMap()
            require(values["v"] == "1")
            val name = values["name"] ?: error("缺少设备名")
            require(name.isNotEmpty() && name.toByteArray(StandardCharsets.UTF_8).size <= 255)
            val key = values["key"] ?: error("缺少密钥")
            pairingKey(key)
            return Invitation(name, key.lowercase())
        }
    }
}
