"""Reglas del validador de mods (paridad con game/core/mod_registry.gd)."""
import json
from pathlib import Path
import tempfile
import unittest

from pocx import mods


def base(**extra):
    data = {"id": "yugis-gods", "name": "Yugi's Gods", "version": "1.0.0", "api": 1}
    data.update(extra)
    return data


class ManifestTests(unittest.TestCase):
    def test_minimal_manifest_is_valid(self):
        self.assertEqual(mods.validate_manifest(base(), "yugis-gods"), [])

    def test_rejects_bad_ids_and_folder_mismatch(self):
        self.assertTrue(mods.validate_manifest(base(id="../x"), "../x"))
        self.assertTrue(mods.validate_manifest(base(id="A"), "A"))
        self.assertTrue(mods.validate_manifest(base(), "otra-carpeta"))

    def test_rejects_wrong_api_games_engine_requires(self):
        self.assertTrue(mods.validate_manifest(base(api=2), "yugis-gods"))
        self.assertTrue(mods.validate_manifest(base(api=True), "yugis-gods"))
        self.assertTrue(mods.validate_manifest(base(games=[]), "yugis-gods"))
        self.assertTrue(mods.validate_manifest(base(games=["pegasus"]), "yugis-gods"))
        self.assertTrue(mods.validate_manifest(base(engine="x"), "yugis-gods"))
        self.assertTrue(mods.validate_manifest(base(requires=["../a"]), "yugis-gods"))
        self.assertTrue(mods.validate_manifest([], "yugis-gods"))

    def test_scripts_list(self):
        self.assertEqual(mods.validate_manifest(base(scripts=["scripts/slifer.gd", "scripts/x/y_z.gd"]), "yugis-gods"), [])
        for bad in ("slifer.gd", "scripts/../x.gd", "scripts/a.txt", "/scripts/a.gd", "scripts\\a.gd", "scripts/a b.gd", 5):
            self.assertTrue(mods.validate_manifest(base(scripts=[bad]), "yugis-gods"), bad)
        self.assertTrue(mods.validate_manifest(base(scripts="scripts/a.gd"), "yugis-gods"))
        self.assertTrue(mods.validate_manifest(base(scripts=[f"scripts/s{i}.gd" for i in range(9)]), "yugis-gods"))


class FolderTests(unittest.TestCase):
    def make(self, manifest, files=()):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        folder = Path(tmp.name) / manifest["id"]
        folder.mkdir()
        (folder / "mod.json").write_text(json.dumps(manifest), encoding="utf-8")
        for rel in files:
            target = folder / "assets" / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(b"x")
        return folder

    def test_warns_about_protected_and_undeclared_game_files(self):
        folder = self.make(base(games=["yugi"]), [
            "yugi/card/god.png", "kaiba/card/x.png", "common/db/cards.json", "common/ok.png"])
        errors, warnings = mods.validate_mod(folder)
        self.assertEqual(errors, [])
        self.assertEqual(len(warnings), 2)
        self.assertTrue(any("kaiba/card/x.png" in w for w in warnings))
        self.assertTrue(any("cards.json" in w for w in warnings))

    def test_script_must_exist_and_warns_about_code(self):
        folder = self.make(base(scripts=["scripts/a.gd"]))
        errors, _ = mods.validate_mod(folder)
        self.assertTrue(any("scripts/a.gd" in e for e in errors))
        (folder / "scripts").mkdir()
        (folder / "scripts" / "a.gd").write_text("extends ModScript\n", encoding="utf-8")
        errors, warnings = mods.validate_mod(folder)
        self.assertEqual(errors, [])
        self.assertTrue(any("codigo" in w for w in warnings))

    def test_missing_manifest(self):
        with tempfile.TemporaryDirectory() as tmp:
            errors, _ = mods.validate_mod(Path(tmp))
            self.assertEqual(errors, ["falta mod.json"])


class CardFragmentTests(unittest.TestCase):
    def card(self, **extra):
        data = {"key": "obelisk", "names": {"eng": "Obelisk"}, "descriptions": {"eng": "d"},
                "atk": 4000, "defense": 4000, "level": 10, "attribute": "dark", "type_id": 1}
        data.update(extra)
        return data

    def test_effect_and_revive_by(self):
        self.assertEqual(mods.validate_card(self.card(effect="slifer", revive_by=[1008, "0x447"]), ["yugi"]), [])
        for bad in ({"effect": "Bad Key"}, {"effect": 5}, {"revive_by": 1008}, {"revive_by": [0]},
                    {"revive_by": [2000]}, {"revive_by": ["zz"]}, {"revive_by": [True]}):
            self.assertTrue(mods.validate_card(self.card(**bad), ["yugi"]), bad)

    def test_valid_and_invalid_cards(self):
        self.assertEqual(mods.validate_card(self.card(), ["yugi"]), [])
        for bad in (dict(atk=4005), dict(atk=5120), dict(level=16), dict(attribute="cosmic"),
                    dict(image="../a.png"), dict(key="X!"), dict(names={"fra": "x"}), dict(games=["pegasus"]),
                    dict(password="12")):
            self.assertTrue(mods.validate_card(self.card(**bad), ["yugi"]), bad)
        self.assertEqual(mods.validate_card({"key": "m1", "category": "spell", "names": {"eng": "M"},
                                             "descriptions": {"eng": "d"}}, ["yugi"]), [])

    def test_folder_checks_cards_images_and_duplicate_keys(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp) / "yugis-gods"
            (folder / "assets/common/card").mkdir(parents=True)
            (folder / "mod.json").write_text(json.dumps(base()), encoding="utf-8")
            (folder / "cards.json").write_text(json.dumps([self.card(image="obelisk.png"), self.card()]), encoding="utf-8")
            errors, warnings = mods.validate_mod(folder)
            self.assertTrue(any("key repetida" in e for e in errors))
            self.assertTrue(any("assets/common/card/obelisk.png" in w for w in warnings))
            self.assertTrue(any("assets/common/mini/obelisk.png" in w for w in warnings))


class InspectTests(unittest.TestCase):
    def test_reports_free_ids_variants_and_capacity(self):
        import struct
        with tempfile.TemporaryDirectory() as tmp:
            bin_dir = Path(tmp) / "common/bin"
            bin_dir.mkdir(parents=True)
            ids = [0, 10, 1919, 1918, 3918]
            int_ids = [0] * 2048
            for i in (1, 2, 3):
                int_ids[ids[i]] = i
            props = [0, 1, 2, 3, 4]
            (bin_dir / "card_id.bin").write_bytes(struct.pack(f"<{len(ids)}H", *ids))
            (bin_dir / "card_intid.bin").write_bytes(struct.pack("<2048H", *int_ids))
            (bin_dir / "card_prop.bin").write_bytes(struct.pack(f"<{len(props)}I", *props))
            (bin_dir / "card_pack.bin").write_bytes(struct.pack("<5H", 0, 1, 1, 1, 1))
            import zlib
            def chunk(tag, data):
                return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff)
            png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 177, 254, 8, 2, 0, 0, 0)) + chunk(b"IEND", b"")
            (Path(tmp) / "common/card").mkdir()
            (Path(tmp) / "common/card/a.png").write_bytes(png)
            self.assertEqual(mods.image_size(Path(tmp) / "common/card/a.png"), (177, 254))
            report = "\n".join(mods.inspect_tables(Path(tmp)))
            self.assertIn("(177, 254)", report)
            self.assertIn("primer indice libre tras las tablas: 5", report)
            self.assertIn("[1917, 1916", report)
            self.assertIn("variantes que NO cumplen index_of(id)=CARD_IntID[id%2000]+1: 0", report)


if __name__ == "__main__":
    unittest.main()
