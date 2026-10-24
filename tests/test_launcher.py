"""Integration checks for the native launcher; no Steam, downloads or credentials."""

import json
import fcntl
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest


LAUNCHER = os.environ.get("CS2MAC_LAUNCHER")


@unittest.skipUnless(LAUNCHER, "run make test-app for the macOS launcher")
class LauncherTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="cs2mac-test-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.root = self.base / "Application Support with spaces"

    def invoke(self, *args, valid=True):
        result = subprocess.run(
            [LAUNCHER, "--data-root", str(self.root), *args],
            capture_output=True, text=True, timeout=30,
        )
        if valid:
            self.assertEqual(result.returncode, 0, result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout)
        return result

    def configure(self, **values):
        self.root.mkdir(parents=True, exist_ok=True)
        (self.root / "selection.json").write_text(json.dumps(values))

    def source_game(self):
        source = self.base / "original library/steamapps/common/Counter-Strike Global Offensive"
        exe = source / "game/bin/win64/cs2.exe"
        exe.parent.mkdir(parents=True)
        exe.write_bytes(b"synthetic Windows game fixture")
        manifest = source.parent.parent / "appmanifest_730.acf"
        manifest.write_text('"AppState" { "appid" "730" "buildid" "123" }')
        return source, exe, manifest

    def prepare_steam(self):
        steam = self.root / "Steam/drive_c/Program Files (x86)/Steam/steam.exe"
        steam.parent.mkdir(parents=True)
        steam.write_bytes(b"synthetic Steam installation")

    def test_dry_run_launches_steam_not_the_game_and_creates_nothing(self):
        for cmd in ("steam", "play", "stop"):
            plan = json.loads(self.invoke(cmd, "--dry-run").stdout)
            self.assertFalse(plan["launchesGameDirectly"])
            self.assertTrue(plan["arguments"][0].endswith("/Steam/steam.exe"))
            self.assertNotIn("cs2.exe", " ".join(plan["arguments"]))
            self.assertEqual(plan["environment"]["WINEPREFIX"], str(self.root / "Steam"))
        self.assertFalse(self.root.exists())

    def test_play_and_stop_have_the_expected_steam_routes(self):
        play = json.loads(self.invoke("play", "--dry-run").stdout)
        self.assertEqual(play["arguments"][-2:], ["-applaunch", "730"])
        stop = json.loads(self.invoke("stop", "--dry-run").stdout)
        self.assertEqual(stop["arguments"][-1], "-shutdown")

    def test_crossover_bottle_is_one_literal_argument(self):
        bottle = "Steam spaces; echo literal"
        self.configure(backend="crossover", bottle=bottle, crossOverApp="/Applications/An App.app")
        plan = json.loads(self.invoke("play", "--dry-run").stdout)
        self.assertEqual(plan["arguments"][:4], ["--bottle", bottle, "--no-wait", "--cx-app"])
        self.assertEqual(plan["arguments"][4], r"C:\Program Files (x86)\Steam\steam.exe")
        self.assertEqual(plan["arguments"][-2:], ["-applaunch", "730"])
        self.assertNotIn("WINEPREFIX", plan["environment"])

    def test_invalid_configuration_cannot_escape_the_bottle_directory(self):
        for bottle in ("", ".", "..", "../another-bottle", "a\\b"):
            with self.subTest(bottle=bottle):
                self.configure(backend="crossover", bottle=bottle, crossOverApp="/Applications/CrossOver.app")
                self.assertIn("inválida", self.invoke("steam", "--dry-run", valid=False).stderr)

    def test_unknown_backend_fails_without_rewriting_selection(self):
        self.configure(backend="unknown")
        before = (self.root / "selection.json").read_bytes()
        self.invoke("play", "--dry-run", valid=False)
        self.assertEqual((self.root / "selection.json").read_bytes(), before)

    def test_doctor_does_not_prepare_or_launch_an_environment(self):
        result = self.invoke("doctor", "--json", valid=False)
        report = json.loads(result.stdout)
        self.assertFalse(report["readyToOpenSteam"])
        self.assertFalse(report["liveOnlineSessionChecked"])
        self.assertFalse(self.root.exists())
        self.assertNotIn(str(Path.home()), result.stdout)

    def test_import_is_independent_and_preserves_the_original(self):
        source, exe, manifest = self.source_game()
        self.prepare_steam()
        original = exe.read_bytes()
        self.invoke("import-game", str(source))
        copied = self.root / "Steam/drive_c/Program Files (x86)/Steam/steamapps/common" / source.name
        self.assertEqual((copied / "game/bin/win64/cs2.exe").read_bytes(), original)
        self.assertEqual((copied.parent.parent / manifest.name).read_bytes(), manifest.read_bytes())
        (copied / "game/bin/win64/cs2.exe").write_bytes(b"independent update")
        self.assertEqual(exe.read_bytes(), original)
        self.assertNotEqual(exe.stat().st_ino, (copied / "game/bin/win64/cs2.exe").stat().st_ino)

    def test_import_does_not_overwrite_an_existing_installation(self):
        source, _, _ = self.source_game()
        self.prepare_steam()
        self.invoke("import-game", str(source))
        self.assertIn("Conservé ambas", self.invoke("import-game", str(source), valid=False).stderr)

    def test_invalid_source_creates_no_destination(self):
        self.invoke("import-game", str(self.base), valid=False)
        self.assertFalse(self.root.exists())

    def test_import_rejects_links_to_the_original_library(self):
        source, _, _ = self.source_game()
        external = self.base / "external.vpk"
        external.write_bytes(b"must remain outside the managed library")
        (source / "linked.vpk").symlink_to(external)
        self.assertIn("enlaces simbólicos", self.invoke("import-game", str(source), valid=False).stderr)
        self.assertFalse(self.root.exists())
        self.assertEqual(external.read_bytes(), b"must remain outside the managed library")

    def test_import_rejects_a_symlink_as_the_game_root(self):
        source, _, _ = self.source_game()
        linked = self.base / "linked game"
        linked.symlink_to(source, target_is_directory=True)
        self.assertIn("carpeta real", self.invoke("import-game", str(linked), valid=False).stderr)
        self.assertFalse(self.root.exists())

    def test_import_requires_steam_first_to_keep_installer_destination_empty(self):
        source, _, _ = self.source_game()
        self.assertIn("carpeta vacía", self.invoke("import-game", str(source), valid=False).stderr)
        self.assertFalse(self.root.exists())

    def bootstrap_fixture(self):
        self.prepare_steam()
        steam = self.root / "Steam/drive_c/Program Files (x86)/Steam"
        (steam / "logs").mkdir()
        (steam / "package").mkdir()
        log = steam / "logs/bootstrap_log.txt"
        receipt = steam / "package/steam_client_win64.installed"
        log.write_text("[test] Committing NTFS transaction\n[test] Shutdown\n")
        receipt.write_text("synthetic installed receipt")
        old = int(time.time()) - 30
        for path in (log, receipt):
            os.utime(path, (old, old))
        return steam, log, receipt

    def test_bootstrap_status_is_read_only_before_any_update(self):
        result = json.loads(self.invoke("bootstrap-status").stdout)
        self.assertEqual(result["phase"], "waiting")
        self.assertFalse(self.root.exists())

    def test_completed_initial_update_is_distinct_from_an_active_update(self):
        _, log, _ = self.bootstrap_fixture()
        self.assertEqual(json.loads(self.invoke("bootstrap-status").stdout)["phase"], "restart-required")
        log.write_text("[test] Downloading update\n")
        self.assertEqual(json.loads(self.invoke("bootstrap-status").stdout)["phase"], "waiting")

    def test_frontend_evidence_prevents_initial_bootstrap_recovery(self):
        steam, _, _ = self.bootstrap_fixture()
        frontend = steam / "logs/steamui_system.txt"
        frontend.write_text("synthetic frontend startup")
        self.assertEqual(json.loads(self.invoke("bootstrap-status").stdout)["phase"], "frontend-started")
        self.assertEqual(frontend.read_text(), "synthetic frontend startup")

    def test_already_handled_update_cannot_trigger_another_reset(self):
        _, _, receipt = self.bootstrap_fixture()
        record = {"handledReceipts": [int(receipt.stat().st_mtime)]}
        (self.root / "bootstrap-recovery.json").write_text(json.dumps(record))
        self.assertEqual(json.loads(self.invoke("bootstrap-status").stdout)["phase"], "already-recovered")

    def test_initial_recovery_budget_and_corrupt_records_fail_closed(self):
        self.bootstrap_fixture()
        ledger = self.root / "bootstrap-recovery.json"
        ledger.write_text(json.dumps({"handledReceipts": [1, 2]}))
        self.assertEqual(json.loads(self.invoke("bootstrap-status").stdout)["phase"], "recovery-limit")
        ledger.write_text("corrupt")
        self.assertEqual(json.loads(self.invoke("bootstrap-status").stdout)["phase"], "recovery-blocked")

    def test_configuration_mutations_wait_for_the_shared_control_lock(self):
        self.root.mkdir()
        with (self.root / "control.lock").open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            process = subprocess.Popen(
                [LAUNCHER, "--data-root", str(self.root), "use-managed"],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            )
            try:
                with self.assertRaises(subprocess.TimeoutExpired):
                    process.communicate(timeout=0.2)
                self.assertFalse((self.root / "selection.json").exists())
                fcntl.flock(lock, fcntl.LOCK_UN)
                _, error = process.communicate(timeout=15)
                self.assertEqual(process.returncode, 0, error)
                self.assertEqual(json.loads((self.root / "selection.json").read_text())["backend"], "managed")
            finally:
                if process.poll() is None:
                    process.kill()
                    process.communicate()


if __name__ == "__main__":
    unittest.main()
