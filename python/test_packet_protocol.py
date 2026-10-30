import unittest

from packet_controller import MAX_PAYLOAD, SYNC, build_packet
from packet_commands import CMD_DATA
from packet_response import read_packet


class FakeSerial:
    def __init__(self, data):
        self.data = bytearray(data)

    def read(self, count):
        result = bytes(self.data[:count])
        del self.data[:count]
        return result


class PacketControllerTests(unittest.TestCase):
    def test_empty_echo_packet(self):
        self.assertEqual(build_packet(0x01), b"\xA5\x5A\x01\x00\x00\x01")

    def test_payload_length_and_xor_checksum(self):
        payload = b"\x12\xA5"
        packet = build_packet(0x01, payload)

        self.assertEqual(packet[:2], SYNC)
        self.assertEqual(packet[2:5], b"\x01\x02\x00")
        self.assertEqual(packet[5:-1], payload)
        self.assertEqual(packet[-1], 0x01 ^ 0x02 ^ 0x12 ^ 0xA5)

    def test_maximum_payload_is_allowed(self):
        packet = build_packet(0x01, bytes(MAX_PAYLOAD))
        self.assertEqual(packet[3:5], MAX_PAYLOAD.to_bytes(2, "little"))
        self.assertEqual(len(packet), len(SYNC) + 1 + 2 + MAX_PAYLOAD + 1)

    def test_payload_over_limit_is_rejected(self):
        with self.assertRaises(ValueError):
            build_packet(0x01, bytes(MAX_PAYLOAD + 1))

    def test_response_reader_skips_noise_and_checks_frame(self):
        payload = b"\x00\xA5\x5A\xFF"
        response = b"\x00\xA5" + build_packet(CMD_DATA, payload)
        self.assertEqual(read_packet(FakeSerial(response)), (CMD_DATA, payload))

    def test_response_reader_rejects_bad_checksum(self):
        response = bytearray(build_packet(CMD_DATA, b"\x42"))
        response[-1] ^= 1
        with self.assertRaisesRegex(ValueError, "checksum"):
            read_packet(FakeSerial(response))

    def test_response_reader_reports_timeout(self):
        with self.assertRaises(TimeoutError):
            read_packet(FakeSerial(b""))


if __name__ == "__main__":
    unittest.main()
