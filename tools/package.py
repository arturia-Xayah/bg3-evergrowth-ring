"""Small deterministic LSPK v18 writer, following Norbyte/LSLib's layout.

Stores payloads uncompressed; the file table is a valid literal-only LZ4
block. Includes LSLib's 64-byte alignment and content-MD5-plus-one convention.
No external dependencies; intentionally limited to small single-part mods.
"""
import hashlib
import struct
from pathlib import Path


def lz4_literals(data):
    length = len(data)
    out = bytearray([min(length, 15) << 4])
    if length >= 15:
        remaining = length - 15
        while remaining >= 255:
            out.append(255)
            remaining -= 255
        out.append(remaining)
    return bytes(out) + data


def pack(source, destination):
    files = sorted(p for p in Path(source).rglob("*") if p.is_file()
                   and (p.suffix not in {".lsx", ".xml"} or p.name == "meta.lsx"))
    # Authoring XML is excluded. The engine consumes compiled LSF and LOCA.
    files = [p for p in files if not any(part.startswith(".") for part in p.relative_to(source).parts)]
    header = struct.Struct("<4sIQIBB16sH")
    entry = struct.Struct("<256sIHBBII")
    payload, table, md5 = bytearray(), bytearray(), hashlib.md5()
    expected = {}
    for path in files:
        name = path.relative_to(source).as_posix()
        encoded = name.encode("utf-8")
        assert len(encoded) < 256, name
        data = path.read_bytes()
        offset = header.size + len(payload)
        assert offset < 2**32 and len(data) < 2**32
        table += entry.pack(encoded.ljust(256, b"\0"), offset, 0, 0, 0, len(data), 0)
        payload += data
        payload += b"\xad" * ((-len(payload)) % 64)
        md5.update(data)
        expected[name] = hashlib.sha256(data).hexdigest()
    compressed = lz4_literals(bytes(table))
    file_list = struct.pack("<II", len(files), len(compressed)) + compressed
    checksum = bytes((b + 1) % 256 for b in md5.digest())
    result = header.pack(b"LSPK", 18, header.size + len(payload), len(file_list), 0, 0, checksum, 1)
    Path(destination).write_bytes(result + payload + file_list)
    return expected
