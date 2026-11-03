"""Python 3.10+; no pip installs needed. Rebuild and verify the installable pak."""
import hashlib
import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE / "vendor"))
from bg3forge.parsers.lsf import write_lsf, parse_lsf
from bg3forge.parsers.lsx import parse_lsx
from bg3forge.parsers.localization import LocaEntry, write_loca, parse_loca
from bg3forge.parsers.meta import parse_meta
from bg3forge.parsers.stats import parse_stats
from bg3forge.pak.reader import PakReader
from package import pack


def build():
    source = ROOT / "source"
    meta = parse_meta(parse_lsx((source / "Mods/EvergrowthRing/meta.lsx").read_bytes()))
    assert meta.uuid == "7d174b8e-d212-49a3-bd8b-94f17bd08633"
    assert meta.folder == "EvergrowthRing" and meta.mod_type == "Add-on"
    assert meta.version == (0, 4, 0, 0)
    extender = json.loads((source / "Mods/EvergrowthRing/ScriptExtender/Config.json").read_text())
    assert extender["RequiredVersion"] == 34 and extender["FeatureFlags"] == ["Lua"]
    stats = [entry for path in (source / "Public/EvergrowthRing/Stats/Generated/Data").glob("*.txt")
             for entry in parse_stats(path.read_text(encoding="utf-8"))]
    assert {entry.name for entry in stats} == {"ER_Ring_Evergrowth", "ER_EQUIPPED", "Shout_ER_Inspect"}
    templates = source / "Public/EvergrowthRing/RootTemplates"
    document = parse_lsx((templates / "_merged.lsx").read_bytes())
    binary = write_lsf(document, version=7)
    decoded = list(parse_lsf(binary).find_all("GameObjects"))
    assert len(decoded) == 1
    assert decoded[0].get("MapKey") == "2cbb59be-e573-4dfa-8d40-52db636de013"
    assert decoded[0].get("Stats") == "ER_Ring_Evergrowth"
    assert decoded[0].get("LevelName") == ""
    (templates / "_merged.lsf").write_bytes(binary)
    for language in ["English", "Chinese"]:
        xml = ET.parse(ROOT / "localization" / (language + ".xml"))
        entries = [LocaEntry(e.attrib["contentuid"], int(e.attrib["version"]), e.text or "")
                   for e in xml.getroot()]
        assert len(entries) == len({entry.key for entry in entries})
        for entry in entries:
            assert re.fullmatch(r"h[0-9a-f]{8}g[0-9a-f]{4}g[0-9a-f]{4}g[0-9a-f]{4}g[0-9a-f]{12}", entry.key)
        binary = write_loca(entries)
        assert parse_loca(binary) == entries
        directory = source / "Localization" / language
        directory.mkdir(parents=True, exist_ok=True)
        (directory / "EvergrowthRing.loca").write_bytes(binary)
    pak = ROOT / "EvergrowthRing.pak"
    expected = pack(source, pak)
    with PakReader(pak) as archive:
        assert archive.header.version == 18
        actual = {name: hashlib.sha256(archive.read(name)).hexdigest() for name in archive.names()}
        assert actual == expected, "PAK round-trip differs from the source"
        assert any(name.endswith("/_merged.lsf") for name in actual)
        assert any(name.endswith("/meta.lsx") for name in actual)
    manifest = {"file": pak.name, "version": "0.4.0", "sha256": hashlib.sha256(pak.read_bytes()).hexdigest(),
                "format": "LSPK v18", "entries": expected,
                "game_tested": False, "windows_tested": False}
    (ROOT / "BUILD_MANIFEST.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"Built and round-trip verified {pak.name}: {len(expected)} files, {pak.stat().st_size} bytes")
    print("This is archive validation, NOT an in-game compatibility test.")
    return pak


if __name__ == "__main__":
    build()
