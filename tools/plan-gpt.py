"""Calculate a Topaz 256 GB GPT from the owner's untouched recovery snapshots.

Never opens a disk for writing. A separate Windows script compares those
snapshots with the live USB mass-storage device before writing.
"""

import argparse
import hashlib
import json
import struct
import uuid
import zlib
from pathlib import Path

SECTOR = 4096
SECTORS = 61937664
SNAPSHOT_SECTORS = 64
PRIMARY_HEADER = 1
SECONDARY_HEADER = SECTORS - 1
PRIMARY_TABLE = 2
SECONDARY_TABLE = SECTORS - 5
FIRST_USABLE = 6
LAST_USABLE = SECTORS - 6
ENTRY_SIZE = 128
USERDATA_START = 2565160
ESP_START = 23536896
WINDOWS_START = ESP_START + 131072
USERDATA_TYPE = uuid.UUID("1b81e7e6-f50d-419b-a739-2aeef8da3335")
EXPECTED_NAMES = [
    "ssd", "persist", "misc", "countrycode", "keystore", "frp", "minidump",
    "cust", "super", "vbmeta_system_a", "vbmeta_system_b", "metadata",
    "rescue", "mem", "gsort", "ffu", "opcust", "opconfig", "userdata",
]


def require(condition, message):
    if not condition:
        raise ValueError(message)


def stock_header(snapshot, start, own_lba, peer_lba, table_lba):
    offset = (own_lba - start) * SECTOR
    header = snapshot[offset:offset + SECTOR]
    require(header[:8] == b"EFI PART", "Missing GPT header")
    version, size, saved_crc = struct.unpack_from("<III", header, 8)
    require(version == 0x10000 and size == 92, "Unexpected GPT header version or size")
    checked = bytearray(header[:size])
    struct.pack_into("<I", checked, 16, 0)
    require(zlib.crc32(checked) == saved_crc, "GPT header CRC mismatch")
    require(struct.unpack_from("<QQQQ", header, 24) ==
            (own_lba, peer_lba, FIRST_USABLE, LAST_USABLE), "Unexpected disk geometry")
    lba, count, width, crc = struct.unpack_from("<QIII", header, 72)
    require(lba == table_lba and count in (32, 128) and width == ENTRY_SIZE,
            "Unexpected GPT entries location or size")
    offset = (lba - start) * SECTOR
    entries = snapshot[offset:offset + count * width]
    require(zlib.crc32(entries) == crc, "GPT entries CRC mismatch")
    return header, entries


def replace_header(original, table_lba, entries, last_usable=LAST_USABLE):
    header = bytearray(original)
    struct.pack_into("<Q", header, 48, last_usable)
    struct.pack_into("<QIII", header, 72, table_lba, len(entries) // ENTRY_SIZE,
                     ENTRY_SIZE, zlib.crc32(entries))
    struct.pack_into("<I", header, 16, 0)
    struct.pack_into("<I", header, 16, zlib.crc32(header[:92]))
    return header


def create_entry(type_guid, start, end, name):
    entry = bytearray(ENTRY_SIZE)
    entry[:16] = uuid.UUID(type_guid).bytes_le
    entry[16:32] = uuid.uuid4().bytes_le
    struct.pack_into("<QQ", entry, 32, start, end)
    encoded = name.encode("utf-16-le")
    entry[56:56 + len(encoded)] = encoded
    return entry


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def make_plan(first, last, output):
    require(len(first) == len(last) == SNAPSHOT_SECTORS * SECTOR,
            "Both snapshots must cover exactly 64 sectors")
    require(first[510:512] == b"\x55\xaa" and first[450] == 0xEE,
            "Missing protective MBR")
    primary, original = stock_header(first, 0, PRIMARY_HEADER, SECONDARY_HEADER, PRIMARY_TABLE)
    secondary, mirror = stock_header(last, SECTORS - SNAPSHOT_SECTORS,
                                     SECONDARY_HEADER, PRIMARY_HEADER, SECONDARY_TABLE)
    require(original == mirror and primary[56:72] == secondary[56:72],
            "The two GPT copies disagree")
    require(not any(original[19 * ENTRY_SIZE:]), "Unexpected entries after userdata")

    previous_end = FIRST_USABLE - 1
    for index, expected in enumerate(EXPECTED_NAMES):
        entry = original[index * ENTRY_SIZE:(index + 1) * ENTRY_SIZE]
        name = entry[56:].decode("utf-16-le").rstrip("\0")
        require(name == expected, f"Partition {index + 1}: expected {expected}, found {name}")
        start, end = struct.unpack_from("<QQ", entry, 32)
        require(previous_end < start <= end <= LAST_USABLE, f"Invalid extents for {name}")
        previous_end = end
    userdata = original[18 * ENTRY_SIZE:19 * ENTRY_SIZE]
    require(uuid.UUID(bytes_le=userdata[:16]) == USERDATA_TYPE and
            struct.unpack_from("<QQ", userdata, 32) == (USERDATA_START, LAST_USABLE),
            "Expected an untouched userdata partition")

    entries = bytearray(original.ljust(128 * ENTRY_SIZE, b"\0"))
    struct.pack_into("<Q", entries, 18 * ENTRY_SIZE + 40, ESP_START - 1)
    entries[19 * ENTRY_SIZE:20 * ENTRY_SIZE] = create_entry(
        "c12a7328-f81f-11d2-ba4b-00a0c93ec93b", ESP_START, WINDOWS_START - 1, "esp")
    entries[20 * ENTRY_SIZE:21 * ENTRY_SIZE] = create_entry(
        "ebd0a0a2-b9e5-4433-87c0-68b6b72699c7", WINDOWS_START, LAST_USABLE, "win")
    writes = [
        ("secondary-entries.bin", SECONDARY_TABLE, entries),
        ("secondary-header.bin", SECONDARY_HEADER, replace_header(secondary, SECONDARY_TABLE, entries)),
        ("primary-entries.bin", PRIMARY_TABLE, entries),
        ("primary-header.bin", PRIMARY_HEADER, replace_header(primary, PRIMARY_TABLE, entries)),
    ]

    allowed = [{"first": sha256(first), "last": sha256(last)}]
    if len(original) == SECTOR:
        # The tested UMS path moved the advertised 32-entry arrays to LBA 5
        # and end-1. The old primary array was still at LBA 2.
        moved_first = bytearray(first)
        moved_last = bytearray(last)
        moved_first[SECTOR:2 * SECTOR] = replace_header(primary, 5, original, SECTORS - 3)
        moved_last[-2 * SECTOR:-SECTOR] = original
        moved_last[-SECTOR:] = replace_header(secondary, SECTORS - 2, original, SECTORS - 3)
        allowed.append({"first": sha256(moved_first), "last": sha256(moved_last)})

    # Keep the snapshots and corresponding plan together on the local PC.
    output.mkdir()
    for name, _, data in writes:
        (output / name).write_bytes(data)
    (output / "original-first64.bin").write_bytes(first)
    (output / "original-last64.bin").write_bytes(last)
    metadata = {
        "diskGuid": str(uuid.UUID(bytes_le=primary[56:72])),
        "allowedSnapshots": allowed,
        "writes": [{"name": name, "lba": lba, "bytes": len(data), "sha256": sha256(data)}
                   for name, lba, data in writes],
    }
    (output / "plan.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")

    print("Verified 256 GB Topaz layout. No disk writes performed.")
    print(f"19 userdata  {USERDATA_START}..{ESP_START - 1}")
    print(f"20 esp       {ESP_START}..{WINDOWS_START - 1}")
    print(f"21 win       {WINDOWS_START}..{LAST_USABLE}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("first64", type=Path)
    parser.add_argument("last64", type=Path)
    parser.add_argument("new_plan_directory", type=Path)
    args = parser.parse_args()
    try:
        make_plan(args.first64.read_bytes(), args.last64.read_bytes(), args.new_plan_directory)
    except (OSError, ValueError) as error:
        parser.exit(1, f"GPT plan refused: {error}\n")


if __name__ == "__main__":
    main()
