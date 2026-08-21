#!/usr/bin/env python3
"""Append, replace, or remove a marked o.bind block in ~/.config/hypr/bindings.lua.

Never writes hl.unbind. Only the marked plugin block is touched.
"""

import os
import stat
import tempfile
import sys



def _refuse_symlink(path: str) -> None:
    try:
        st = os.lstat(path)
    except FileNotFoundError:
        return
    if stat.S_ISLNK(st.st_mode):
        raise OSError("refusing symlink: %s" % path)
    if not stat.S_ISREG(st.st_mode):
        raise OSError("not a regular file: %s" % path)


def read_text_nofollow(path: str) -> str:
    flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0)
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    fd = os.open(path, flags)
    try:
        data = os.read(fd, 4_000_000)
    finally:
        os.close(fd)
    return data.decode("utf-8")


def write_text_atomic(path: str, text: str) -> None:
    parent = os.path.dirname(path) or "."
    os.makedirs(parent, exist_ok=True)
    pst = os.lstat(parent)
    if stat.S_ISLNK(pst.st_mode):
        raise OSError("refusing symlink directory: %s" % parent)
    _refuse_symlink(path)
    fd, tmp = tempfile.mkstemp(prefix=".bindings.", suffix=".tmp", dir=parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(text)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp, path)
        st = os.lstat(path)
        if stat.S_ISLNK(st.st_mode):
            raise OSError("refusing to leave a symlink at %s" % path)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def usage() -> int:
    print(
        "usage: install-binds.py PLUGIN_ID LUA_BLOCK\n"
        "       install-binds.py --remove PLUGIN_ID",
        file=sys.stderr,
    )
    return 2


def bindings_path() -> str:
    config_home = os.environ.get("XDG_CONFIG_HOME") or os.path.join(
        os.path.expanduser("~"), ".config"
    )
    return os.path.join(config_home, "hypr", "bindings.lua")


def markers(plugin_id: str) -> tuple[str, str]:
    return f"-- BEGIN {plugin_id}", f"-- END {plugin_id}"


def replace_block(text: str, begin: str, end: str, chunk: str) -> str:
    if begin in text and end in text:
        pre = text[: text.index(begin)]
        post = text[text.index(end) + len(end) :].lstrip("\n")
        out = pre.rstrip() + "\n\n" + chunk
        if post:
            out = out.rstrip() + "\n" + post
        if not out.endswith("\n"):
            out += "\n"
        return out
    if begin in text or end in text:
        raise ValueError("marked bind block is incomplete")
    if text and not text.endswith("\n"):
        text += "\n"
    out = text.rstrip() + "\n\n" + chunk
    if not out.endswith("\n"):
        out += "\n"
    return out


def strip_block(text: str, begin: str, end: str) -> str:
    if begin not in text and end not in text:
        return text
    if begin not in text or end not in text:
        raise ValueError("marked bind block is incomplete")
    pre = text[: text.index(begin)]
    post = text[text.index(end) + len(end) :].lstrip("\n")
    out = pre.rstrip()
    if post:
        out = out + "\n\n" + post.lstrip()
    if out and not out.endswith("\n"):
        out += "\n"
    return out


def write_path(path: str, text: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    write_text_atomic(path, text)


def read_path(path: str) -> str:
    if os.path.islink(path):
        raise OSError("refusing symlink: %s" % path)
    if not os.path.isfile(path):
        return ""
    return read_text_nofollow(path)


def main() -> int:
    if len(sys.argv) < 3:
        return usage()
    if sys.argv[1] == "--remove":
        plugin_id = sys.argv[2]
        begin, end = markers(plugin_id)
        path = bindings_path()
        try:
            text = strip_block(read_path(path), begin, end)
        except (ValueError, OSError) as exc:
            print(str(exc), file=sys.stderr)
            return 1
        if text:
            write_path(path, text)
        elif os.path.isfile(path):
            write_path(path, "")
        print("ok")
        return 0

    plugin_id = sys.argv[1]
    block = sys.argv[2]
    if not block.endswith("\n"):
        block += "\n"
    if "hl.unbind" in block:
        print("refusing to write hl.unbind", file=sys.stderr)
        return 1
    begin, end = markers(plugin_id)
    chunk = f"{begin}\n{block}{end}\n"
    path = bindings_path()
    try:
        text = replace_block(read_path(path), begin, end, chunk)
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    write_path(path, text)
    print("ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
