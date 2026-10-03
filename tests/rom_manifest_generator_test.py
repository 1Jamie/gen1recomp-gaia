#!/usr/bin/env python3
"""ROM-free regression tests for the manifest generator's version pin and
its documented, deliberate overrides. No pokered checkout or ROM needed."""

from pathlib import Path
from unittest import TestCase, main, mock

import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import make_rom_manifest  # noqa: E402


class CheckPokeredRevisionTest(TestCase):
    def test_matching_revision_is_silent(self):
        with mock.patch.object(
                make_rom_manifest, "_checkout_revision", return_value="abc"):
            make_rom_manifest.check_pokered_revision("/pokered", "abc")

    def test_mismatched_revision_raises(self):
        with mock.patch.object(
                make_rom_manifest, "_checkout_revision", return_value="abc"):
            with self.assertRaises(SystemExit):
                make_rom_manifest.check_pokered_revision("/pokered", "def")

    def test_allow_mismatch_bypasses_the_raise(self):
        with mock.patch.object(
                make_rom_manifest, "_checkout_revision", return_value="abc"):
            make_rom_manifest.check_pokered_revision(
                "/pokered", "def", allow_mismatch=True)

    def test_unresolvable_checkout_is_silent(self):
        # _checkout_revision returns None for a non-git directory; nothing
        # to compare against, so this must not block generation.
        with mock.patch.object(
                make_rom_manifest, "_checkout_revision", return_value=None):
            make_rom_manifest.check_pokered_revision("/pokered", "abc")


class ApplyKnownNonreproducibleOverridesTest(TestCase):
    def fixtures(self):
        texts = {"trainerHeaders": {}}
        field_data = {
            "seafoam": {
                "SEAFOAM_ISLANDS_B3F": {
                    "pluggedByHolesOn": {
                        "holes": [{"showObject": "X"}, {"showObject": "Y"}],
                    },
                },
            },
            "tradeArt": {"bubble": "assets/generated/trade/bubble.png"},
        }
        return texts, field_data

    def test_mtmoonb2f_super_nerd_slot_is_pinned(self):
        texts, field_data = self.fixtures()
        make_rom_manifest.apply_known_nonreproducible_overrides(
            texts, field_data)

        self.assertEqual(texts["trainerHeaders"]["MtMoonB2F"][1], {
            "after": "_MtMoonB2FSuperNerdTheresAPokemonLabText",
            "battle": "_MtMoonB2FSuperNerdTheyreBothMineText",
            "event": "EVENT_BEAT_MT_MOON_3_SUPER_NERD",
            "won": "_MtMoonB2FSuperNerdOkIllShareText",
        })

    def test_mtmoonb2f_survives_a_populated_map_entry(self):
        # A fresh extraction already fills in the map's other slots (2-5);
        # the override must add slot 1 alongside them, not replace them.
        texts, field_data = self.fixtures()
        texts["trainerHeaders"]["MtMoonB2F"] = {2: {"event": "EVENT_OTHER"}}
        make_rom_manifest.apply_known_nonreproducible_overrides(
            texts, field_data)

        self.assertIn(1, texts["trainerHeaders"]["MtMoonB2F"])
        self.assertEqual(
            texts["trainerHeaders"]["MtMoonB2F"][2], {"event": "EVENT_OTHER"})

    def test_seafoam_boulder_toggle_ids_are_pinned(self):
        texts, field_data = self.fixtures()
        make_rom_manifest.apply_known_nonreproducible_overrides(
            texts, field_data)

        holes = field_data["seafoam"]["SEAFOAM_ISLANDS_B3F"][
            "pluggedByHolesOn"]["holes"]
        self.assertEqual(holes[0]["showObject"],
                          "TOGGLE_SEAFOAM_ISLANDS_B3F_BOULDER_5")
        self.assertEqual(holes[1]["showObject"],
                          "TOGGLE_SEAFOAM_ISLANDS_B3F_BOULDER_6")

    def test_trade_art_is_dropped(self):
        texts, field_data = self.fixtures()
        make_rom_manifest.apply_known_nonreproducible_overrides(
            texts, field_data)

        self.assertNotIn("tradeArt", field_data)

    def test_missing_trade_art_does_not_raise(self):
        texts, field_data = self.fixtures()
        del field_data["tradeArt"]
        make_rom_manifest.apply_known_nonreproducible_overrides(
            texts, field_data)


class YellowSuperRodParseTest(TestCase):
    """#1074: Yellow's inline Super Rod table (species, level), not Red's."""

    def test_parse_super_rod_yellow_safari_dragonair(self):
        import json
        import tempfile
        from extract import field

        asm = (
            "SuperRodFishingSlots::\n"
            "\tdb SAFARI_ZONE_CENTER, MAGIKARP, 5, MAGIKARP, 10, "
            "DRATINI, 10, DRAGONAIR, 15\n"
            "\tdb SAFARI_ZONE_EAST, MAGIKARP, 5, MAGIKARP, 10, "
            "MAGIKARP, 15, DRATINI, 15\n"
            "\tdb -1 ; end\n"
        )
        with tempfile.TemporaryDirectory() as td:
            wild = Path(td) / "data" / "wild"
            wild.mkdir(parents=True)
            (wild / "super_rod.asm").write_text(asm)
            parsed = field.parse_super_rod_yellow(td)

        self.assertEqual(parsed["SAFARI_ZONE_CENTER"], [
            {"level": 5, "species": "MAGIKARP"},
            {"level": 10, "species": "MAGIKARP"},
            {"level": 10, "species": "DRATINI"},
            {"level": 15, "species": "DRAGONAIR"},
        ])
        self.assertNotIn("DRAGONAIR",
                         [s["species"] for s in parsed["SAFARI_ZONE_EAST"]])

    def test_shipped_yellow_manifest_has_safari_dragonair(self):
        import json
        path = Path(__file__).resolve().parents[1] / "tools" / "rom_manifest_yellow.json"
        data = json.loads(path.read_text(encoding="utf-8"))
        center = data["field"]["superRod"]["SAFARI_ZONE_CENTER"]
        self.assertIn({"level": 15, "species": "DRAGONAIR"}, center)


class Gen2RequiredAssetPreservationTest(TestCase):
    def symbol_fixture(self, directory, version):
        import json
        from rom_data import SymbolTable

        root = Path(__file__).resolve().parents[1]
        manifest = json.loads((root / "tools" / ("rom_manifest_" + version + ".json")).read_text())
        path = Path(directory) / (version + ".sym")
        path.write_text("\n".join(
            f"{bank:02x}:{address:04x} {name}"
            for name, (bank, address) in manifest["symbols"].items()))
        return manifest, path, SymbolTable(str(path))

    def test_gold_generation_keeps_extracted_field_art(self):
        import tempfile
        import make_gold_manifest as gold

        with tempfile.TemporaryDirectory() as directory:
            manifest, _, symbols = self.symbol_fixture(directory, "gold")
            embedded = gold.embedded_symbols(symbols, [])
        for name in ("CutGrassGFX", "JumpShadowGFX"):
            self.assertEqual(embedded.get(name), manifest["symbols"][name])

    def test_crystal_generation_keeps_tileset_palettes_and_field_art(self):
        import tempfile
        import make_gold_manifest as gold
        from crystal_symbol_deltas import crystal_required

        with tempfile.TemporaryDirectory() as directory:
            manifest, _, symbols = self.symbol_fixture(directory, "crystal")
            embedded = gold.embedded_symbols(
                symbols, [], required=crystal_required(gold.REQUIRED_SYMBOLS))
        for name in ("BattleTowerInsidePalette", "HousePalette", "IcePathPalette",
                     "MansionPalette1", "MansionPalette2", "PokeComPalette",
                     "RadioTowerPalette", "CutGrassGFX", "JumpShadowGFX"):
            self.assertEqual(embedded.get(name), manifest["symbols"][name])

    def test_silver_derives_field_art_from_generated_gold(self):
        import tempfile
        import make_gold_manifest as gold
        import make_silver_manifest as silver

        with tempfile.TemporaryDirectory() as directory:
            gold_manifest, _, symbols = self.symbol_fixture(directory, "gold")
            expected, silver_path, _ = self.symbol_fixture(directory, "silver")
            gold_manifest["symbols"] = gold.embedded_symbols(symbols, [])
            derived = silver.derive(gold_manifest, str(silver_path))
        for name in ("CutGrassGFX", "JumpShadowGFX"):
            self.assertEqual(derived["symbols"].get(name), expected["symbols"][name])


if __name__ == "__main__":
    main()
