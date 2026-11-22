"""Tests for scripts/appcast.py — the Sparkle appcast maintainer.

Run: uv run --no-project --with pytest pytest scripts/tests/
"""

import email.utils
import xml.etree.ElementTree as ET
from pathlib import Path

import pytest

import appcast

SPARKLE = "http://www.sparkle-project.org/xml/rss"
PUBLISHED_FEED = Path(__file__).resolve().parents[2] / "appcast.xml"
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

    def test_malformed_beta_version(self, feed, tmp_path):
        with pytest.raises(SystemExit):
            run(feed, "0.9.0-beta.1", tmp_path)


class TestChannel:
    def test_beta_item_carries_the_beta_channel(self, feed, tmp_path):
        assert run(feed, "0.9.0b1", tmp_path) == 0
        (item,) = items(feed)
        assert [c.text for c in item.findall(f"{{{SPARKLE}}}channel")] == ["beta"]
        tags = [child.tag for child in item]
        after_minimum = tags.index(f"{{{SPARKLE}}}minimumSystemVersion") + 1
        assert tags[after_minimum] == f"{{{SPARKLE}}}channel"
        assert item.findtext("title") == "Mini Whisper 0.9.0b1"
        assert sparkle_version(item) == "0.9.0b1"
        assert item.findtext(f"{{{SPARKLE}}}shortVersionString") == "0.9.0b1"
        assert item.find("enclosure").get("url") == (
            "https://github.com/cagriy/mini-whisper/releases/download/"
            "v0.9.0b1/MiniWhisper-0.9.0b1-arm64.dmg"
        )

    def test_release_item_has_no_channel(self, feed, tmp_path):
        run(feed, "0.8.2", tmp_path)
        (item,) = items(feed)
        assert item.find(f"{{{SPARKLE}}}channel") is None

    def test_beta_insert_keeps_release_items_byte_identical(self, feed, tmp_path):
        run(feed, "0.8.2", tmp_path)
        release = ET.tostring(items(feed)[0])
        run(feed, "0.9.0b1", tmp_path)
        assert [sparkle_version(i) for i in items(feed)] == ["0.9.0b1", "0.8.2"]
        assert ET.tostring(items(feed)[1]) == release


class TestChannelOf:
    def test_channel_of(self):
        assert appcast.channel_of("0.8.2") == "release"
        assert appcast.channel_of("0.9.0b1") == "beta"
        assert appcast.channel_of("1.10.2b12") == "beta"
        for version in ("0.9.0-beta.1", "v0.9.0", "0.9", "0.9.0b0", "0.9.0b", "0.9.0rc1"):
            with pytest.raises(ValueError):
                appcast.channel_of(version)


class TestPrintChannel:
    @pytest.mark.parametrize("version, channel", [("0.8.2", "release"), ("0.9.0b1", "beta")])
    def test_prints_the_channel(self, version, channel, capsys):
        assert appcast.main(["--print-channel", version]) == 0
        assert capsys.readouterr().out == f"{channel}\n"

    @pytest.mark.parametrize("version", ["0.9.0-beta.1", "v0.9.0", "0.9", "0.9.0b0"])
    def test_rejects_other_forms(self, version, capsys):
        with pytest.raises(SystemExit) as raised:
            appcast.main(["--print-channel", version])
        assert raised.value.code == 2
        assert f"'{version}'" in capsys.readouterr().err


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


class TestReleaseItemBytes:
    def test_release_item_matches_the_published_feed(self):
        # Rebuilds a shipped item from its own fields, so any change to how a
        # release item is written shows up against bytes that were published.
        published = next(i for i in ET.parse(PUBLISHED_FEED).getroot().findall("channel/item")
                         if sparkle_version(i) == "0.8.1")
        for element in published.iter():
            if element.text is not None and not element.text.strip():
                element.text = None
            if element.tail is not None and not element.tail.strip():
                element.tail = None
        enclosure = published.find("enclosure")
        rebuilt = appcast.build_item(
            sparkle_version(published),
            enclosure.get(f"{{{SPARKLE}}}edSignature"),
            int(enclosure.get("length")),
            published.findtext("description"),
            email.utils.parsedate_to_datetime(published.findtext("pubDate")),
        )
        assert ET.tostring(rebuilt) == ET.tostring(published)
