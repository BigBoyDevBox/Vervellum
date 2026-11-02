#!/usr/bin/env python3
"""Dependency discovery must fail rather than publish guessed metadata."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class DependencyDiscoveryTests(unittest.TestCase):
    def run_discovery(self, command):
        with tempfile.TemporaryDirectory() as temporary:
            tool = Path(temporary) / "dpkg-shlibdeps"
            tool.write_text("#!/bin/sh\n" + command + "\n")
            tool.chmod(0o755)
            environment = dict(os.environ, PATH=temporary + os.pathsep + os.environ["PATH"])
            return subprocess.run(
                ["bash", str(ROOT / "scripts/deb-dependencies.sh"), "/unused/vervellum"],
                env=environment, capture_output=True, text=True, check=False,
            )

    def test_failed_tool_produces_no_dependency_list(self):
        result = self.run_discovery("exit 1")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")

    def test_empty_success_produces_no_dependency_list(self):
        result = self.run_discovery("exit 0")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")

    def test_success_includes_the_unlinked_shortcut_command(self):
        result = self.run_discovery("echo 'shlibs:Depends=libc6 (>= 2.39), libgtk-4-1'")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "libc6 (>= 2.39), libgtk-4-1, libglib2.0-bin\n")


if __name__ == "__main__":
    unittest.main()
