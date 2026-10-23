"""Integration regressions for report output preserving inspected files."""

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

from test_inventory import pe_image


ROOT = Path(__file__).resolve().parents[1]


class BaselineOutputTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="cs2-baseline-test-")
        self.addCleanup(self.temporary.cleanup)
        self.work = Path(self.temporary.name)
        self.game = self.work / "game-install"
        self.input = self.game / "game/bin/win64/cs2.exe"
        self.input.parent.mkdir(parents=True)
        self.original = pe_image()
        self.input.write_bytes(self.original)
        self.tool = Path(os.environ.get("CS2_NATIVE_LAB", ROOT / ".build/cs2-native-lab"))

    def invoke(self, output, tool=None):
        return subprocess.run(
            [sys.executable, str(ROOT / "tools/capture_baseline.py"),
             "--root", str(self.game), "--tool", str(tool or self.tool),
             "--output", str(output)],
            capture_output=True, text=True, timeout=10,
        )

    def test_output_cannot_overwrite_a_game_input(self):
        result = self.invoke(self.input)
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("outside the game installation", result.stderr)
        self.assertEqual(self.input.read_bytes(), self.original)

    def test_output_symlink_cannot_overwrite_a_game_input(self):
        output = self.work / "report.json"
        output.symlink_to(self.input)
        result = self.invoke(output)
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertTrue(output.is_symlink())
        self.assertEqual(self.input.read_bytes(), self.original)

    def test_output_hard_link_is_replaced_without_changing_input(self):
        output = self.work / "report.json"
        os.link(self.input, output)
        result = self.invoke(output)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.input.read_bytes(), self.original)
        self.assertNotEqual(self.input.stat().st_ino, output.stat().st_ino)
        report = json.loads(output.read_text())
        inspected = report["records"][0]["inspection"]
        self.assertEqual(inspected["sha256"], hashlib.sha256(self.original).hexdigest())
        self.assertFalse(report["game_execution_observed"])
        self.assertEqual(list(self.work.glob(".cs2-baseline-*")), [])

    def test_output_cannot_overwrite_the_native_inspector(self):
        tool_copy = self.work / "inspector-copy"
        shutil.copy2(self.tool, tool_copy)
        before = hashlib.sha256(tool_copy.read_bytes()).digest()
        result = self.invoke(tool_copy, tool_copy)
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("cannot replace the native inspector", result.stderr)
        self.assertEqual(hashlib.sha256(tool_copy.read_bytes()).digest(), before)


if __name__ == "__main__":
    unittest.main()
