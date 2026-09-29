# Xbox Dev Mode

Every release ships `gen1recomp-*-xbox-uwp.zip` for Xbox One and Xbox Series
consoles in Developer Mode. It cannot be installed in retail mode.

Extract the archive, then use Xbox Device Portal to install the `.msix` and
the x64 package under `Dependencies`.

## External setup

1. Put your legally obtained ROMs on an external drive. Mod ZIPs can go on the
   same drive.
2. Connect the drive to the Xbox and open Gen1Recomp.
3. Select **Import ROM** or **Import Mod**, then choose the file with the Xbox
   file picker.
4. Repeat the ROM import for each version you want to use.

## Internal setup

1. Create a folder named `baseroms` on your PC and place your legally obtained
   ROMs inside it.
2. ZIP the folder, keeping `baseroms` at the top level of the archive.
3. Launch Gen1Recomp once, then close it.
4. Open Xbox Device Portal and upload the ZIP to
   `Gen1Recomp/LocalState/pokemon-love2d/`.
5. Choose **Yes** when Device Portal asks whether to extract the archive.
6. Open Gen1Recomp. The launcher checks baseroms once at startup. When it
   finds a compatible ROM, that game's tab shows ROM FOUND and an Import
   detected ROM button.

ROMs, generated game data, saves, and mods remain in LocalState and are not
included in the app.

Source builds and package details are in the
[Xbox UWP build notes](../../ports/uwp/BUILD.md).
