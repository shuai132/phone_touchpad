package dev.phonetouchpad.core

import org.bouncycastle.tls.*
import org.bouncycastle.tls.crypto.impl.bc.BcTlsCrypto
import java.io.ByteArrayOutputStream
import java.net.InetSocketAddress
import java.net.Socket
import java.nio.charset.StandardCharsets
import java.security.SecureRandom
import java.util.concurrent.atomic.AtomicBoolean

/** A blocking TLS-PSK transport shared by the Android app and JVM interoperability checks. */
class SecureChannel : AutoCloseable {
    private val socket = Socket()
    private var tls: TlsClientProtocol? = null
    private val closed = AtomicBoolean(false)
    private val writeLock = Any()
    fun connect(host: String, port: Int = RECEIVER_PORT, key: String) {
        val psk = pairingKey(key)
        socket.tcpNoDelay = true; socket.keepAlive = true; socket.soTimeout = 10_000
        socket.connect(InetSocketAddress(host, port), 10_000)
        check(!closed.get()) { "连接已取消" }
        val protocol = TlsClientProtocol(socket.getInputStream(), socket.getOutputStream())
        tls = protocol
        try {
            protocol.connect(object : PSKTlsClient(BcTlsCrypto(SecureRandom()), BasicTlsPSKIdentity("phone-touchpad-v1", psk)) {
                override fun getSupportedVersions(): Array<ProtocolVersion> = arrayOf(ProtocolVersion.TLSv12)
                override fun getSupportedCipherSuites(): IntArray = intArrayOf(CipherSuite.TLS_PSK_WITH_AES_128_GCM_SHA256)
                override fun notifySelectedCipherSuite(selectedCipherSuite: Int) {
                    require(selectedCipherSuite == CipherSuite.TLS_PSK_WITH_AES_128_GCM_SHA256)
                    super.notifySelectedCipherSuite(selectedCipherSuite)
                }
                override fun notifyServerVersion(serverVersion: ProtocolVersion) {
                    require(serverVersion == ProtocolVersion.TLSv12)
                    super.notifyServerVersion(serverVersion)
                }
            })
        } finally { psk.fill(0) }
        socket.soTimeout = 8000
    }
    fun send(packet: Packet) = synchronized(writeLock) {
        check(!closed.get()) { "连接已断开" }
        val output = checkNotNull(tls).outputStream
        output.write(packet.encode()); output.flush()
    }
    fun receive(): Packet {
        val input = checkNotNull(tls).inputStream
        val bytes = ByteArrayOutputStream()
        while (!closed.get()) {
            val next = input.read()
            check(next >= 0) { "连接已断开" }
            if (next == 10) return Packet.decode(String(bytes.toByteArray(), StandardCharsets.UTF_8))
            check(bytes.size() < 65536) { "收到过长的数据帧" }
            bytes.write(next)
        }
        error("连接已断开")
    }
    override fun close() {
        if (closed.compareAndSet(false, true)) socket.close()
    }
}
