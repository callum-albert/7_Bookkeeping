#!/usr/bin/env python3
"""检查 ZIP 本地头、压缩方法、长度、CRC 和 iOS bundle；不代表真机安装已通过。"""
import plistlib
import stat
import struct
import sys
import zipfile
import zlib
from pathlib import Path


def verify(path: Path):
    raw = path.read_bytes()
    with zipfile.ZipFile(path) as archive:
        entries = archive.infolist()
        names = set(archive.namelist())
        assert len(names) == len(entries), "Duplicate ZIP paths"
        assert archive.testzip() is None, "CRC mismatch"
        for entry in entries:
            assert entry.filename.startswith("Payload/") and ".." not in Path(entry.filename).parts
            assert entry.compress_type in (0, 8), "Unsupported ZIP compression"
            offset = entry.header_offset
            magic, _, flags, method, _, _, _, _, _, name_len, extra_len = struct.unpack_from("<IHHHHHIIIHH", raw, offset)
            assert magic == 0x04034B50 and method == entry.compress_type
            assert not flags & 1, "Encrypted ZIP entry"
            start = offset + 30 + name_len + extra_len
            compressed = raw[start:start + entry.compress_size]
            data = compressed if method == 0 else zlib.decompress(compressed, -15)
            assert len(data) == entry.file_size and zlib.crc32(data) == entry.CRC, entry.filename
        app_plists = [name for name in names if name.count("/") == 2 and name.endswith(".app/Info.plist")]
        assert len(app_plists) == 1
        main = plistlib.loads(archive.read(app_plists[0]))
        for name in names:
            if name.endswith("/Info.plist"):
                info = plistlib.loads(archive.read(name))
                root = name.rsplit("/", 1)[0]
                executable = root + "/" + info["CFBundleExecutable"]
                binary = archive.read(executable)
                assert binary[:4] == b"\xcf\xfa\xed\xfe", "Expected 64-bit Mach-O"
                assert archive.getinfo(executable).external_attr >> 16 & stat.S_IXUSR
                if name != app_plists[0]:
                    assert info["CFBundleIdentifier"].startswith(main["CFBundleIdentifier"] + ".")
    print(f"Verified {len(entries)} ZIP entries, headers, CRCs and app/extension bundles: {path.name}")


if __name__ == "__main__":
    verify(Path(sys.argv[1]))
