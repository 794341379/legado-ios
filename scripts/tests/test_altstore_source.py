import hashlib
import importlib.util
import plistlib
import tempfile
import unittest
import zipfile
from pathlib import Path


spec = importlib.util.spec_from_file_location("altstore_source", Path(__file__).parents[1] / "update-altstore-source.py")
altstore_source = importlib.util.module_from_spec(spec)
spec.loader.exec_module(altstore_source)


class AltStoreSourceTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.ipa = Path(temporary.name) / "reader-unsigned.ipa"
        self.info = {
            "CFBundleIdentifier": "com.epiboly.legado",
            "CFBundleName": "Reader",
            "CFBundleDisplayName": "小浣熊阅读",
            "CFBundleShortVersionString": "1.2.3",
            "CFBundleVersion": "42",
            "MinimumOSVersion": "15.0",
            "NSCameraUsageDescription": "扫描导入二维码",
            "NSPhotoLibraryAddUsageDescription": "保存图片",
            "NSAppTransportSecurity": {"NSAllowsArbitraryLoads": True},
        }
        self.release = {
            "tag_name": "v1.2.3",
            "published_at": "2026-10-19T01:02:03Z",
            "draft": False,
            "prerelease": False,
            "body": "更新阅读体验。",
        }
        self.write_ipa()

    def write_ipa(self, extra=None):
        with zipfile.ZipFile(self.ipa, "w") as archive:
            archive.writestr("Payload/Reader.app/Info.plist", plistlib.dumps(self.info, fmt=plistlib.FMT_BINARY))
            if extra:
                archive.writestr(extra, b"fixture")
        self.release["assets"] = [{
            "name": self.ipa.name,
            "state": "uploaded",
            "size": self.ipa.stat().st_size,
            "digest": "sha256:" + hashlib.sha256(self.ipa.read_bytes()).hexdigest(),
            "browser_download_url": "https://github.com/Aminark/legado-ios/releases/download/v1.2.3/reader-unsigned.ipa",
        }]

    def generate(self):
        return altstore_source.make_source(self.ipa, self.release, "Aminark/legado-ios", "main")

    def test_metadata_permissions_and_legacy_fields_match_ipa(self):
        source = self.generate()
        self.assertEqual(source["sourceURL"], "https://raw.githubusercontent.com/Aminark/legado-ios/main/docs/altstore.json")
        app = source["apps"][0]
        version = app["versions"][0]
        self.assertEqual(app["bundleIdentifier"], self.info["CFBundleIdentifier"])
        self.assertEqual(version["version"], "1.2.3")
        self.assertEqual(version["buildVersion"], "42")
        self.assertEqual(version["minOSVersion"], "15.0")
        self.assertEqual(version["date"], self.release["published_at"])
        for key in ("version", "size", "downloadURL"):
            self.assertEqual(app[key], version[key])
        self.assertEqual(app["appPermissions"], {
            "entitlements": [],
            "privacy": {
                "NSCameraUsageDescription": "扫描导入二维码",
                "NSPhotoLibraryAddUsageDescription": "保存图片",
            },
        })

    def test_rejects_drafts_and_prereleases(self):
        for key in ("draft", "prerelease"):
            with self.subTest(key=key):
                self.release[key] = True
                with self.assertRaisesRegex(ValueError, "published stable"):
                    self.generate()
                self.release[key] = False

    def test_rejects_wrong_release_asset(self):
        for key, value in (("size", 1), ("digest", "sha256:wrong"),
                           ("browser_download_url", "https://example.com/wrong.ipa"),
                           ("name", "another.ipa"), ("state", "new")):
            with self.subTest(key=key):
                self.write_ipa()
                self.release["assets"][0][key] = value
                with self.assertRaises(ValueError):
                    self.generate()

    def test_older_github_metadata_without_digest_is_supported(self):
        del self.release["assets"][0]["digest"]
        self.assertEqual(self.generate()["apps"][0]["version"], "1.2.3")

    def test_rejects_packages_needing_an_entitlement_audit(self):
        for extra in ("Payload/Reader.app/_CodeSignature/CodeResources",
                      "Payload/Reader.app/embedded.mobileprovision",
                      "Payload/Reader.app/PlugIns/Widget.appex/Info.plist"):
            with self.subTest(extra=extra):
                self.write_ipa(extra)
                with self.assertRaisesRegex(ValueError, "entitlement audit"):
                    self.generate()

    def test_rejects_unresolved_build_metadata(self):
        self.info["CFBundleVersion"] = "$(CURRENT_PROJECT_VERSION)"
        self.write_ipa()
        with self.assertRaisesRegex(ValueError, "CFBundleVersion"):
            self.generate()

    def test_rejects_release_and_package_mismatches(self):
        self.info["CFBundleIdentifier"] = "com.example.another-app"
        self.write_ipa()
        with self.assertRaisesRegex(ValueError, "bundle identifier"):
            self.generate()
        self.info["CFBundleIdentifier"] = "com.epiboly.legado"
        self.info["CFBundleShortVersionString"] = "1.2.4"
        self.write_ipa()
        with self.assertRaisesRegex(ValueError, "Release tag"):
            self.generate()

    def test_rejects_publication_dates_without_a_timezone(self):
        self.release["published_at"] = "2026-10-19T01:02:03"
        with self.assertRaisesRegex(ValueError, "timezone"):
            self.generate()


if __name__ == "__main__":
    unittest.main()
