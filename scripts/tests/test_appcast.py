"""Tests for scripts/appcast.py — the Sparkle appcast maintainer.

Run: uv run --no-project --with pytest pytest scripts/tests/
"""

import email.utils
import xml.etree.ElementTree as ET

import pytest

import appcast

SPARKLE = "http://www.sparkle-project.org/xml/rss"
SKELETON = (
    "<?xml version='1.0' encoding='utf-8'?>\n"
    f'<rss xmlns:sparkle="{SPARKLE}" version="2.0">\n'
    "  <channel>\n"
    "    <title>Mini Whisper</title>\n"
    "    <link>https://raw.githubusercontent.com/cagriy/mini-whisper/main/appcast.xml</link>\n"
    "    <language>en</language>\n"
    "  </channel>\n"
    "</rss>\n"
)

SIG = "7cLALFUHSwvEJWSkV8aMreoBe4fhRa4FncC5NoThKxwThL6FDR7hTiPJh1fo2uagnPogisnQsgFgq6mGkt2RBw=="


@pytest.fixture
def feed(tmp_path):
    path = tmp_path / "appcast.xml"
    path.write_text(SKELETON)
    return path


def notes(tmp_path, text="### Added\n- **Sparkle** auto-updates via `appcast.xml`\n"):
    path = tmp_path / "notes.md"
    path.write_text(text)
    return path


def run(feed, version, tmp_path, signature=SIG, length="12345", notes_text=None):
    args = [
        "--appcast", str(feed),
        "--version", version,
        "--signature", signature,
        "--length", length,
        "--notes-file", str(notes(tmp_path) if notes_text is None else notes(tmp_path, notes_text)),
    ]
    return appcast.main(args)


def items(feed):
    return ET.parse(feed).getroot().findall("channel/item")


def sparkle_version(item):
    return item.findtext(f"{{{SPARKLE}}}version")


class TestFirstInsert:
    def test_item_fields(self, feed, tmp_path):
        assert run(feed, "0.4.0", tmp_path) == 0
        (item,) = items(feed)
        assert item.findtext("title") == "Mini Whisper 0.4.0"
        assert sparkle_version(item) == "0.4.0"
        assert item.findtext(f"{{{SPARKLE}}}shortVersionString") == "0.4.0"
        assert item.findtext(f"{{{SPARKLE}}}minimumSystemVersion") == "14.0"

    def test_pub_date_is_rfc822(self, feed, tmp_path):
        run(feed, "0.4.0", tmp_path)
        (item,) = items(feed)
        parsed = email.utils.parsedate_to_datetime(item.findtext("pubDate"))
        assert parsed.tzinfo is not None

    def test_enclosure(self, feed, tmp_path):
        run(feed, "0.4.0", tmp_path)
        (item,) = items(feed)
        enclosure = item.find("enclosure")
        assert enclosure.get("url") == (
            "https://github.com/cagriy/mini-whisper/releases/download/"
            "v0.4.0/MiniWhisper-0.4.0-arm64.dmg"
        )
        assert enclosure.get(f"{{{SPARKLE}}}edSignature") == SIG
        assert enclosure.get("length") == "12345"
        assert enclosure.get("type") == "application/octet-stream"


class TestOrderingAndIdempotence:
    def test_new_items_come_first(self, feed, tmp_path):
        run(feed, "0.4.0", tmp_path)
        run(feed, "0.4.1", tmp_path)
        assert [sparkle_version(i) for i in items(feed)] == ["0.4.1", "0.4.0"]

    def test_rerun_replaces_not_duplicates(self, feed, tmp_path):
        run(feed, "0.4.0", tmp_path, length="111")
        run(feed, "0.4.0", tmp_path, length="222")
        (item,) = items(feed)
        assert item.find("enclosure").get("length") == "222"

    def test_replace_keeps_position_of_other_items(self, feed, tmp_path):
        run(feed, "0.4.0", tmp_path)
        run(feed, "0.4.1", tmp_path)
        run(feed, "0.4.1", tmp_path, length="999")
        assert [sparkle_version(i) for i in items(feed)] == ["0.4.1", "0.4.0"]


class TestValidation:
    def test_malformed_version(self, feed, tmp_path):
        with pytest.raises(SystemExit):
            run(feed, "0.4", tmp_path)

    def test_empty_signature(self, feed, tmp_path):
        with pytest.raises(SystemExit):
            run(feed, "0.4.0", tmp_path, signature="")

    def test_non_integer_length(self, feed, tmp_path):
        with pytest.raises(SystemExit):
            run(feed, "0.4.0", tmp_path, length="12k")

    def test_missing_appcast_file(self, tmp_path):
        with pytest.raises(SystemExit):
            run(tmp_path / "nope.xml", "0.4.0", tmp_path)


class TestReleaseNotes:
    def test_description_html(self, feed, tmp_path):
        run(feed, "0.4.0", tmp_path,
            notes_text="### Added\n- **Sparkle** updates via `appcast.xml`\n- second item\n\nPlain closing line.\n")
        (item,) = items(feed)
        html = item.findtext("description")
        assert "<h3>Added</h3>" in html
        assert "<ul>" in html and html.count("<li>") == 2
        assert "<strong>Sparkle</strong>" in html
        assert "<code>appcast.xml</code>" in html
        assert "<p>Plain closing line.</p>" in html

    def test_wrapped_bullet_lines_stay_in_one_li(self, feed, tmp_path):
        # Keep-a-Changelog entries hard-wrap; continuation lines (indented or
        # not) belong to the bullet above, not to new paragraphs.
        run(feed, "0.4.0", tmp_path,
            notes_text="### Added\n- **Sparkle auto-updates.** The app checks\n  the feed daily and offers found\n  updates.\n")
        (item,) = items(feed)
        html = item.findtext("description")
        assert html.count("<li>") == 1
        assert "<p>" not in html
        assert "The app checks the feed daily and offers found updates." in html

    def test_description_escapes_html_specials(self, feed, tmp_path):
        run(feed, "0.4.0", tmp_path, notes_text="- keep a < b & c\n")
        (item,) = items(feed)
        assert "a &lt; b &amp; c" in item.findtext("description")


class TestRoundTrip:
    def test_two_item_feed_stays_valid_and_preserves_items(self, feed, tmp_path):
        run(feed, "0.4.0", tmp_path, length="111")
        first = ET.tostring(items(feed)[0])
        run(feed, "0.4.1", tmp_path, length="222")
        root = ET.parse(feed).getroot()
        assert root.tag == "rss"
        channel = root.find("channel")
        assert channel.findtext("title") == "Mini Whisper"
        preserved = ET.tostring(root.findall("channel/item")[1])
        assert preserved == first
