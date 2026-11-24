import unittest

from fir_design import COEFFICIENT_SCALE, design_firwin_taps, response_db


class FirDesignTests(unittest.TestCase):
    def test_stream_design_produces_64_signed_q15_taps(self):
        coefficients = design_firwin_taps(
            num_taps=64,
            cutoff_hz=2_000,
            stopband_start_hz=4_000,
            sample_rate_hz=48_000,
            attenuation_db=30.0,
        )

        self.assertEqual(len(coefficients), 64)
        self.assertEqual(sum(coefficients), COEFFICIENT_SCALE)
        self.assertTrue(all(-32768 <= value <= 32767 for value in coefficients))
        frequencies, response = response_db(coefficients, sample_rate_hz=48_000)
        worst_stopband_db = response[frequencies >= 4_000].max()
        self.assertLessEqual(worst_stopband_db, -30.0)


if __name__ == "__main__":
    unittest.main()
