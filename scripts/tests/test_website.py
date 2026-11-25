"""Check that the product page can be served from a GitHub Pages subpath."""

from html.parser import HTMLParser
from pathlib import Path
import unittest
from urllib.parse import unquote, urlsplit


WEBSITE = Path(__file__).resolve().parents[2] / "website"


class PageReferences(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids = set()
        self.urls = []

    def handle_starttag(self, tag, attrs):
        for name, value in attrs:
            if name == "id" and value:
                self.ids.add(value)
            if name in ("src", "href") and value:
                self.urls.append(value)


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
