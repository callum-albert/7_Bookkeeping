#!/usr/bin/env python3
"""创建使用最基础 ZIP Stored 格式的 IPA，避免侧载解压器的 deflate 兼容问题。"""
import os
import stat
import sys
import zipfile
from pathlib import Path


def package(payload: Path, output: Path):
    if payload.name != "Payload" or len(list(payload.glob("*.app"))) != 1:
        raise ValueError("Expected Payload with exactly one app")
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_STORED, allowZip64=False) as archive:
        for path in [payload] + sorted(payload.rglob("*")):
            if path.is_symlink():
                raise ValueError(f"Unexpected symlink: {path}")
            name = path.relative_to(payload.parent).as_posix() + ("/" if path.is_dir() else "")
            info = zipfile.ZipInfo(name)
            info.create_system = 3
            mode = (stat.S_IFDIR | 0o755) if path.is_dir() else (stat.S_IFREG | stat.S_IMODE(path.stat().st_mode))
            info.external_attr = mode << 16
            if path.is_dir():
                info.external_attr |= 0x10
            archive.writestr(info, b"" if path.is_dir() else path.read_bytes())


if __name__ == "__main__":
    package(Path(sys.argv[1]), Path(sys.argv[2]))
