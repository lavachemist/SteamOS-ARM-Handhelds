"""barry_apps: Barry Launcher's user apps, packaged as a zip or tar archive
of a folder and installed into ~/.local/share/barry_launcher/apps/ID.

A package is a folder with barry-app.json at its top (or an archive of
such a folder: the archive may hold it directly or inside one folder):

  {
    "format": 1,
    "id": "io.github.someone.dice",  lower case, dotted (reverse domain)
    "name": "Dice",                  the tile's label, up to 20 characters
    "version": "1.0.0",
    "main": "main.qml",              the app: its root item fills the screen
    "icon": "icon.png",              optional: PNG or SVG, square
    "description": "...", "author": "...", "homepage": "..."   optional
  }

Barry Launcher runs main.qml in a full-screen window of its own
(shell/AppHost.qml), the way it runs its own QML apps. Installing an app
that is already there (same id) updates it and keeps its data
(~/.local/share/barry_launcher/app-data/ID); removing it deletes both.

barry_launcher_shelld lists and starts the installed apps; the barry-app
command and the Barry Launcher Decky plugin install and remove them.
"""
from __future__ import annotations

import json
import os
import re
import shutil
import stat
import tarfile
import tempfile
import zipfile

HOME = os.path.expanduser("~")
DATA = os.path.join(os.environ.get("XDG_DATA_HOME", f"{HOME}/.local/share"), "barry_launcher")
APPS_DIR = os.path.join(DATA, "apps")
APP_DATA_DIR = os.path.join(DATA, "app-data")
MANIFEST = "barry-app.json"
FORMAT = 1
# A dot keeps every user app's id apart from Barry Launcher's own apps.
ID_RE = re.compile(r"^[a-z0-9][a-z0-9_-]*(\.[a-z0-9][a-z0-9_-]*)+$")
ID_MAX = 64
NAME_MAX = 20
ICON_TYPES = (".png", ".svg")
# Limits against an archive that unpacks into far more than it looks.
MAX_ARCHIVE = 100 * 1024 * 1024
MAX_UNPACKED = 300 * 1024 * 1024
MAX_FILES = 5000
ARCHIVE_TYPES = (".zip", ".tar", ".tar.gz", ".tgz", ".tar.xz", ".txz", ".tar.bz2", ".tbz2")


class AppError(Exception):
    """A package that cannot be installed, and why (shown to the user)."""


def _str(m: dict, key: str, required: bool = True) -> str | None:
    v = m.get(key)
    if v is None and not required:
        return None
    if not isinstance(v, str) or not v.strip():
        raise AppError(f'{MANIFEST}: "{key}" must be a non-empty string')
    return v.strip()


def _inside(root: str, rel: str, what: str) -> str:
    """The file rel names in the package at root; it must be in the
    package."""
    if os.path.isabs(rel) or ".." in rel.replace("\\", "/").split("/"):
        raise AppError(f'{MANIFEST}: "{what}" must be a path inside the app folder')
    path = os.path.normpath(os.path.join(root, rel))
    if not os.path.isfile(path):
        raise AppError(f'{MANIFEST}: "{what}" names {rel}, which is not in the app folder')
    return path


def read_manifest(root: str) -> dict:
    """The checked manifest of the app folder at root."""
    try:
        with open(os.path.join(root, MANIFEST), encoding="utf-8") as fh:
            m = json.load(fh)
    except FileNotFoundError:
        raise AppError(f"no {MANIFEST} in the app folder") from None
    except (OSError, ValueError) as err:
        raise AppError(f"cannot read {MANIFEST}: {err}") from None
    if not isinstance(m, dict):
        raise AppError(f"{MANIFEST} must hold a JSON object")
    fmt = m.get("format", FORMAT)
    if fmt != FORMAT:
        raise AppError(f'{MANIFEST}: "format" {fmt!r} is not one this Barry Launcher knows ({FORMAT})')
    app_id = _str(m, "id")
    if len(app_id) > ID_MAX or not ID_RE.match(app_id):
        raise AppError(f'{MANIFEST}: "id" {app_id!r} must be lower case and dotted, like "io.github.you.myapp"')
    name = _str(m, "name")
    if len(name) > NAME_MAX:
        raise AppError(f'{MANIFEST}: "name" is {len(name)} characters; the tile has room for {NAME_MAX}')
    version = _str(m, "version")
    main = _str(m, "main")
    if not main.endswith(".qml"):
        raise AppError(f'{MANIFEST}: "main" must be a .qml file')
    _inside(root, main, "main")
    icon = _str(m, "icon", required=False)
    if icon is not None:
        if not icon.lower().endswith(ICON_TYPES):
            raise AppError(f'{MANIFEST}: "icon" must be a PNG or SVG file')
        _inside(root, icon, "icon")
    out = {"format": FORMAT, "id": app_id, "name": name, "version": version, "main": main, "icon": icon}
    for key in ("description", "author", "homepage"):
        v = m.get(key)
        if isinstance(v, str) and v.strip():
            out[key] = v.strip()
    return out


def _check_member(name: str) -> None:
    parts = name.replace("\\", "/").split("/")
    if name.startswith(("/", "\\")) or ".." in parts or re.match(r"^[A-Za-z]:", name):
        raise AppError(f"the archive has a file outside its folder: {name}")


def _unpack(archive: str, dest: str) -> None:
    """Unpack archive into dest: plain files and folders only, all inside
    dest, within the size limits."""
    size = os.path.getsize(archive)
    if size > MAX_ARCHIVE:
        raise AppError(f"the archive is {size // 1048576} MB; the limit is {MAX_ARCHIVE // 1048576} MB")
    lower = archive.lower()
    total = files = 0
    if lower.endswith(".zip"):
        try:
            zf = zipfile.ZipFile(archive)
        except zipfile.BadZipFile:
            raise AppError("this is not a zip file Barry Launcher can read") from None
        with zf:
            for info in zf.infolist():
                _check_member(info.filename)
                mode = info.external_attr >> 16
                if stat.S_ISLNK(mode):
                    raise AppError(f"the archive has a link, which apps may not have: {info.filename}")
                total += info.file_size
                files += 1
                if total > MAX_UNPACKED or files > MAX_FILES:
                    raise AppError("the archive unpacks into too much")
            zf.extractall(dest)
        return
    if not lower.endswith(ARCHIVE_TYPES):
        raise AppError("apps come as .zip, .tar.gz, .tar.xz or .tar.bz2 archives")
    try:
        tf = tarfile.open(archive)
    except (tarfile.TarError, OSError):
        raise AppError("this is not an archive Barry Launcher can read") from None
    with tf:
        members = tf.getmembers()
        for m in members:
            _check_member(m.name)
            if not (m.isfile() or m.isdir()):
                raise AppError(f"the archive has a link or special file, which apps may not have: {m.name}")
            total += m.size
            files += 1
            if total > MAX_UNPACKED or files > MAX_FILES:
                raise AppError("the archive unpacks into too much")
        for m in members:
            # No owners, modes or times from the archive: plain user files.
            m.mode = 0o755 if m.isdir() else 0o644
            m.uid = m.gid = 0
            m.uname = m.gname = ""
        if hasattr(tarfile, "data_filter"):
            tf.extractall(dest, members, filter="data")
        else:
            tf.extractall(dest, members)


def _package_root(unpacked: str) -> str:
    """Where barry-app.json is: the archive's top, or its one folder."""
    if os.path.isfile(os.path.join(unpacked, MANIFEST)):
        return unpacked
    entries = [e for e in os.listdir(unpacked) if e not in ("__MACOSX", ".DS_Store")]
    if len(entries) == 1 and os.path.isdir(os.path.join(unpacked, entries[0])):
        inner = os.path.join(unpacked, entries[0])
        if os.path.isfile(os.path.join(inner, MANIFEST)):
            return inner
    raise AppError(f"no {MANIFEST} at the top of the archive, or in its one folder")


def check(path: str) -> dict:
    """The manifest of the app in archive or folder path, if it would
    install."""
    if os.path.isdir(path):
        return read_manifest(path)
    with tempfile.TemporaryDirectory(prefix="barry-app-") as tmp:
        _unpack(path, tmp)
        return read_manifest(_package_root(tmp))


def install(archive: str, reserved: set[str] = frozenset()) -> dict:
    """Install (or update) the app in archive; its manifest, with
    "updated": whether it replaced an installed version."""
    if not os.path.isfile(archive):
        raise AppError(f"no file {archive}")
    os.makedirs(APPS_DIR, exist_ok=True)
    tmp = tempfile.mkdtemp(prefix=".new-", dir=APPS_DIR)
    try:
        _unpack(archive, tmp)
        root = _package_root(tmp)
        m = read_manifest(root)
        if m["id"] in reserved:
            raise AppError(f'"{m["id"]}" is one of Barry Launcher\'s own apps')
        dest = os.path.join(APPS_DIR, m["id"])
        old = None
        if os.path.exists(dest):
            old = tempfile.mkdtemp(prefix=".old-", dir=APPS_DIR)
            os.rename(dest, os.path.join(old, "app"))
        os.rename(root, dest)
        os.chmod(dest, 0o755)
        os.makedirs(os.path.join(APP_DATA_DIR, m["id"]), exist_ok=True)
        if old:
            shutil.rmtree(old, ignore_errors=True)
        return dict(m, updated=old is not None)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def remove(app_id: str, keep_data: bool = False) -> bool:
    """Remove an installed app (and its data unless keep_data); False if it
    was not installed."""
    if not ID_RE.match(app_id or ""):
        return False
    dest = os.path.join(APPS_DIR, app_id)
    if not os.path.isdir(dest):
        return False
    shutil.rmtree(dest)
    if not keep_data:
        shutil.rmtree(os.path.join(APP_DATA_DIR, app_id), ignore_errors=True)
    return True


def installed() -> dict[str, dict]:
    """id -> manifest, with "dir", of every installed app that still reads
    cleanly (a broken one is left out)."""
    apps = {}
    try:
        names = sorted(os.listdir(APPS_DIR))
    except OSError:
        return apps
    for name in names:
        root = os.path.join(APPS_DIR, name)
        if name.startswith(".") or not os.path.isdir(root):
            continue
        try:
            m = read_manifest(root)
        except AppError:
            continue
        if m["id"] != name:
            continue
        apps[name] = dict(m, dir=root)
    return apps


def stamp() -> float | None:
    """Changes when an app is installed, updated or removed."""
    try:
        return os.stat(APPS_DIR).st_mtime
    except OSError:
        return None
