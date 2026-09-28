import importlib.util
import unittest
from pathlib import Path
from unittest.mock import patch


SCRIPT_PATH = Path(__file__).parents[2] / "scripts" / "update_tracking_rules.py"
SPEC = importlib.util.spec_from_file_location("update_tracking_rules", SCRIPT_PATH)
updater = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(updater)


class UpdateTrackingRulesTests(unittest.TestCase):
    def test_fetches_commit_before_rules_and_pins_rules_url(self):
        sha = "a" * 40
        calls = []

        def fake_fetch(url):
            calls.append(url)
            return {"sha": sha} if url == updater.COMMIT_API_URL else {"providers": {}}

        with patch.object(updater, "fetch_json", side_effect=fake_fetch):
            actual_sha, data = updater.fetch_pinned_upstream()

        self.assertEqual(actual_sha, sha)
        self.assertEqual(data, {"providers": {}})
        self.assertEqual(
            calls,
            [updater.COMMIT_API_URL, updater.RULES_URL_TEMPLATE.format(sha=sha)],
        )

    def test_rejects_invalid_commit_sha(self):
        with patch.object(updater, "fetch_json", return_value={"sha": "master"}):
            with self.assertRaisesRegex(ValueError, "valid 40-character SHA"):
                updater.fetch_pinned_upstream()

    def test_rejects_changed_top_level_schema(self):
        with self.assertRaisesRegex(ValueError, "top-level schema"):
            updater.validate_upstream_schema({"providers": {}, "schemaVersion": 2})

    def test_rejects_malformed_provider_rules(self):
        data = {"providers": {"example": {"urlPattern": "example", "rules": "utm"}}}
        with self.assertRaisesRegex(ValueError, "non-string 'rules' array"):
            updater.validate_upstream_schema(data)

    def test_expected_skipped_provider_set_is_explicit(self):
        self.assertEqual(updater.EXPECTED_SKIPPED_PROVIDERS, {"weibo"})


if __name__ == "__main__":
    unittest.main()
