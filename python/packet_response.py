from packet_controller import MAX_PAYLOAD, SYNC


def _read_exactly(serial_port, count):
    data = bytearray()
    while len(data) < count:
        chunk = serial_port.read(count - len(data))
        if not chunk:
            raise TimeoutError(f"Timed out after receiving {len(data)} of {count} bytes")
        data.extend(chunk)
    return bytes(data)


def read_packet(serial_port):
    """Read one framed packet, skipping bytes until the A5 5A sync marker."""
    matched = 0
    while matched < len(SYNC):
        value = _read_exactly(serial_port, 1)[0]
        if matched == 0:
            matched = 1 if value == SYNC[0] else 0
        elif value == SYNC[1]:
            matched = 2
        else:
            matched = 1 if value == SYNC[0] else 0

    header = _read_exactly(serial_port, 3)  # command, length low, length high
    command = header[0]
    length = header[1] | (header[2] << 8)
    if length > MAX_PAYLOAD:
        raise ValueError(f"Response payload too large: {length} bytes")

    payload_and_checksum = _read_exactly(serial_port, length + 1)
    payload = payload_and_checksum[:-1]
    checksum = 0
    for byte in header + payload:
        checksum ^= byte
    if checksum != payload_and_checksum[-1]:
        raise ValueError("Response checksum mismatch")

    return command, payload
