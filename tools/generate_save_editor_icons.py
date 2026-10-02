"""Render pinned upstream Lucide SVG artwork; requires rsvg-convert and ImageMagick."""
from pathlib import Path
import subprocess
import tempfile
import urllib.request

COMMIT = "f06ac67e33d645c40b8ce19a0419c85c5d7dd751"
NAMES = [
    "chevron-left", "chevron-up", "chevron-down", "plus", "minus", "undo-2", "redo-2",
    "save", "rotate-ccw", "ellipsis", "copy", "heart", "package", "backpack", "list-filter",
    "arrow-up", "arrow-down", "arrow-left", "arrow-right", "arrow-up-down", "eye", "award",
    "book-open", "shield-check", "map-pin", "grid-2x2", "sliders-horizontal", "expand",
    "chevrons-up", "users", "user-round", "wallet", "flag",
]


def main():
    root = Path(__file__).resolve().parent.parent
    output = root / "assets/launcher/lucide/editor.png"
    with tempfile.TemporaryDirectory(prefix="save-editor-icons-") as directory:
        images = []
        for name in NAMES:
            svg = Path(directory) / (name + ".svg")
            png = svg.with_suffix(".png")
            url = f"https://raw.githubusercontent.com/lucide-icons/lucide/{COMMIT}/icons/{name}.svg"
            with urllib.request.urlopen(url, timeout=30) as response:
                source = response.read().decode("utf-8")
            svg.write_text(source.replace('stroke="currentColor"', 'stroke="#ffffff"'))
            subprocess.run(["rsvg-convert", "-w", "96", "-h", "96", "-o", str(png), str(svg)], check=True)
            images.append(str(png))
        subprocess.run(["magick", *images, "+append", str(output)], check=True)
    print(f"Rendered {len(NAMES)} Lucide icons into {output.relative_to(root)}")


if __name__ == "__main__":
    main()
