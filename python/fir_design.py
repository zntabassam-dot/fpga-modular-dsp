"""Windowed-sinc FIR coefficient design shared by the host test and RTL."""

import numpy as np


SAMPLE_RATE_HZ = 48_000
CUTOFF_HZ = 2_000
STOPBAND_START_HZ = 4_000
TRANSITION_WIDTH_HZ = STOPBAND_START_HZ - CUTOFF_HZ
STOPBAND_ATTENUATION_DB = 30.0
PASSBAND_CHECK_HZ = 1_000
FIR_TAPS = 41
COEFFICIENT_FRACTION_BITS = 15
COEFFICIENT_SCALE = 1 << COEFFICIENT_FRACTION_BITS


def _kaiser_beta(attenuation_db):
    """Kaiser-window beta approximation used by the firwin width method."""
    if attenuation_db > 50:
        return 0.1102 * (attenuation_db - 8.7)
    if attenuation_db >= 21:
        delta = attenuation_db - 21
        return 0.5842 * delta**0.4 + 0.07886 * delta
    return 0.0


def design_firwin_taps(
    num_taps=FIR_TAPS,
    cutoff_hz=CUTOFF_HZ,
    stopband_start_hz=STOPBAND_START_HZ,
    sample_rate_hz=SAMPLE_RATE_HZ,
    attenuation_db=None,
):
    """Return quantized Q1.15 taps for a windowed-sinc low-pass FIR.

    This is the windowed-sinc calculation used by scipy.signal.firwin with a
    Kaiser width. It is written with NumPy so the audio test does not require
    SciPy just to load the coefficients. The number of taps and frequency
    design values can be supplied by a streaming application.
    """
    if num_taps < 2:
        raise ValueError("num_taps must be at least 2")
    if not 0 < cutoff_hz < stopband_start_hz < sample_rate_hz / 2:
        raise ValueError("Require 0 < cutoff < stopband start < Nyquist")

    transition_width_hz = stopband_start_hz - cutoff_hz
    transition_width = transition_width_hz / (sample_rate_hz / 2)
    kaiser_attenuation = (
        2.285 * (num_taps - 1) * np.pi * transition_width + 7.95
    )
    requested_attenuation = (
        kaiser_attenuation if attenuation_db is None else
        min(attenuation_db, kaiser_attenuation)
    )
    beta = _kaiser_beta(requested_attenuation)

    sample_offsets = np.arange(num_taps) - (num_taps - 1) / 2
    normalized_cutoff = 2 * cutoff_hz / sample_rate_hz
    ideal_lowpass = normalized_cutoff * np.sinc(
        normalized_cutoff * sample_offsets
    )
    floating_taps = ideal_lowpass * np.kaiser(num_taps, beta)
    floating_taps /= floating_taps.sum()  # Unity gain at DC.

    quantized = np.rint(floating_taps * COEFFICIENT_SCALE).astype(np.int64)
    # Correct rounding at the centre tap so the fixed-point DC gain is exactly 1.
    centre = num_taps // 2
    quantized[centre] += COEFFICIENT_SCALE - int(quantized.sum())
    if np.any(quantized < -32768) or np.any(quantized > 32767):
        raise ValueError("Designed Q1.15 coefficients exceed signed 16-bit range")
    return tuple(int(value) for value in quantized)


FIR_COEFFICIENTS_Q15 = design_firwin_taps()


def response_db(coefficients=FIR_COEFFICIENTS_Q15, sample_rate_hz=SAMPLE_RATE_HZ):
    """Return frequencies and the quantized filter magnitude in dB."""
    fft_size = 65_536
    taps = np.asarray(coefficients, dtype=np.float64) / COEFFICIENT_SCALE
    response = np.abs(np.fft.rfft(taps, n=fft_size))
    frequencies = np.fft.rfftfreq(fft_size, d=1 / sample_rate_hz)
    magnitude_db = 20 * np.log10(np.maximum(response, 1e-12))
    return frequencies, magnitude_db


if __name__ == "__main__":
    frequencies, magnitude_db = response_db()
    stopband = magnitude_db[frequencies >= STOPBAND_START_HZ]
    passband = magnitude_db[frequencies <= PASSBAND_CHECK_HZ]
    print(f"FIR taps: {FIR_TAPS}")
    print(f"Cutoff: {CUTOFF_HZ} Hz; stopband starts: {STOPBAND_START_HZ} Hz")
    print(f"Passband checked: 0-{PASSBAND_CHECK_HZ} Hz")
    print(f"Passband ripple: {passband.max() - passband.min():.2f} dB")
    print(f"Worst stopband level: {stopband.max():.2f} dB")
    print("Q1.15 coefficients (tap index: signed integer):")
    for index, coefficient in enumerate(FIR_COEFFICIENTS_Q15):
        print(f"    {index:2d}: {coefficient}")
