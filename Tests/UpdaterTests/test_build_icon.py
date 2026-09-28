import importlib.util
import struct
import tempfile
import unittest
from pathlib import Path


SCRIPT_PATH = Path(__file__).parents[2] / "scripts" / "build_icon.py"
SPEC = importlib.util.spec_from_file_location("build_icon", SCRIPT_PATH)
build_icon = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(build_icon)


class BuildIconTests(unittest.TestCase):
    def test_builds_well_formed_icns_with_all_modern_sizes(self):
        source = Path(__file__).parents[2] / "Assets" / "AppIcon.png"
        with tempfile.TemporaryDirectory() as temporary:
            destination = Path(temporary) / "AppIcon.icns"
            build_icon.build_icns(source, destination)
            contents = destination.read_bytes()

        self.assertEqual(contents[:4], b"icns")
        self.assertEqual(struct.unpack(">I", contents[4:8])[0], len(contents))
        for element_type, _ in build_icon.ICON_REPRESENTATIONS:
            self.assertIn(element_type, contents)
