package dev.phonetouchpad.core

/** Android finger pressure is device-specific. This is an opt-in relative estimate, not force. */
class PressureEstimate {
    private var baseline: Double? = null
    fun reset() { baseline = null }
    fun sample(raw: Double, deepPress: Boolean = false): Double? {
        if (!raw.isFinite() || raw < 0) return null
        if (deepPress) return 1.0
        if (baseline == null && raw > 0) baseline = raw
        val initial = baseline ?: return null
        // Constant 1.0 (common on devices without meaningful finger pressure) stays zero.
        return ((raw - initial) / maxOf(initial, 0.2)).coerceIn(0.0, 1.0)
    }
}
