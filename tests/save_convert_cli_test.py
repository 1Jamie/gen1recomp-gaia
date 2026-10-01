import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which("luajit"), "requires LuaJIT")
class SaveConvertCliTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="save-convert-cli-")
        cls.path = Path(cls.temp.name)
        generated = cls.path / "cache" / "data" / "generated"
        generated.mkdir(parents=True)
        cls.env = dict(os.environ, SAVE_CONVERT_CLI_TEST_DIR=str(cls.path))
        for version in ("gold", "silver", "crystal"):
            cls.env[version.upper() + "_CACHE"] = str(cls.path / "cache")
        code = '''
love = require("tests.love_stub")
local G2 = require("tests.fixtures.save.gen2_build")
local K = require("tests.save_compat._codec")
local Serializer = require("src.core.SaveSerializer")
local root = os.getenv("SAVE_CONVERT_CLI_TEST_DIR")
local function write(path, bytes)
  local f = assert(io.open(root .. "/" .. path, "wb"))
  f:write(bytes)
  f:close()
end
local data = { items = K.gen2Data.items, maps = K.gen2Data.maps,
  pokemon = { CYNDAQUIL = { index = 155, dex = 155, name = "CYNDAQUIL", genderRatio = 31 } },
  moves = { TACKLE = { index = 33, pp = 35 }, GROWL = { index = 43, pp = 40 } } }
for name, rows in pairs(data) do
  write("cache/data/generated/" .. name .. ".lua", Serializer.encode(rows))
end
for _, version in ipairs({ "gold", "silver", "crystal" }) do
  write(version .. ".sav", G2.build({ version = version, footer = string.rep("\\0", 18) }))
  write(version .. "-warning.sav", G2.build({ version = version, lowByteZero = true }))
end
for _, case in ipairs(G2.cases()) do
  if case.id == "g2.crystal.corrupt_primary" then write("backup.sav", case.bytes) end
end
'''
        subprocess.run(["luajit", "-e", code], cwd=ROOT, env=cls.env, check=True,
                       capture_output=True, text=True)

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def convert(self, operation, source, target, version):
        result = subprocess.run(["luajit", "tools/save_convert/convert.lua", operation,
                                 str(self.path / source), str(self.path / target), version],
                                cwd=ROOT, env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def test_rtc_footer_survives_cli_roundtrip(self):
        for version in ("gold", "silver", "crystal"):
            with self.subTest(version=version):
                self.convert("import", version + ".sav", version + ".lua", version)
                self.convert("export", version + ".lua", version + "-out.sav", version)
                self.assertEqual((self.path / (version + "-out.sav")).read_bytes(),
                                 (self.path / (version + ".sav")).read_bytes())

    def test_backup_import_note_is_printed(self):
        result = self.convert("import", "backup.sav", "backup.lua", "crystal")
        self.assertIn("backup copy", result.stderr)

    def test_accepted_reader_warning_is_printed(self):
        for version in ("gold", "silver", "crystal"):
            with self.subTest(version=version):
                source = version + "-warning.sav"
                slot = version + "-warning.lua"
                target = version + "-warning-out.sav"
                self.convert("import", source, slot, version)
                result = self.convert("export", slot, target, version)
                self.assertIn("gen2.openhomeChecksum", result.stderr)
                self.assertEqual((self.path / target).read_bytes(), (self.path / source).read_bytes())


if __name__ == "__main__":
    unittest.main()
