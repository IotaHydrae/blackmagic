#!/usr/bin/env python3
"""Extract the KiCad ibom.html PCB/BOM data (vendor board) to JSON.

The vendor shared only the interactive BOM (docs/ibom.html in blackmagic_copy).
This script decompresses its embedded pcbdata (LZString) and writes a
readable JSON, used to build the hardware-replica documentation.

Usage:
    python3 extract-ibom.py <ibom.html> [out.json]

Requires: pip install lzstring
"""
import json
import re
import sys


def extract_ibom(html_path, out_path):
    with open(html_path, encoding="utf-8", errors="replace") as fh:
        html = fh.read()

    marker = 'pcbdata = JSON.parse(LZString.decompressFromBase64("'
    idx = html.find(marker)
    if idx < 0:
        raise SystemExit(f"pcbdata not found in {html_path}")
    start = idx + len(marker)
    end = html.find('"));', start)
    if end < 0:
        raise SystemExit("could not find end of pcbdata payload")

    from lzstring import LZString  # local import: only needed for this step

    compressed = html[start:end]
    pcb = json.loads(LZString().decompressFromBase64(compressed))

    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(pcb, fh, indent=1)

    # Summary
    meta = pcb.get("metadata", {})
    fps = pcb.get("footprints", [])
    print(f"project : {meta.get('title', '?')}")
    print(f"date    : {meta.get('date', '?')}")
    print(f"parts   : {len(fps)} footprints")
    print(f"written : {out_path}")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    extract_ibom(sys.argv[1], sys.argv[2])
