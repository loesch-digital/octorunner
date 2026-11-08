import json
from pathlib import Path
import subprocess
import unittest


class MatchConfigurationTests(unittest.TestCase):
    def test_certificate_sync_does_not_require_an_app_store_bundle_identifier(self):
        fastfile = Path(__file__).resolve().parents[2] / "fastlane" / "Fastfile"
        result = subprocess.run([
            "ruby", "-rjson", "-e", '''
$lanes = {}
def default_platform(*) end
def platform(*) yield end
def desc(*) end
def lane(name, &block) $lanes[name] = block end
def is_ci; false end
def match(**options) puts JSON.generate(options) end
load ARGV.fetch(0)
$lanes.fetch(:sync_certificates).call
''', str(fastfile),
        ], capture_output=True, text=True, check=True)
        options = json.loads(result.stdout)
        self.assertEqual(options["type"], "developer_id")
        self.assertEqual(options.get("app_identifier"), [])
        self.assertTrue(options.get("skip_provisioning_profiles"))


if __name__ == "__main__":
    unittest.main()
