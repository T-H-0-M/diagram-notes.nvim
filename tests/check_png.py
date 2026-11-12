from pathlib import Path
import struct
import zlib


def decode(path):
    data = path.read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    compressed = bytearray()
    offset = 8
    while offset < len(data):
        size = struct.unpack_from(">I", data, offset)[0]
        kind = data[offset + 4:offset + 8]
        chunk = data[offset + 8:offset + 8 + size]
        if kind == b"IHDR":
            width, height, depth, colour, compression, filtering, interlace = struct.unpack(">IIBBBBB", chunk)
            assert (depth, colour, compression, filtering, interlace) == (8, 6, 0, 0, 0)
        elif kind == b"IDAT":
            compressed.extend(chunk)
        offset += size + 12
    raw = zlib.decompress(compressed)
    stride = width * 4
    previous = bytearray(stride)
    pixels = bytearray()
    for y in range(height):
        start = y * (stride + 1)
        mode = raw[start]
        assert mode in range(5)
        row = bytearray(raw[start + 1:start + 1 + stride])
        for x in range(stride):
            left = row[x - 4] if x >= 4 else 0
            above = previous[x]
            upper_left = previous[x - 4] if x >= 4 else 0
            if mode == 1:
                predictor = left
            elif mode == 2:
                predictor = above
            elif mode == 3:
                predictor = (left + above) // 2
            elif mode == 4:
                p = left + above - upper_left
                distances = (abs(p - left), abs(p - above), abs(p - upper_left))
                predictor = (left, above, upper_left)[distances.index(min(distances))]
            else:
                predictor = 0
            row[x] = (row[x] + predictor) % 256
        pixels.extend(row)
        previous = row
    return width, height, pixels


path = Path(__file__).resolve().parent.parent / ".deps/render-smoke/overview.png"
width, height, pixels = decode(path)
assert width > 160 and height > 160
assert pixels[3] == 0, "Canvas background is opaque"
assert pixels[(80 * width + 80) * 4 + 3] == 0, "Box interior has a fill"
opaque = [pixels[i:i + 3] for i in range(0, len(pixels), 4) if pixels[i + 3] == 255]
assert len(opaque) > 1000, "Diagram content is missing"
assert all(min(rgb) > 180 for rgb in opaque), "Opaque dark pixels remain"
print("PASS transparent canvas and box interior, with light text and outlines")
