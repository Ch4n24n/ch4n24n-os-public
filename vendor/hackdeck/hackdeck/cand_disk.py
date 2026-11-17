"""変数の候補: いま認識しているディスクと、いまマウントしている所。

physical の disks は ntfs-3g の対象、mntdirs は ntfs-3g のマウント先（/mnt 直下）、mounts は chntpw・umount
（2026-11-17、本人「このSSDにはマウントされているディレクトリが他にもあるだろ？」「ntfs-3gも書き換わったんだ？
ここにはマウント候補が乗るはずだろ？/mnt配下のディレクトリが乗るのは正しいだろ？」）。mounts は findmnt（無ければ
/proc/self/mounts）の /dev の実マウント（/ や /boot/efi も含む）。lsblk・findmnt が無い・読めないときは空。"""
import json
import os
import subprocess
from pathlib import Path

from .text import out


# マウント対象にならないファイルシステム（ライブの squash・光学メディア・swap）
_SKIP_FS = {"swap", "squashfs", "iso9660"}
# proc・sys・tmpfs・docker など、ディスクの実マウントではないもの
_SKIP_MNT_FS = {
    "proc", "sysfs", "devtmpfs", "devpts", "tmpfs", "cgroup", "cgroup2", "overlay", "squashfs",
    "iso9660", "autofs", "bpf", "debugfs", "tracefs", "securityfs", "pstore", "efivarfs",
    "fusectl", "mqueue", "hugetlbfs", "configfs", "binfmt_misc", "rpc_pipefs", "nsfs", "nfsd",
}


def _json_cmd(argv):
    """外部コマンドの JSON。失敗・空・壊れた JSON は None。"""
    try:
        r = subprocess.run(argv, capture_output=True, text=True)
    except OSError:
        return None
    if not r.stdout.strip():
        return None
    try:
        return json.loads(r.stdout)
    except json.JSONDecodeError:
        return None


def _walk(nodes, acc):
    for n in nodes:
        acc.append(n)
        _walk(n.get("children") or [], acc)


def _mountpoint(node):
    """lsblk の JSON は版によって mountpoint（文字列）か mountpoints（配列）。"""
    m = node.get("mountpoint")
    if m:
        return m
    for x in node.get("mountpoints") or []:
        if x:
            return x
    return ""


def disk_rows():
    """(デバイス, 説明)。ファイルシステムがあるブロック。swap・squashfs・iso9660 は出さない。"""
    data = _json_cmd(["lsblk", "-J", "-p", "-o", "NAME,FSTYPE,LABEL,SIZE,TYPE,MOUNTPOINT"])
    if not data:
        return []
    nodes = []
    _walk(data.get("blockdevices") or [], nodes)
    rows = []
    for n in nodes:
        path = n.get("name") or ""
        fstype = n.get("fstype") or ""
        if not path or not fstype or fstype.lower() in _SKIP_FS:
            continue
        bits = [fstype]
        if n.get("label"):
            bits.append(n["label"])
        if n.get("size"):
            bits.append(n["size"])
        mp = _mountpoint(n)
        bits.append(mp if mp else "未マウント")
        rows.append((path, "  ".join(bits)))
    return rows


def _unproc(s):
    return s.replace("\\040", " ").replace("\\011", "\t").replace("\\012", "\n").replace("\\134", "\\")


def _findmnt_rows():
    """(target, source, fstype, label)。findmnt が無ければ /proc/self/mounts。"""
    data = _json_cmd(["findmnt", "-J", "-l", "-o", "TARGET,SOURCE,FSTYPE,LABEL"])
    if data:
        rows = []
        for n in data.get("filesystems") or []:
            rows.append((n.get("target") or "", n.get("source") or "", n.get("fstype") or "", n.get("label") or ""))
        return rows
    try:
        lines = Path("/proc/self/mounts").read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return []
    rows = []
    for line in lines:
        p = line.split()
        if len(p) >= 3:
            rows.append((_unproc(p[1]), _unproc(p[0]), p[2], ""))
    return rows


def _disk_mount(source, fstype):
    """ブロックデバイス（/dev/…）か NTFS の実マウント。/proc や tmpfs は出さない。"""
    fs = (fstype or "").lower()
    if fs in _SKIP_MNT_FS or fs.startswith("fuse."):
        return False
    src = source or ""
    if src.startswith("/dev/"):
        return True
    return fs in {"ntfs", "ntfs3", "fuseblk"}


def _has_sam(target):
    try:
        return os.path.isfile(os.path.join(target, "Windows", "System32", "config", "SAM"))
    except OSError:
        return False


def mount_rows():
    """(パス, 説明)。findmnt（無ければ /proc/self/mounts）の、ディスクの実マウント。フォルダの中身は見ない。"""
    mounted, seen = [], set()
    for target, source, fstype, label in _findmnt_rows():
        if not target or not _disk_mount(source, fstype) or target in seen:
            continue
        seen.add(target)
        bits = [fstype] if fstype else []
        if label:
            bits.append(label)
        if source:
            bits.append(source)
        sam = _has_sam(target)
        if sam:
            bits.append("Windows")
        mounted.append((target, "  ".join(bits), sam))
    mounted.sort(key=lambda r: (not r[2], r[0]))
    return [(t, d) for t, d, _ in mounted]


def mntdir_rows():
    """/mnt 直下のフォルダ。まだ無い /mnt/win も先頭に出す。"""
    seen, rows = set(), []
    rows.append(("/mnt/win", ""))
    seen.add("/mnt/win")
    try:
        for p in sorted(Path("/mnt").iterdir()):
            if p.name.startswith(".") or not p.is_dir():
                continue
            s = str(p)
            if s not in seen:
                rows.append((s, ""))
                seen.add(s)
    except OSError:
        pass
    return rows


def c_disks():
    """いま認識しているディスク（ntfs-3g の対象）。"""
    for v, d in disk_rows():
        out(v, d)


def c_mounts():
    """いまマウントしている所（chntpw・umount）。findmnt のディスクの実マウント。"""
    for v, d in mount_rows():
        out(v, d)


def c_mntdirs():
    """ntfs-3g のマウント先。/mnt 直下のフォルダ。"""
    for v, d in mntdir_rows():
        out(v, d)
