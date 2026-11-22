# /// script
# requires-python = ">=3.12"
# ///
"""Maintain the Sparkle appcast for Mini Whisper.

Inserts (or replaces) one <item> in appcast.xml at the repo root, which Sparkle
reads over raw.githubusercontent.com. The EdDSA signature and byte length come
from Sparkle's sign_update, run by .github/workflows/build.yml after stapling.
A beta (X.Y.ZbN) item carries <sparkle:channel>beta</sparkle:channel>.

Usage:
  uv run scripts/appcast.py --appcast <path> --version <X.Y.Z|X.Y.ZbN> \
    --signature <edSignature> --length <bytes> --notes-file <section.md>
  uv run scripts/appcast.py --print-channel <version>   # release or beta; exit 2 otherwise

Tests: uv run --no-project --with pytest pytest scripts/tests/
"""

import argparse
import email.utils
import html
import re
import sys
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path

SPARKLE_NS = "http://www.sparkle-project.org/xml/rss"
DOWNLOAD_URL = (
    "https://github.com/cagriy/mini-whisper/releases/download/"
    "v{version}/MiniWhisper-{version}-arm64.dmg"
)
MINIMUM_SYSTEM_VERSION = "14.0"
# No hyphenated suffix: Sparkle stops comparing at a "-", so 0.9.0-beta.1 and
# 0.9.0 would compare equal.
VERSION_PATTERN = re.compile(r"\d+\.\d+\.\d+(b[1-9]\d*)?")

ET.register_namespace("sparkle", SPARKLE_NS)


def sparkle(tag: str) -> str:
    return f"{{{SPARKLE_NS}}}{tag}"


def channel_of(version: str) -> str:
    """'beta' for X.Y.ZbN, 'release' for X.Y.Z; ValueError for any other form."""
    match = VERSION_PATTERN.fullmatch(version)
    if match is None:
        raise ValueError(f"version '{version}' is not X.Y.Z or X.Y.ZbN")
    return "beta" if match.group(1) else "release"


def markdown_to_html(markdown: str) -> str:
    """Minimal CHANGELOG-section markdown: ### headings, - bullets, **bold**,
    `code`, blank-line-separated paragraphs. Everything is HTML-escaped first."""

    def inline(text: str) -> str:
        text = html.escape(text, quote=False)
        text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)
        text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
        return text

    blocks: list[str] = []
    bullets: list[str] = []
    paragraph: list[str] = []

    def flush_bullets() -> None:
        if bullets:
            blocks.append("<ul>" + "".join(f"<li>{b}</li>" for b in bullets) + "</ul>")
            bullets.clear()

    def flush_paragraph() -> None:
        if paragraph:
            blocks.append(f"<p>{' '.join(paragraph)}</p>")
            paragraph.clear()

    for line in markdown.splitlines():
        stripped = line.strip()
        if not stripped:
            flush_bullets()
            flush_paragraph()
        elif stripped.startswith("- "):
            flush_paragraph()
            bullets.append(inline(stripped[2:]))
        elif match := re.match(r"(#{1,6})\s+(.*)", stripped):
            flush_bullets()
            flush_paragraph()
            level = min(len(match.group(1)), 6)
            blocks.append(f"<h{level}>{inline(match.group(2))}</h{level}>")
        elif bullets:
            # Hard-wrapped continuation of the bullet above (Keep a Changelog
            # entries wrap at ~80 columns).
            bullets[-1] += " " + inline(stripped)
        else:
            paragraph.append(inline(stripped))
    flush_bullets()
    flush_paragraph()
    return "\n".join(blocks)


def build_item(version: str, signature: str, length: int, notes_html: str,
               pub_date: datetime) -> ET.Element:
    item = ET.Element("item")
    ET.SubElement(item, "title").text = f"Mini Whisper {version}"
    ET.SubElement(item, sparkle("version")).text = version
    ET.SubElement(item, sparkle("shortVersionString")).text = version
    ET.SubElement(item, sparkle("minimumSystemVersion")).text = MINIMUM_SYSTEM_VERSION
    if channel_of(version) == "beta":
        ET.SubElement(item, sparkle("channel")).text = "beta"
    ET.SubElement(item, "description").text = notes_html
    ET.SubElement(item, "pubDate").text = email.utils.format_datetime(pub_date)
    ET.SubElement(item, "enclosure", {
        "url": DOWNLOAD_URL.format(version=version),
        sparkle("edSignature"): signature,
        "length": str(length),
        "type": "application/octet-stream",
    })
    return item


def add_version(tree: ET.ElementTree, version: str, signature: str, length: int,
                notes_html: str, pub_date: datetime) -> None:
    channel = tree.getroot().find("channel")
    if channel is None:
        raise SystemExit("error: appcast has no <channel> element")

    existing = channel.findall("item")
    replaced = next(
        (i for i in existing if i.findtext(sparkle("version")) == version), None)
    item = build_item(version, signature, length, notes_html, pub_date)
    if replaced is not None:
        channel[list(channel).index(replaced)] = item
    elif existing:
        channel.insert(list(channel).index(existing[0]), item)
    else:
        channel.append(item)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--print-channel", metavar="VERSION")
    # Required unless --print-channel is given, so checked below, not by argparse.
    insert_options = [
        parser.add_argument("--appcast", type=Path),
        parser.add_argument("--version"),
        parser.add_argument("--signature"),
        parser.add_argument("--length", type=int),
        parser.add_argument("--notes-file", type=Path),
    ]
    args = parser.parse_args(argv)

    printing = args.print_channel is not None
    if not printing:
        missing = [o.option_strings[0] for o in insert_options if getattr(args, o.dest) is None]
        if missing:
            parser.error(f"the following arguments are required: {', '.join(missing)}")
    try:
        channel = channel_of(args.print_channel if printing else args.version)
    except ValueError as error:
        parser.error(str(error))
    if printing:
        print(channel)
        return 0

    if not args.signature.strip():
        parser.error("signature is empty")
    if not args.appcast.is_file():
        parser.error(f"appcast not found: {args.appcast}")
    if not args.notes_file.is_file():
        parser.error(f"notes file not found: {args.notes_file}")

    tree = ET.parse(args.appcast)
    add_version(tree, args.version, args.signature.strip(), args.length,
                markdown_to_html(args.notes_file.read_text()),
                datetime.now(timezone.utc))
    ET.indent(tree, space="  ")
    tree.write(args.appcast, encoding="utf-8", xml_declaration=True)
    args.appcast.write_text(args.appcast.read_text() + "\n")
    print(f"appcast: added {args.version} -> {args.appcast}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
