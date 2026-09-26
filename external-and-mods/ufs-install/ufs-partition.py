#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Inspect and repartition internal UFS for the SteamOS SM8650 install.

Splits Android userdata into userdata + ROCKNIX (FAT, ABL reads KERNEL) +
STORAGE (ext4 root) + HOME (ext4 /home). The whole GPT is rewritten in one
sfdisk call from a validated snapshot: every other partition keeps its
number, type, GUID and attributes, and userdata only changes its end.

Table validation, the sfdisk plan and the post-write checks are adapted from
Armada's armada-installer (https://github.com/armada-os/armada,
GPL-2.0-or-later).

  ufs-partition.py detect                 KEY=value lines (mode=fresh|installed|occupied|toosmall)
  ufs-partition.py partition --android-gib N [--expect-table FP] [--dry-run]
"""

import argparse
from dataclasses import asdict, dataclass, replace
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

MIB = 1024**2
GIB = 1024**3


def env_gib(name, default):
    value = os.environ.get(name, "")
    return int(value) if re.fullmatch(r"[1-9][0-9]*", value) else default


BOOT_GIB = 2
ROOT_GIB = env_gib("ROOT_PART_GIB", 16)
MIN_HOME_GIB = env_gib("MIN_HOME_GIB", 16)
ANDROID_MIN_GIB = 16
ANDROID_RECOMMENDED_GIB = 64
BOOT_SIZE, ROOT_SIZE = BOOT_GIB * GIB, ROOT_GIB * GIB
RESERVE = BOOT_SIZE + ROOT_SIZE + MIN_HOME_GIB * GIB + 64 * MIB
# ABL 1.1.8 boots the FAT partition that follows userdata (Armada uses the ESP
# type for it on SM8650). STORAGE and HOME are plain Linux filesystems.
ESP_TYPE = "c12a7328-f81f-11d2-ba4b-00a0c93ec93b"
LINUX_TYPE = "0fc63daf-8483-4772-8e79-3d69d8477de4"
LINUX_NAMES = ("ROCKNIX", "STORAGE", "HOME")


class Error(Exception):
    pass


def run(*args, input=None):
    proc = subprocess.run([str(a) for a in args], text=True, input=input,
                          capture_output=True, check=False)
    if proc.returncode:
        raise Error(f"{' '.join(str(a) for a in args)} failed ({proc.returncode}): "
                    f"{(proc.stderr or proc.stdout).strip()}")
    return proc.stdout


def part_node(device, number):
    return f"{device}{'p' if device[-1].isdigit() else ''}{number}"


def align_up(value):
    return (value + MIB - 1) // MIB * MIB


@dataclass(frozen=True)
class Partition:
    number: int
    start: int
    end: int
    name: str
    type: str
    uuid: str = ""
    attrs: str = ""


@dataclass(frozen=True)
class Table:
    device: str
    sector_size: int
    first: int
    last: int
    disk_id: str
    parts: tuple
    entry_count: int = 128
    unused: tuple = ()

    @classmethod
    def parse(cls, device, data):
        try:
            t = data["partitiontable"]
            sector = t["sectorsize"]
            if (t["label"] != "gpt" or t["unit"] != "sectors" or t["device"] != device
                    or type(sector) is not int or sector not in (512, 4096)):
                raise ValueError("expected a GPT disk with 512 or 4096 byte sectors")
            first, last = t["firstlba"], t["lastlba"]
            if type(first) is not int or type(last) is not int or not 0 < first < last:
                raise ValueError("invalid usable disk bounds")
            count = t.get("table-length", 128)
            if not re.fullmatch(r"[1-9][0-9]*", str(count)) or int(count) > 2**32 - 1:
                raise ValueError("invalid GPT entry count")
            count = int(count)
            parts, unused = [], []
            for p in t["partitions"]:
                match = re.fullmatch(re.escape(device) + ("p" if device[-1].isdigit() else "")
                                     + r"([1-9][0-9]*)", p["node"])
                if not match or int(match[1]) > count:
                    raise ValueError("invalid partition number")
                if p["type"] == "00000000-0000-0000-0000-000000000000":
                    unused.append(int(match[1]))
                    continue
                if type(p["start"]) is not int or type(p["size"]) is not int or p["size"] <= 0:
                    raise ValueError("invalid partition extent")
                if not isinstance(p.get("name", ""), str):
                    raise ValueError("invalid partition name")
                parts.append(Partition(int(match[1]), p["start"], p["start"] + p["size"],
                                       p.get("name", ""), p["type"].lower(), p["uuid"].lower(),
                                       p.get("attrs", "")))
            ordered = sorted(parts, key=lambda p: p.start)
            if (len({p.number for p in parts} | set(unused)) != len(parts) + len(unused)
                    or any(p.start < first or p.end > last + 1 for p in parts)
                    or any(a.end > b.start for a, b in zip(ordered, ordered[1:]))):
                raise ValueError("overlapping or out-of-bounds partitions")
            return cls(device, sector, first, last, t["id"].lower(),
                       tuple(sorted(parts, key=lambda p: p.number)), count, tuple(sorted(unused)))
        except (KeyError, TypeError, ValueError, AttributeError) as error:
            raise Error(f"Could not validate the partition table: {error}") from error

    def layout(self):
        userdata = [p for p in self.parts if p.name == "userdata"]
        if len(userdata) != 1:
            raise Error("Expected exactly one Android userdata partition")
        userdata = userdata[0]
        tail = tuple(sorted((p for p in self.parts if p.start >= userdata.end), key=lambda p: p.start))
        return userdata, tail

    def gib(self, sectors):
        return sectors * self.sector_size // GIB

    def info(self):
        userdata, tail = self.layout()
        disk_end = max(p.end for p in (userdata, *tail))
        info = dict(device=self.device, sector_size=self.sector_size,
                    disk_total_gib=self.gib(self.last + 1),
                    android_current_gib=self.gib(userdata.end - userdata.start),
                    android_min_gib=ANDROID_MIN_GIB, boot_gib=BOOT_GIB, root_gib=ROOT_GIB,
                    min_home_gib=MIN_HOME_GIB, userdata=part_node(self.device, userdata.number))
        if tail:
            info["tail"] = ", ".join(f"{part_node(self.device, p.number)} ({p.name or 'unnamed'})"
                                     for p in tail)
            # ROCKNIX + STORAGE + HOME in that order is this installer's own layout.
            info["mode"] = "installed" if tuple(p.name for p in tail) == LINUX_NAMES else "occupied"
            for p in tail:
                if p.name in LINUX_NAMES:
                    info[p.name.lower()] = part_node(self.device, p.number)
            return info
        maximum = ((disk_end * self.sector_size // MIB * MIB)
                   - align_up(userdata.start * self.sector_size) - RESERVE) // GIB
        if maximum < ANDROID_MIN_GIB:
            info.update(mode="toosmall", needed_gib=ANDROID_MIN_GIB + RESERVE // GIB)
            return info
        info.update(mode="fresh", android_max_gib=maximum,
                    android_recommended_gib=max(ANDROID_MIN_GIB, min(maximum, ANDROID_RECOMMENDED_GIB)))
        return info


def read_table(device):
    try:
        return Table.parse(device, json.loads(run("sfdisk", "--json", device)))
    except ValueError as error:
        raise Error(f"Invalid partition table output: {error}") from error


def table_fingerprint(table):
    ident = os.stat(table.device).st_rdev
    seq = Path("/sys/dev/block") / f"{os.major(ident)}:{os.minor(ident)}" / "diskseq"
    diskseq = seq.read_text().strip() if seq.exists() else ""
    data = dict(table=asdict(table), device_id=ident, disk_sequence=diskseq)
    return hashlib.sha256(json.dumps(data, sort_keys=True).encode()).hexdigest()


@dataclass(frozen=True)
class Plan:
    table: Table
    userdata: Partition
    userdata_end: int
    create: tuple

    @classmethod
    def make(cls, table, android_gib):
        info = table.info()
        if info["mode"] != "fresh":
            raise Error(f"Internal storage is not ready for a fresh install (layout: {info['mode']})")
        if type(android_gib) is not int or not ANDROID_MIN_GIB <= android_gib <= info["android_max_gib"]:
            raise Error(f"Android size must be {ANDROID_MIN_GIB}..{info['android_max_gib']} GiB")
        userdata, _ = table.layout()
        sector = table.sector_size
        ud_end = (align_up(userdata.start * sector) + android_gib * GIB) // sector
        end = userdata.end * sector // MIB * MIB // sector
        boot_end = ud_end + BOOT_SIZE // sector
        root_end = boot_end + ROOT_SIZE // sector
        if (end - root_end) * sector < MIN_HOME_GIB * GIB:
            raise Error("Not enough space left for HOME; choose a smaller Android size")
        used = {p.number for p in table.parts}
        preferred = [userdata.number + offset for offset in (1, 2, 3)]
        free = [n for n in range(1, table.entry_count + 1) if n not in used]
        numbers = preferred if all(n in free for n in preferred) else free[:3]
        if len(numbers) != 3:
            raise Error("Not enough free GPT partition slots")
        create = (Partition(numbers[0], ud_end, boot_end, "ROCKNIX", ESP_TYPE),
                  Partition(numbers[1], boot_end, root_end, "STORAGE", LINUX_TYPE),
                  Partition(numbers[2], root_end, end, "HOME", LINUX_TYPE))
        return cls(table, userdata, ud_end, create)

    def script(self):
        table = self.table
        lines = ["label: gpt", f"label-id: {table.disk_id}", "unit: sectors",
                 f"first-lba: {table.first}", f"last-lba: {table.last}",
                 f"sector-size: {table.sector_size}", f"table-length: {table.entry_count}"]
        parts = [replace(p, end=self.userdata_end) if p == self.userdata else p
                 for p in table.parts] + list(self.create)
        for p in sorted(parts, key=lambda p: p.number):
            name = re.sub(r'["\\\x00-\x1f]', lambda m: f"\\x{ord(m[0]):02x}", p.name)
            fields = [f"start={p.start}", f"size={p.end - p.start}", f"type={p.type}", f'name="{name}"']
            if p.uuid:
                fields.append("uuid=" + p.uuid)
            if p.attrs:
                fields.append("attrs=" + json.dumps(p.attrs))
            lines.append(part_node(table.device, p.number) + ": " + ", ".join(fields))
        return "\n".join(lines) + "\n"

    def describe(self):
        t = self.table
        rows = [("userdata", self.userdata.number, self.userdata.start, self.userdata_end),
                *((p.name, p.number, p.start, p.end) for p in self.create)]
        return "\n".join(f"  {name:<9} {part_node(t.device, num):<14} {(end - start) * t.sector_size / GIB:8.1f} GiB"
                         for name, num, start, end in rows)

    def write(self):
        run("sfdisk", "--no-reread", "--no-tell-kernel", "--wipe=never", "--wipe-partitions=never",
            self.table.device, input=self.script())

    def verify(self, actual):
        t = self.table
        expected = {p.number: p for p in t.parts}
        expected[self.userdata.number] = replace(self.userdata, end=self.userdata_end)
        new = {p.number: p for p in self.create}
        if ((actual.device, actual.sector_size, actual.first, actual.last, actual.disk_id, actual.entry_count)
                != (t.device, t.sector_size, t.first, t.last, t.disk_id, t.entry_count)
                or actual.unused or {p.number for p in actual.parts} != expected.keys() | new.keys()):
            raise Error("Partition table does not match the installation plan")
        for p in actual.parts:
            wanted = new.get(p.number)
            if (wanted and replace(p, uuid="", attrs="") != wanted) or (not wanted and p != expected[p.number]):
                raise Error(f"Partition {p.number} does not match the installation plan")

    def verify_kernel(self):
        for p in (replace(self.userdata, end=self.userdata_end), *self.create):
            node = part_node(self.table.device, p.number)
            path = Path("/sys/class/block") / Path(self.table.device).name / Path(node).name
            try:
                ident = os.stat(node).st_rdev
                device_id = (path / "dev").read_text().strip()
                # Sysfs uses 512-byte sectors even on 4K-sector UFS.
                start = int((path / "start").read_text()) * 512
                size = int((path / "size").read_text()) * 512
            except (OSError, ValueError) as error:
                raise Error(f"Could not verify the kernel partition mapping for {node}: {error}") from error
            if (device_id != f"{os.major(ident)}:{os.minor(ident)}"
                    or start != p.start * self.table.sector_size
                    or size != (p.end - p.start) * self.table.sector_size):
                raise Error(f"Kernel partition mapping for {node} does not match the installation plan")


def discover_device(override=None):
    if override:
        device = str(Path(override).resolve(strict=True))
    else:
        disks = json.loads(run("lsblk", "--json", "--paths", "--output", "NAME,TYPE,PARTLABEL"))["blockdevices"]
        candidates = [d["name"] for d in disks if d["type"] == "disk"
                      and any(p.get("partlabel") == "userdata" for p in d.get("children", []))]
        if len(candidates) != 1:
            raise Error("Could not uniquely identify internal UFS (need exactly one disk with a "
                        "userdata partition); pass --device")
        device = candidates[0]
    # A loop device is only accepted when named explicitly (testing on an image).
    allowed = ("disk", "loop") if override else ("disk",)
    if not Path(device).is_block_device() or run("lsblk", "-dnro", "TYPE", device).strip() not in allowed:
        raise Error(f"{device} is not a whole block device")
    return device


def refuse_boot_disk(device):
    source = run("findmnt", "--noheadings", "--output", "SOURCE", "--target", "/").strip().split("[", 1)[0]
    if not Path(source).is_block_device():
        raise Error("Cannot determine the boot disk; refusing to modify internal storage")
    ancestors = run("lsblk", "--inverse", "--noheadings", "--raw", "--output", "MAJ:MIN", source).split()
    ident = os.stat(device).st_rdev
    if not ancestors or f"{os.major(ident)}:{os.minor(ident)}" in ancestors:
        raise Error("Refusing to modify the disk the running system booted from; boot from microSD")


def require_idle(plan):
    mounted = {line.split()[2] for path in ("/proc/1/mountinfo", "/proc/self/mountinfo")
               for line in Path(path).read_text().splitlines()}
    swaps = {os.stat(line.split()[0]).st_rdev for line in Path("/proc/swaps").read_text().splitlines()[1:]}
    node = part_node(plan.table.device, plan.userdata.number)
    ident = os.stat(node).st_rdev
    key = f"{os.major(ident)}:{os.minor(ident)}"
    if key in mounted or ident in swaps or any((Path("/sys/dev/block") / key / "holders").iterdir()):
        raise Error(f"{node} is in use; unmount it before continuing")


def partition(args):
    device = discover_device(args.device)
    table = read_table(device)
    if args.expect_table and args.expect_table != table_fingerprint(table):
        raise Error("The partition table changed since it was inspected; start the installer again")
    plan = Plan.make(table, args.android_gib)
    print("Partition plan:", file=sys.stderr)
    print(plan.describe(), file=sys.stderr)
    if args.dry_run:
        print("[dry-run] sfdisk script:\n" + plan.script(), file=sys.stderr)
    else:
        if os.geteuid() != 0:
            raise Error("partition must run as root")
        refuse_boot_disk(device)
        if read_table(device) != table:
            raise Error("The partition table changed after inspection; start the installer again")
        require_idle(plan)
        plan.write()
        run("partprobe", device)
        run("udevadm", "settle")
        plan.verify(read_table(device))
        plan.verify_kernel()
        # Android re-creates its filesystem; stale headers would confuse it.
        with open(part_node(device, plan.userdata.number), "r+b") as dev:
            dev.write(b"\0" * 8 * MIB)
            dev.flush()
            os.fsync(dev.fileno())
    print(f"SECTOR_SIZE={table.sector_size}")
    for p in plan.create:
        print(f"{p.name}={part_node(device, p.number)}")
    print(f"USERDATA={part_node(device, plan.userdata.number)}")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--device", default=os.environ.get("UFS_DEVICE"))
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("detect", help="inspect internal UFS without changing it")
    p = commands.add_parser("partition", help="split userdata into userdata + ROCKNIX + STORAGE + HOME")
    p.add_argument("--android-gib", type=int, required=True)
    p.add_argument("--expect-table", help="fingerprint printed by detect")
    p.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)
    try:
        if args.command == "detect":
            table = read_table(discover_device(args.device))
            info = table.info()
            info["table_fingerprint"] = table_fingerprint(table)
            for key, value in info.items():
                print(f"{key.upper()}={value}")
        else:
            partition(args)
        return 0
    except Error as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
