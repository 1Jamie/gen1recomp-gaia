using System.Buffers.Binary;
using System.Text;
using System.Text.RegularExpressions;
using PKHeX.Core;

static byte[] Trim(byte[] data)
{
    int[] chips = [0x20000, 0x10000, 0x8000, 0x2000];
    if (Array.IndexOf(chips, data.Length) >= 0) return data;
    if (data.Length - 16 is 0x20000 or 0x10000) return data[..^16];
    foreach (var size in chips)
    {
        if (size >= data.Length) continue;
        var pad = data.AsSpan(size);
        var v = pad[0];
        if ((v is 0xFF or 0x00) && pad.IndexOfAnyExcept(v) < 0) return data[..size];
    }
    return data;
}

static bool Open(byte[] orig, out SaveFile? save, out byte[] payload, out string route)
{
    payload = orig.ToArray();
    route = "direct";
    var ok = SaveUtil.TryGetSaveFile(payload, out save);
    if (!ok)
    {
        var t = Trim(orig);
        if (t.Length != orig.Length)
        {
            payload = t.ToArray();
            ok = SaveUtil.TryGetSaveFile(payload, out save);
            route = $"trim({orig.Length}->{t.Length})";
        }
    }
    return ok && save != null;
}

static string Diffs(byte[] a, byte[] b, int max = 12)
{
    if (a.Length != b.Length) return $"LEN {a.Length}->{b.Length}";
    var runs = new List<string>();
    int n = 0;
    for (int i = 0; i < a.Length;)
    {
        if (a[i] == b[i]) { i++; continue; }
        int s = i;
        while (i < a.Length && a[i] != b[i]) { n++; i++; }
        runs.Add($"0x{s:X}-0x{i - 1:X}");
    }
    if (n == 0) return "identical";
    var shown = string.Join(",", runs.Take(max)) + (runs.Count > max ? $",...(+{runs.Count - max} runs)" : "");
    return $"{n}B/{runs.Count}runs: {shown}";
}

static IEnumerable<(string where, PKM pk)> AllMons(SaveFile s)
{
    int pc = Math.Clamp(s.PartyCount, 0, 6);
    for (int i = 0; i < pc; i++) yield return ($"party[{i}]", s.GetPartySlotAtIndex(i));
    for (int b = 0; b < s.BoxCount; b++)
        for (int k = 0; k < s.BoxSlotCount; k++)
        {
            var pk = s.GetBoxSlotAtIndex(b, k);
            bool empty = pk is G3PKM g ? g.SpeciesInternal == 0 : pk.Species == 0;
            if (pk is PK1 or PK2 ? pk.Species == 0 : false) empty = true;
            if (!empty) yield return ($"box{b + 1}[{k}]", pk);
        }
}

var okName = new Regex(@"^[A-Za-z0-9 .,'\-!?:;()/&é♂♀×]*$");

static string Slots(SaveFile s)
{
    var sb = new StringBuilder();
    int pc = Math.Clamp(s.PartyCount, 0, 6);
    for (int i = 0; i < pc; i++) sb.Append(Convert.ToHexString(s.GetPartySlotAtIndex(i).Data)).Append('|');
    for (int b = 0; b < s.BoxCount; b++) for (int k = 0; k < s.BoxSlotCount; k++) sb.Append(Convert.ToHexString(s.GetBoxSlotAtIndex(b, k).Data)).Append('|');
    return sb.ToString();
}

static string G1BoxChecksums(byte[] d)
{
    if (d.Length < 0x8000) return "n/a";
    var bad = new List<string>();
    for (int bank = 0; bank < 2; bank++)
    {
        int b0 = 0x4000 + bank * 0x2000;
        byte all = 0;
        for (int i = 0; i < 0x1A4C; i++) all += d[b0 + i];
        all = (byte)~all;
        if (all != d[b0 + 0x1A4C]) bad.Add($"bank{bank + 2}all(stored {d[b0 + 0x1A4C]:X2} calc {all:X2})");
        for (int bx = 0; bx < 6; bx++)
        {
            byte c = 0;
            for (int i = 0; i < 0x462; i++) c += d[b0 + bx * 0x462 + i];
            c = (byte)~c;
            if (c != d[b0 + 0x1A4D + bx]) bad.Add($"bank{bank + 2}box{bx}(stored {d[b0 + 0x1A4D + bx]:X2} calc {c:X2})");
        }
    }
    return bad.Count == 0 ? "ok" : "BAD:" + string.Join(";", bad);
}

Console.WriteLine("file\tsize\troute\ttype\tversion\tPKHeXchk\tchkInfo\textraChk\tparty\tboxed\tmonAnomalies\texception\tunchangedWriteDiff\tunchangedWriteSizeSame\tnoopSetSlotsWriteDiff\tnoopSizeSame\tpkforgeReopen\tpkforgeSlotDiff\tpkforgeG3Corrupting\tpkforgeG3Foreign\tpkforgeG3ChkMajority\tpkforgeEditionHint\tnotes");
foreach (var path in args)
{
    var cols = new string[23];
    cols[0] = path;
    try
    {
        var orig = File.ReadAllBytes(path);
        cols[1] = orig.Length.ToString();
        if (!Open(orig, out var save, out var pristine, out var route) || save == null)
        {
            cols[2] = "-"; cols[3] = "NOT RECOGNIZED"; cols[11] = "InvalidDataException: The selected bytes are not a recognized save file.";
            Console.WriteLine(string.Join("\t", cols.Select(c => c ?? "")));
            continue;
        }
        pristine = pristine.ToArray();
        cols[2] = route;
        cols[3] = save.GetType().Name;
        cols[4] = save.Version.ToString();
        cols[5] = save.ChecksumsValid.ToString();
        cols[6] = save.ChecksumInfo.Replace("\n", " / ").Replace("\r", "");
        if (save is SAV1) cols[7] = "G1boxbanks=" + G1BoxChecksums(pristine);
        else if (save is SAV2 s2c)
        {
            var o = s2c.Version == GameVersion.C ? 0x1F0D : 0x7E6D;
            cols[7] = s2c.Version == GameVersion.C ? "crystal:see chkInfo" : "GS 0x7E6D: see chkInfo";
        }
        int party = save.PartyCount;
        cols[8] = party.ToString();
        var anomalies = new List<string>();
        int total = 0;
        foreach (var (where, pk) in AllMons(save))
        {
            if (!where.StartsWith("party")) total++;
            var issues = new List<string>();
            var lv = pk.CurrentLevel;
            if (pk.Species < 1 || pk.Species > save.MaxSpeciesID) issues.Add($"species={pk.Species}");
            if (lv < 1 || lv > 100) issues.Add($"lvl={lv}");
            if (where.StartsWith("party") && pk.Stat_Level != lv) issues.Add($"lvlbyte={pk.Stat_Level}!=exp{lv}");
            if (!okName.IsMatch(pk.Nickname) || pk.Nickname.Length == 0) issues.Add($"nick='{pk.Nickname}'");
            if (!okName.IsMatch(pk.OriginalTrainerName) || pk.OriginalTrainerName.Length == 0) issues.Add($"OT='{pk.OriginalTrainerName}'");
            if (pk is G3PKM g3 && !pk.ChecksumValid) issues.Add("monChkBAD");
            if (pk is PK3 p3 && !p3.IsEgg && (p3.Data[0x13] & 2) == 0) issues.Add("noHasSpecies");
            if (issues.Count > 0) anomalies.Add($"{where}:{string.Join(",", issues)}");
        }
        cols[9] = total.ToString();
        cols[10] = anomalies.Count == 0 ? "none" : $"{anomalies.Count} mons; " + string.Join(" ; ", anomalies.Take(6)) + (anomalies.Count > 6 ? " ..." : "");
        cols[11] = "";
        var before = Slots(save);
        if (save is SAV3 s3) cols[22] = $"jp={s3.Japanese}";
        if (save is SAV1 s1) cols[22] = $"jp={s1.Japanese},boxInit={s1.BoxesInitialized},curBox={s1.CurrentBox}";
        if (save is SAV2 s2x) cols[22] = $"jp={s2x.Japanese},kor={s2x.Korean}";
        byte[] written;
        try { written = save.Write().ToArray(); }
        catch (Exception e) { cols[11] = $"WRITE EXC {e.GetType().Name}: {e.Message}"; Console.WriteLine(string.Join("\t", cols.Select(c => c ?? ""))); continue; }
        cols[12] = Diffs(pristine, written);
        if (Environment.GetEnvironmentVariable("DUMP") is { } dd) { Directory.CreateDirectory(dd); File.WriteAllBytes(Path.Combine(dd, Path.GetFileName(path) + ".written"), written); }
        cols[13] = (written.Length == pristine.Length).ToString();
        try
        {
            Open(orig, out var s2, out var p2, out _);
            var sv = s2!;
            if (sv.PartyCount > 0) sv.SetPartySlotAtIndex(sv.GetPartySlotAtIndex(0), 0, EntityImportSettings.None);
            for (int b = 0; b < sv.BoxCount; b++) for (int k = 0; k < sv.BoxSlotCount; k++)
                {
                    var pk = sv.GetBoxSlotAtIndex(b, k);
                    bool e = pk is G3PKM gg ? gg.SpeciesInternal == 0 : pk.Species == 0;
                    if (!e) { sv.SetBoxSlotAtIndex(pk, b, k, EntityImportSettings.None); goto done; }
                }
            done:
            var w2 = sv.Write().ToArray();
            cols[14] = Diffs(pristine, w2);
            cols[15] = (w2.Length == pristine.Length).ToString();
        }
        catch (Exception e) { cols[14] = $"EXC {e.GetType().Name}: {e.Message}"; }
        try
        {
            var okr = Open(written, out var s3r, out _, out _);
            cols[16] = okr.ToString();
            if (okr) cols[17] = Slots(s3r!) == before ? "no slot change" : "SLOTS CHANGED";
        }
        catch (Exception e) { cols[16] = $"EXC {e.Message}"; }
        if (save is SAV3 g3s)
        {
            cols[18] = written.AsSpan().SequenceEqual(pristine) ? "no (untouched Write reproduces file: writes allowed)" : "YES CorruptingLayout: untouched Write != file (writes refused)";
            int foreign = 0, readable = 0, party6 = 0, partyBad = 0, boxN = 0, boxBad = 0;
            var editions = new HashSet<GameVersion>();
            for (int i = 0; i < Math.Clamp(g3s.PartyCount, 0, 6); i++)
            {
                var pk = (G3PKM)g3s.GetPartySlotAtIndex(i);
                if (pk.Data.ToArray().Any(b => b != 0)) { party6++; if (!pk.ChecksumValid) partyBad++; }
                if (pk.ChecksumValid && pk.SpeciesInternal != 0) { readable++; var r = pk.SpeciesInternal; if (!(r is >= 1 and <= 251 or >= 277 and <= 412)) foreign++; }
            }
            for (int b = 0; b < g3s.BoxCount; b++) for (int k = 0; k < g3s.BoxSlotCount; k++)
                {
                    var pk = (G3PKM)g3s.GetBoxSlotAtIndex(b, k);
                    bool empty = pk.Data.ToArray().All(x => x == 0) || pk.SpeciesInternal == 0 && pk.ChecksumValid;
                    if (!empty) { boxN++; if (!pk.ChecksumValid) boxBad++; }
                    if (pk.ChecksumValid && pk.SpeciesInternal != 0) { readable++; var r = pk.SpeciesInternal; if (!(r is >= 1 and <= 251 or >= 277 and <= 412)) foreign++; }
                }
            cols[19] = foreign == 0 ? "no" : $"YES SuspectedHack: {foreign} of {readable} foreign species ids";
            bool maj = (party6 > 0 && partyBad * 2 > party6) || (boxN >= 3 && boxBad * 2 > boxN);
            cols[20] = maj ? $"YES CorruptingLayout: partyBad {partyBad}/{party6} boxBad {boxBad}/{boxN}" : $"no (partyBad {partyBad}/{party6}, boxBad {boxBad}/{boxN})";
            if (save is SAV3FRLG or SAV3RS)
            {
                var eds = new HashSet<GameVersion>();
                var all = AllMons(save);
                var ed = save is SAV3FRLG ? new[] { GameVersion.FR, GameVersion.LG } : new[] { GameVersion.R, GameVersion.S };
                foreach (var (_, pk) in all)
                    if (pk.Species != 0 && pk.ChecksumValid && pk.ID32 == save.ID32 && pk.OriginalTrainerName == save.OT && Array.IndexOf(ed, pk.Version) >= 0) eds.Add(pk.Version);
                cols[21] = eds.Count == 1 ? $"{eds.First()}" : $"none/ambiguous ({eds.Count}); stays {save.Version}";
            }
        }
    }
    catch (Exception e)
    {
        cols[11] = $"{e.GetType().FullName}: {e.Message} @ {e.StackTrace?.Split('\n').FirstOrDefault()?.Trim()}";
    }
    Console.WriteLine(string.Join("\t", cols.Select(c => c ?? "")));
}
return 0;
