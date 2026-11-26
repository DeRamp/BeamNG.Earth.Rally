#!/usr/bin/env python3
"""Build templates/Earth Rally templates.zip from the templates/Earth Rally templates folder: the download people fill
in to make their own stages, rallies and seasons (docs/making-rally-packs.md). Run it after changing a template; the
zip is the same bytes for the same files (fixed dates, sorted), so git only sees a real change.

    python tools/make_templates.py            (write the zip)
    python tools/make_templates.py --check    (exit 1 when the zip is not the folder's)
"""
import io
import os
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FOLDER = os.path.join(ROOT, "templates", "Earth Rally templates")
ZIP = os.path.join(ROOT, "templates", "Earth Rally templates.zip")
STAMP = (2026, 1, 1, 0, 0, 0)


def build():
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
        names = []
        for d, _, files in os.walk(FOLDER):
            for n in files:
                names.append(os.path.relpath(os.path.join(d, n), FOLDER).replace(os.sep, "/"))
        for rel in sorted(names):
            with open(os.path.join(FOLDER, rel), "rb") as f:
                data = f.read()
            # (Windows line ends: the files are opened in Notepad)
            if rel.lower().endswith((".txt", ".csv")):
                data = data.replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")
            info = zipfile.ZipInfo("Earth Rally templates/" + rel, STAMP)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            z.writestr(info, data)
    return buf.getvalue()


def main():
    data = build()
    if "--check" in sys.argv:
        same = os.path.isfile(ZIP) and open(ZIP, "rb").read() == data
        print("templates zip up to date" if same else "templates zip out of date: run tools/make_templates.py")
        return 0 if same else 1
    with open(ZIP, "wb") as f:
        f.write(data)
    print(f"wrote {ZIP} ({len(data)} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
