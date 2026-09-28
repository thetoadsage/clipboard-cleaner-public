#!/usr/bin/env python3
"""Build a modern ICNS container from a square PNG using macOS `sips`."""
from __future__ import annotations

import struct
import subprocess
import sys
import tempfile
from pathlib import Path


# Modern ICNS PNG-backed element types and their pixel sizes.
ICON_REPRESENTATIONS = (
    (b"icp4", 16),
    (b"icp5", 32),
    (b"icp6", 64),
    (b"ic07", 128),
    (b"ic08", 256),
    (b"ic09", 512),
    (b"ic10", 1024),
)


def build_icns(source: Path, destination: Path) -> None:
    if not source.is_file():
        raise FileNotFoundError(source)

    elements = []
    with tempfile.TemporaryDirectory(prefix="clipboard-cleaner-icon.") as temporary:
        temporary_path = Path(temporary)
        for element_type, pixels in ICON_REPRESENTATIONS:
            resized = temporary_path / f"icon-{pixels}.png"
            subprocess.run(
                [
                    "sips",
                    "-s",
                    "format",
                    "png",
                    "--resampleHeightWidth",
                    str(pixels),
                    str(pixels),
                    str(source),
                    "--out",
                    str(resized),
                ],
                check=True,
                stdout=subprocess.DEVNULL,
            )
            png = resized.read_bytes()
            elements.append(element_type + struct.pack(">I", len(png) + 8) + png)

    body = b"".join(elements)
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(b"icns" + struct.pack(">I", len(body) + 8) + body)


def main() -> int:
    if len(sys.argv) != 3:
        print(f"usage: {Path(sys.argv[0]).name} SOURCE.png DESTINATION.icns", file=sys.stderr)
        return 2
    build_icns(Path(sys.argv[1]), Path(sys.argv[2]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
