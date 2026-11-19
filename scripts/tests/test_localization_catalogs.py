import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCES = ROOT / 'Packages/OctoRunnerKit/Sources'


class LocalizationCatalogTests(unittest.TestCase):
    def test_explicit_package_text_keys_exist_in_both_languages(self):
        for module in ('AppShellFeature', 'DesignSystem'):
            catalog = json.loads((SOURCES / module / 'Resources/Localizable.xcstrings').read_text())
            for source in (SOURCES / module).rglob('*.swift'):
                for key in re.findall(r'Text\(\s*"([^"\\]*)"\s*,\s*bundle:\s*\.module', source.read_text()):
                    with self.subTest(module=module, source=source.name, key=key):
                        self.assertTrue(key in catalog['strings'], f'Missing catalog key: {key}')
                        for language in ('en', 'de'):
                            value = catalog['strings'].get(key, {}).get('localizations', {}).get(language, {}).get('stringUnit', {}).get('value')
                            self.assertTrue(value, f'{key}: missing {language}')

    def test_translation_format_arguments_match(self):
        for path in SOURCES.glob('*/Resources/Localizable.xcstrings'):
            for key, entry in json.loads(path.read_text())['strings'].items():
                values = [entry.get('localizations', {}).get(lang, {}).get('stringUnit', {}).get('value', '') for lang in ('en', 'de')]
                # All current catalogs use string units, not plural substitutions.
                placeholders = [sorted(re.findall(r'%(?:\d+\$)?(?:lld|ld|d|@|f)', value)) for value in values]
                with self.subTest(catalog=str(path.relative_to(ROOT)), key=key):
                    self.assertEqual(placeholders[0], placeholders[1])
