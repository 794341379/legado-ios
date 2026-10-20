#!/usr/bin/env python3
"""Generate the AltStore/SideStore source from a published release's unsigned IPA."""

import argparse
import hashlib
import json
import plistlib
import re
import zipfile
from datetime import datetime
from pathlib import Path
from urllib.parse import quote


def make_source(ipa: Path, release: dict, repository: str, branch: str) -> dict:
    if release.get("draft") or release.get("prerelease"):
        raise ValueError("Only published stable releases belong in this source")
    date = release["published_at"]
    if datetime.fromisoformat(date.replace("Z", "+00:00")).tzinfo is None:
        raise ValueError("Release publication date must include a timezone")
    assets = [asset for asset in release["assets"] if asset["name"] == ipa.name]
    if len(assets) != 1 or assets[0].get("state") != "uploaded":
        raise ValueError("IPA must match exactly one uploaded release asset")
    asset = assets[0]
    if ipa.stat().st_size != asset["size"]:
        raise ValueError("IPA size differs from the published release asset")
    digest = asset.get("digest")
    if digest and digest != "sha256:" + hashlib.sha256(ipa.read_bytes()).hexdigest():
        raise ValueError("IPA checksum differs from the published release asset")

    with zipfile.ZipFile(ipa) as archive:
        names = archive.namelist()
        info_paths = [name for name in names if re.fullmatch(r"Payload/[^/]+\.app/Info\.plist", name)]
        if len(info_paths) != 1:
            raise ValueError("Expected exactly one app in Payload")
        if any("/_CodeSignature/" in name or name.endswith("/embedded.mobileprovision")
               or ".appex/" in name for name in names):
            raise ValueError("Use an unsigned IPA without extensions; signed apps need an entitlement audit")
        info = plistlib.loads(archive.read(info_paths[0]))
    for key in ("CFBundleIdentifier", "CFBundleShortVersionString", "CFBundleVersion", "MinimumOSVersion"):
        if not isinstance(info.get(key), str) or not info[key] or "$(" in info[key]:
            raise ValueError(f"IPA has an invalid or unresolved {key}")
    if info["CFBundleIdentifier"] != "com.epiboly.legado":
        raise ValueError("IPA bundle identifier does not belong to this app")
    if release["tag_name"] != "v" + info["CFBundleShortVersionString"]:
        raise ValueError("Release tag does not match the IPA version")

    website = f"https://github.com/{repository}"
    download_url = f"{website}/releases/download/{quote(release['tag_name'], safe='')}/{quote(ipa.name, safe='')}"
    if asset["browser_download_url"] != download_url:
        raise ValueError("Release asset URL does not match the repository, tag and IPA name")
    raw_url = f"https://raw.githubusercontent.com/{repository}/{quote(branch, safe='')}"
    icon_url = f"{raw_url}/App/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
    version = {
        "version": info["CFBundleShortVersionString"],
        "buildVersion": info["CFBundleVersion"],
        "date": date,
        "localizedDescription": release.get("body") or release.get("name") or release["tag_name"],
        "downloadURL": download_url,
        "size": asset["size"],
        "minOSVersion": info["MinimumOSVersion"],
    }
    return {
        "name": "小浣熊阅读",
        "identifier": "com.epiboly.legado.source",
        "subtitle": "小浣熊阅读官方应用源",
        "description": "小浣熊阅读的最新正式版，供 AltStore Classic、SideStore 和 LiveContainer 添加。",
        "sourceURL": f"{raw_url}/docs/altstore.json",
        "website": website,
        "iconURL": icon_url,
        "tintColor": "#315C50",
        "apps": [{
            "name": info.get("CFBundleDisplayName") or info["CFBundleName"],
            "bundleIdentifier": info["CFBundleIdentifier"],
            "developerName": repository.split("/")[0],
            "subtitle": "搜书快一点，读书舒服一点。",
            "localizedDescription": "一款优先兼容阅读书源的开源 iOS 阅读器，支持书架、搜索、阅读排版、本地 TXT、语音朗读和 RSS。应用不提供书源或在线书库，书源需自行导入。",
            "iconURL": icon_url,
            "tintColor": "#315C50",
            "category": "utilities",
            "screenshots": [
                {"imageURL": f"{raw_url}/docs/images/{name}.png", "width": 1206, "height": 2622}
                for name in ("bookshelf", "search", "reader")
            ],
            "versions": [version],
            "version": version["version"],
            "versionDate": date,
            "versionDescription": version["localizedDescription"],
            "downloadURL": download_url,
            "size": asset["size"],
            "appPermissions": {
                "entitlements": [],
                "privacy": {key: value for key, value in info.items()
                            if key.startswith("NS") and "UsageDescription" in key},
            },
        }],
        "news": [],
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ipa", required=True, type=Path)
    parser.add_argument("--release", required=True, type=Path, help="GitHub REST release JSON")
    parser.add_argument("--repository", default="Aminark/legado-ios")
    parser.add_argument("--branch", default="main", help="Branch hosting the source and images")
    parser.add_argument("--output", type=Path, default=Path("docs/altstore.json"))
    args = parser.parse_args()
    try:
        source = make_source(args.ipa, json.loads(args.release.read_text(encoding="utf-8")),
                             args.repository, args.branch)
    except (ValueError, KeyError, OSError, zipfile.BadZipFile) as error:
        parser.error(str(error))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(source, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Generated {args.output} from {args.ipa.name}")


if __name__ == "__main__":
    main()
