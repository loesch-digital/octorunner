"""Check that the product page can be served from a GitHub Pages subpath."""

from html.parser import HTMLParser
import json
from pathlib import Path
import unittest
from urllib.parse import unquote, urlsplit


WEBSITE = Path(__file__).resolve().parents[2] / "website"


class PageReferences(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids = set()
        self.urls = []
        self.metadata = {}
        self.links = {}
        self.text = {}
        self.capture = None

    def handle_starttag(self, tag, attrs):
        attributes = dict(attrs)
        if tag == "meta":
            name = attributes.get("name") or attributes.get("property")
            if name:
                self.metadata[name] = attributes.get("content")
        if tag == "link" and attributes.get("rel"):
            self.links.setdefault(attributes["rel"], []).append(attributes.get("href"))
        if tag == "title":
            self.capture = "title"
        elif tag == "script" and attributes.get("type") == "application/ld+json":
            self.capture = "structured_data"
        for name, value in attrs:
            if name == "id" and value:
                self.ids.add(value)
            if name in ("src", "href") and value:
                self.urls.append(value)

    def handle_endtag(self, tag):
        if tag in ("title", "script"):
            self.capture = None

    def handle_data(self, data):
        if self.capture:
            self.text[self.capture] = self.text.get(self.capture, "") + data


class WebsiteTests(unittest.TestCase):
    def test_website_references_resolve_inside_the_published_directory(self):
        index = WEBSITE / "index.html"
        self.assertTrue(index.is_file(), "The Pages artifact requires an index.html")
        page = PageReferences()
        page.feed(index.read_text(encoding="utf-8"))
        self.assertTrue(page.urls)
        for reference in page.urls:
            with self.subTest(reference=reference):
                url = urlsplit(reference)
                if url.scheme or url.netloc:
                    continue
                self.assertFalse(url.path.startswith("/"), "Use relative URLs for project Pages")
                target = (WEBSITE / unquote(url.path)).resolve() if url.path else index
                self.assertTrue(target.is_relative_to(WEBSITE), "Target escapes the Pages artifact")
                self.assertTrue(target.is_file(), "Target is missing from the Pages artifact")
                if target == index and url.fragment:
                    self.assertIn(unquote(url.fragment), page.ids)

    def test_discovery_metadata_uses_the_public_pages_url(self):
        canonical = "https://loesch-digital.github.io/octorunner/"
        page = PageReferences()
        page.feed((WEBSITE / "index.html").read_text(encoding="utf-8"))

        self.assertEqual(page.links.get("canonical"), [canonical])
        self.assertIn("Self-Hosted GitHub Actions Runners", page.text["title"])
        self.assertEqual(page.metadata["og:url"], canonical)
        self.assertEqual(page.metadata["og:title"], page.text["title"])
        self.assertEqual(page.metadata["og:description"], page.metadata["description"])
        image = page.metadata["og:image"]
        self.assertTrue(image.startswith(canonical))
        self.assertTrue((WEBSITE / image.removeprefix(canonical)).is_file())

        app = json.loads(page.text["structured_data"])
        self.assertEqual(app["@type"], "SoftwareApplication")
        self.assertEqual(app["url"], canonical)
        self.assertEqual(app["description"], page.metadata["description"])

        self.assertEqual(page.links.get("describedby"), ["llms.txt"])
        index = (WEBSITE / "llms.txt").read_text(encoding="utf-8")
        self.assertTrue(index.startswith("# OctoRunner\n\n> "))
        self.assertIn(f"]({canonical})", index)
        self.assertIn("https://raw.githubusercontent.com/loesch-digital/octorunner/main/docs/user-guide.md", index)
