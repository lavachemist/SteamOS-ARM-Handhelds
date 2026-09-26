#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Read and patch the ROCKNIX ABL KERNEL (Android boot image, header v0).

  ufs-bootimg.py cmdline KERNEL             print the cmdline
  ufs-bootimg.py set-cmdline SRC DST LINE   copy SRC to DST with a new cmdline
  ufs-bootimg.py initramfs-has-partlabel KERNEL
                                            exit 0 if the initramfs can mount root=PARTLABEL=

The cmdline is patched in place like make-steamos-sm8650.sh does, so the
kernel, appended DTBs and initramfs stay byte-identical. ABL only reads the
first 512-byte cmdline field.
"""

import gzip
import struct
import sys
from pathlib import Path

MAGIC = b"ANDROID!"
CMDLINE_OFF, CMDLINE_LEN = 0x40, 512


def load(path):
    data = bytearray(Path(path).read_bytes())
    if len(data) < 0x800 or data[:8] != MAGIC:
        raise SystemExit(f"{path}: not an Android boot image")
    return data


def cmdline(data):
    return bytes(data[CMDLINE_OFF:CMDLINE_OFF + CMDLINE_LEN]).split(b"\0", 1)[0].decode("ascii")


def ramdisk(data):
    kernel_size, _, ramdisk_size = struct.unpack_from("<3I", data, 8)
    page = struct.unpack_from("<I", data, 36)[0]
    if page not in (2048, 4096, 16384):
        raise SystemExit(f"unexpected page size {page}")
    start = page * (1 + (kernel_size + page - 1) // page)
    blob = bytes(data[start:start + ramdisk_size])
    try:
        return gzip.decompress(blob)
    except OSError:
        return blob


def main(argv):
    if len(argv) == 2 and argv[0] == "cmdline":
        print(cmdline(load(argv[1])))
    elif len(argv) == 4 and argv[0] == "set-cmdline":
        data = load(argv[1])
        new = argv[3].encode("ascii")
        if len(new) >= CMDLINE_LEN:
            raise SystemExit(f"cmdline too long ({len(new)} >= {CMDLINE_LEN})")
        data[CMDLINE_OFF:CMDLINE_OFF + CMDLINE_LEN] = new.ljust(CMDLINE_LEN, b"\0")
        Path(argv[2]).write_bytes(data)
    elif len(argv) == 2 and argv[0] == "initramfs-has-partlabel":
        # initramfs/init handles root=PARTLABEL=<name> (waits for UFS, bootlog on ROCKNIX).
        return 0 if b"PARTLABEL=" in ramdisk(load(argv[1])) else 1
    else:
        print(__doc__, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
