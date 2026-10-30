SYNC = b'\xA5\x5A'  # First 2 bytes, FPGA is expecting this so it can sync to new packet
MAX_PAYLOAD = 256

def build_packet(command, payload=b''): # payload = b'' means it takes in full bytes, i.e. chunks of 8 bits
    if len(payload) > MAX_PAYLOAD:
        raise ValueError("Payload too large")

    length = len(payload).to_bytes(2, 'little') # 'little' means little-endian. Converts payload length into 2-byte representation
    body = bytes([command]) + length + payload

    checksum = 0
    for byte in body:
        checksum ^= byte

    return SYNC + body + bytes([checksum])
