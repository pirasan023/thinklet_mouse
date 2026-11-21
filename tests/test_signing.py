import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

MODULE = Path(__file__).resolve().parents[1] / 'scripts/sign-app.py'
spec = importlib.util.spec_from_file_location('sign_app', MODULE)
signer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(signer)
FINGERPRINT = '12' * 20
REQUIREMENT = f'designated => identifier "ai.thinklet.handmouse.mac" and certificate leaf = H"{FINGERPRINT}"'

class SigningContinuity(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.keychain = self.root / 'local.keychain-db'
        self.keychain.touch()
        (self.root / 'password').write_text('test-only\n')
        self.addCleanup(patch.stopall)
        patch.object(signer, 'LOCAL', self.root).start()
        patch.object(signer, 'KEYCHAIN', self.keychain).start()

    def fake_tools(self, requirement=REQUIREMENT):
        def run(args, **kwargs):
            if 'find-certificate' in args:
                return f'SHA-1 hash: {FINGERPRINT}\n'
            if '-r-' in args:
                return requirement
            return ''
        return patch.object(signer, 'run', side_effect=run)

    def test_same_identity_survives_updates(self):
        with self.fake_tools():
            signer.sign(self.root / 'first.app')
            signer.sign(self.root / 'changed-binary.app')
        self.assertEqual((self.root / 'designated-requirement.txt').read_text().strip(), REQUIREMENT)

    def test_changed_requirement_does_not_overwrite_saved_identity(self):
        recorded = self.root / 'designated-requirement.txt'
        recorded.write_text(REQUIREMENT + '\n')
        changed = REQUIREMENT.replace('ai.thinklet.handmouse.mac', 'other.app')
        with self.fake_tools(changed):
            with self.assertRaisesRegex(RuntimeError, 'identity changed'):
                signer.sign(self.root / 'changed.app')
        self.assertEqual(recorded.read_text().strip(), REQUIREMENT)

    def test_ad_hoc_result_is_rejected(self):
        with self.fake_tools('designated => cdhash H"' + FINGERPRINT + '"'):
            with self.assertRaisesRegex(RuntimeError, 'certificate-based'):
                signer.sign(self.root / 'adhoc.app')

    def test_unpinned_identity_is_rejected(self):
        with self.fake_tools('designated => identifier "ai.thinklet.handmouse.mac"'):
            with self.assertRaisesRegex(RuntimeError, 'certificate-based'):
                signer.sign(self.root / 'unbound.app')

    def test_synthesized_requirement_output_is_understood(self):
        with self.fake_tools('# ' + REQUIREMENT):
            signer.sign(self.root / 'App.app')
        self.assertEqual((self.root / 'designated-requirement.txt').read_text().strip(), REQUIREMENT)

    def test_missing_keychain_does_not_fall_back(self):
        self.keychain.unlink()
        with patch.object(signer, 'run') as run:
            with self.assertRaisesRegex(RuntimeError, 'Ad-hoc signing is disabled'):
                signer.sign(self.root / 'App.app')
            run.assert_not_called()

if __name__ == '__main__':
    unittest.main()
