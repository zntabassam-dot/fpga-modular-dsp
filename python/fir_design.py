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


def design_firwin_taps():
    """Return quantized Q1.15 taps for firwin(cutoff=2k, width=2k, fs=48k).

    This is the windowed-sinc calculation used by scipy.signal.firwin with a
    Kaiser width. It is written with NumPy so the audio test does not require
    SciPy just to load the coefficients.
    """
    transition_width = TRANSITION_WIDTH_HZ / (SAMPLE_RATE_HZ / 2)
    attenuation = (
        2.285 * (FIR_TAPS - 1) * np.pi * transition_width + 7.95
    )
    beta = _kaiser_beta(attenuation)

    sample_offsets = np.arange(FIR_TAPS) - (FIR_TAPS - 1) / 2
    normalized_cutoff = 2 * CUTOFF_HZ / SAMPLE_RATE_HZ
    ideal_lowpass = normalized_cutoff * np.sinc(
        normalized_cutoff * sample_offsets
    )
    floating_taps = ideal_lowpass * np.kaiser(FIR_TAPS, beta)
    floating_taps /= floating_taps.sum()  # Unity gain at DC.

    quantized = np.rint(floating_taps * COEFFICIENT_SCALE).astype(np.int64)
    # Correct rounding at the centre tap so the fixed-point DC gain is exactly 1.
    centre = FIR_TAPS // 2
    quantized[centre] += COEFFICIENT_SCALE - int(quantized.sum())
    return tuple(int(value) for value in quantized)


FIR_COEFFICIENTS_Q15 = design_firwin_taps()


def response_db():
    """Return frequencies and the quantized filter magnitude in dB."""
    fft_size = 65_536
    taps = np.asarray(FIR_COEFFICIENTS_Q15, dtype=np.float64) / COEFFICIENT_SCALE
    response = np.abs(np.fft.rfft(taps, n=fft_size))
    frequencies = np.fft.rfftfreq(fft_size, d=1 / SAMPLE_RATE_HZ)
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
