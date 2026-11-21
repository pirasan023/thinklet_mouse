import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

MODULE = Path(__file__).resolve().parents[1] / 'scripts/installer_core.py'
spec = importlib.util.spec_from_file_location('installer_core', MODULE)
core = importlib.util.module_from_spec(spec)
spec.loader.exec_module(core)

class InstallerTransaction(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.old = self.root / 'App.app'
        self.new = self.root / 'staging.app'
        self.previous = self.root / 'previous.app'
        self.new.mkdir()
        (self.new / 'version').write_text('new')

    def test_first_install(self):
        self.assertIsNone(core.replace_app(self.new, self.old, self.previous))
        self.assertEqual((self.old / 'version').read_text(), 'new')

    def test_update_retains_previous_app(self):
        self.old.mkdir()
        (self.old / 'version').write_text('old')
        self.assertEqual(core.replace_app(self.new, self.old, self.previous), self.previous)
        self.assertEqual((self.old / 'version').read_text(), 'new')
        self.assertEqual((self.previous / 'version').read_text(), 'old')

    def test_failed_update_restores_old_app(self):
        self.old.mkdir()
        (self.old / 'version').write_text('old')
        original = core.os.rename
        def fail_new(source, destination):
            if source == self.new:
                raise PermissionError('simulated install failure')
            original(source, destination)
        with patch.object(core.os, 'rename', side_effect=fail_new):
            with self.assertRaises(PermissionError):
                core.replace_app(self.new, self.old, self.previous)
        self.assertEqual((self.old / 'version').read_text(), 'old')
        self.assertTrue(self.new.exists())

    def test_existing_backup_is_not_overwritten(self):
        self.previous.mkdir()
        with self.assertRaises(FileExistsError):
            core.replace_app(self.new, self.old, self.previous)
        self.assertTrue(self.new.exists())

if __name__ == '__main__':
    unittest.main()
