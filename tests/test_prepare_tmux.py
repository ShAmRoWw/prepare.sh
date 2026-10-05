"""Offline regressions for tmux plugin executable permissions and validation."""

import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "prepare.sh"
DEFINITIONS = SCRIPT.read_text().split("#  Точка входа", 1)[0]
EXECUTABLES = {
    "tpm": ("tpm",),
    "tmux-sensible": ("sensible.tmux",),
    "tmux-logging": (
        "logging.tmux",
        "scripts/toggle_logging.sh",
        "scripts/start_logging.sh",
        "scripts/screen_capture.sh",
        "scripts/save_complete_history.sh",
        "scripts/clear_history.sh",
        "scripts/check_tmux_version.sh",
    ),
}


class PrepareTmuxPermissionsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="prepare-tmux-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.plugins = self.root / "plugins"
        self.conf = self.root / "tmux.conf"
        self.original_conf = b"# User settings\nset -g status off\n"
        self.conf.write_bytes(self.original_conf)
        self.conf.chmod(0o640)
        self.environment = os.environ | {
            "GIT_CONFIG_GLOBAL": os.devnull,
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_AUTHOR_NAME": "Prepare test",
            "GIT_AUTHOR_EMAIL": "prepare-test@example.invalid",
            "GIT_COMMITTER_NAME": "Prepare test",
            "GIT_COMMITTER_EMAIL": "prepare-test@example.invalid",
        }

    def bash(self, code, status=0):
        setup = f"""
TEST_ROOT={shlex.quote(str(self.root))}
TMUX_PLUGIN_DIR="$TEST_ROOT/plugins"
TMUX_LOG_DIR="$TEST_ROOT/logs"
umask 022
tmux() {{ touch "$TEST_ROOT/tmux-called"; return 98; }}
"""
        result = subprocess.run(
            ["bash", "-s"], input=DEFINITIONS + setup + code,
            text=True, capture_output=True, env=self.environment, timeout=20,
        )
        self.assertEqual(result.returncode, status, result.stdout + result.stderr)
        return result

    def git(self, path, *args):
        return subprocess.run(
            ["git", "-C", str(path), *args], check=True, text=True,
            capture_output=True, env=self.environment, timeout=20,
        ).stdout.strip()

    def write_plugin(self, path, name, executable=False):
        path.mkdir(parents=True, exist_ok=True)
        for relative in EXECUTABLES[name]:
            file = path / relative
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text(f"#!/usr/bin/env bash\n# Fixture for {relative}\nexit 0\n")
            file.chmod(0o744 if executable else 0o644)
        (path / "README.md").write_text("Documentation should stay non-executable.\n")
        (path / "README.md").chmod(0o644)

    def repository(self, name="tmux-logging"):
        path = self.root / "source"
        self.write_plugin(path, name)
        self.git(path, "init", "-q")
        self.git(path, "add", ".")
        self.git(path, "commit", "-qm", "Plugin with missing executable bits")
        return path

    def ready_plugins(self):
        for name in EXECUTABLES:
            self.write_plugin(self.plugins / name, name, executable=True)

    def assert_original_config(self):
        self.assertEqual(self.conf.read_bytes(), self.original_conf)
        self.assertEqual(self.conf.stat().st_mode & 0o777, 0o640)
        self.assertEqual(list(self.root.glob("tmux.conf.prepare.*")), [])
        self.assertFalse((self.root / "tmux-called").exists())

    def test_fresh_clone_and_existing_install_repair_all_runtime_scripts(self):
        source = self.repository()
        revision = self.git(source, "rev-parse", "HEAD")
        expected = {
            file: (source / file).read_bytes() for file in EXECUTABLES["tmux-logging"]
        }
        self.bash('tmux_install_plugin tmux-logging "$TEST_ROOT/source"\n')
        installed = self.plugins / "tmux-logging"
        self.assertEqual(self.git(installed, "rev-parse", "HEAD"), revision)
        for relative, content in expected.items():
            file = installed / relative
            self.assertEqual(file.read_bytes(), content)
            self.assertEqual(file.stat().st_mode & 0o777, 0o744)
            file.chmod(0o644)
        # Existing installations must be repaired without fetching or replacing
        # their checkout. Keep a user modification to make that observable.
        modified = installed / "scripts/start_logging.sh"
        modified.write_bytes(expected["scripts/start_logging.sh"] + b"# local change\n")
        expected["scripts/start_logging.sh"] = modified.read_bytes()
        self.bash('tmux_install_plugin tmux-logging "$TEST_ROOT/no-such-repository"\n')
        self.bash('tmux_install_plugin tmux-logging "$TEST_ROOT/no-such-repository"\n')
        self.assertEqual(self.git(installed, "rev-parse", "HEAD"), revision)
        for relative, content in expected.items():
            self.assertEqual((installed / relative).read_bytes(), content)
            self.assertEqual((installed / relative).stat().st_mode & 0o777, 0o744)
        self.assertEqual((installed / "README.md").stat().st_mode & 0o777, 0o644)

    def test_incomplete_clone_is_not_reported_as_installed(self):
        source = self.repository()
        missing = "scripts/start_logging.sh"
        self.git(source, "rm", missing)
        self.git(source, "commit", "-qm", "Incomplete plugin")
        result = self.bash(
            'tmux_install_plugin tmux-logging "$TEST_ROOT/source"\n', status=1,
        )
        self.assertIn(str(self.plugins / "tmux-logging" / missing), result.stdout)
        self.assertNotIn("tmux plugin tmux-logging установлен", result.stdout)

    def test_logging_entrypoint_alone_cannot_pass_config_validation(self):
        self.ready_plugins()
        handler = self.plugins / "tmux-logging/scripts/toggle_logging.sh"
        handler.chmod(0o644)
        result = self.bash('tmux_write_config "$TEST_ROOT/tmux.conf"\n', status=1)
        self.assertIn(str(handler), result.stdout)
        self.assertEqual(handler.stat().st_mode & 0o777, 0o644)
        self.assert_original_config()

    def test_missing_runtime_files_fail_before_starting_tmux(self):
        self.ready_plugins()
        for name, relatives in EXECUTABLES.items():
            for relative in relatives:
                with self.subTest(plugin=name, file=relative):
                    file = self.plugins / name / relative
                    content = file.read_bytes()
                    file.unlink()
                    result = self.bash(
                        'tmux_write_config "$TEST_ROOT/tmux.conf"\n', status=1,
                    )
                    self.assertIn(str(file), result.stdout)
                    self.assert_original_config()
                    file.write_bytes(content)
                    file.chmod(0o744)

    def test_symlink_handler_is_rejected_without_changing_its_target(self):
        source = self.repository()
        handler = source / "scripts/start_logging.sh"
        outside = self.root / "outside.sh"
        outside.write_text("#!/usr/bin/env bash\n# unrelated file\n")
        outside.chmod(0o644)
        handler.unlink()
        handler.symlink_to(outside)
        self.git(source, "add", "scripts/start_logging.sh")
        self.git(source, "commit", "-qm", "Symlink handler")
        result = self.bash(
            'tmux_install_plugin tmux-logging "$TEST_ROOT/source"\n', status=1,
        )
        self.assertIn(str(self.plugins / "tmux-logging/scripts/start_logging.sh"), result.stdout)
        self.assertEqual(outside.stat().st_mode & 0o777, 0o644)
        self.assertEqual(outside.read_text(), "#!/usr/bin/env bash\n# unrelated file\n")
        # Even an executable symlink target cannot make validation succeed.
        outside.chmod(0o744)
        for name in ("tpm", "tmux-sensible"):
            self.write_plugin(self.plugins / name, name, executable=True)
        for relative in EXECUTABLES["tmux-logging"]:
            file = self.plugins / "tmux-logging" / relative
            if not file.is_symlink():
                file.chmod(0o744)
        self.bash('tmux_write_config "$TEST_ROOT/tmux.conf"\n', status=1)
        self.assert_original_config()


if __name__ == "__main__":
    unittest.main()
