import fs from 'node:fs'
import path from 'node:path'
import { G1SAV } from '@openhome-core/save/G1SAV'
import { G1SAVJP } from '@openhome-core/save/G1SAVJP'
import { G2SAV } from '@openhome-core/save/G2SAV'
import { G2SAVJP } from '@openhome-core/save/G2SAVJP'
import { G3SAV } from '@openhome-core/save/G3SAV'
import { Gen1G1RSave, Gen2G1RSave, Gen3G1RSave } from '@openhome-core/save/g1r/G1RSave'
import { buildSaveFile } from '@openhome-core/save/util/load'
import { PK3 } from '@openhome-core/pkm'
import { OriginGames } from '@pkm-rs/pkg'

const LIST = process.env.SAV_LIST ?? ''
const OUTF = process.env.OUT_JSONL ?? ''
const ORDER: any[] = [Gen1G1RSave, Gen2G1RSave, Gen3G1RSave, G1SAV, G1SAVJP, G2SAV, G2SAVJP, G3SAV]

function pathData(p: string) {
  const ext = path.extname(p)
  return { raw: p, dir: path.dirname(p), name: path.basename(p, ext), ext: ext.slice(1), separator: '/' }
}
function total(save: any): number {
  let n = 0
  for (const b of save.boxes) { if (!b) continue; for (const m of b.boxSlots) if (m) n++ }
  return n
}
function boxCounts(save: any): number[] {
  return save.boxes.map((b: any) => (b ? b.boxSlots.filter((m: any) => m).length : -1))
}
function fp(m: any): string {
  const g = (f: () => any) => { try { return f() } catch (e) { return 'E' } }
  return [g(() => m.nationalDex), g(() => m.nickname), g(() => m.trainerName), g(() => m.getLevel?.() ?? m.level), g(() => m.exp), g(() => m.trainerID)].join('|')
}
function fps(save: any): string[][] {
  return save.boxes.map((b: any) => (b ? b.boxSlots.filter((m: any) => m).map(fp).sort() : []))
}
function fpDiff(a: string[][], b: string[][]): string[] {
  const out: string[] = []
  for (let i = 0; i < a.length; i++) {
    const A = a[i] ?? [], B = b[i] ?? []
    const bs = [...B]
    for (const x of A) { const k = bs.indexOf(x); if (k >= 0) bs.splice(k, 1); else out.push(`box${i + 1} lost ${x}`) }
    for (const x of bs) out.push(`box${i + 1} new ${x}`)
  }
  return out
}
function diff(a: Uint8Array, b: Uint8Array) {
  const n = Math.min(a.length, b.length)
  let c = 0
  const first: string[] = []
  for (let i = 0; i < n; i++) if (a[i] !== b[i]) { c++; if (first.length < 8) first.push(`0x${i.toString(16)}:${a[i].toString(16)}->${b[i].toString(16)}`) }
  return { len: a.length === b.length ? 'same' : `${a.length}vs${b.length}`, diffBytes: c + Math.abs(a.length - b.length), first }
}

function capture<T>(fn: () => T): { v?: T; err?: string; logs: string[] } {
  const logs: string[] = []
  const orig = console.error
  console.error = (...a: any[]) => { logs.push(a.map(String).join(' ')) }
  try {
    const v = fn()
    return { v, logs }
  } catch (e) {
    return { err: String(e), logs }
  } finally {
    console.error = orig
  }
}

function rawStats(bytes: Uint8Array, cls: string) {
  const r: any = {}
  if (cls === 'G1SAV') {
    let occ = 0
    for (let b = 0; b < 12; b++) {
      const off = b < 6 ? 0x4000 + b * 0x462 : 0x6000 + (b - 6) * 0x462
      for (let s = 0; s < 20; s++) if (bytes[off + 0x16 + s * 0x21]) occ++
    }
    r.rawOccupied = occ
    r.party = bytes[0x2f2c]
  }
  return r
}

function g3Slots(save: any) {
  const errs: string[] = []
  let occ = 0
  const d = save.primarySave.pcDataContiguous
  for (let i = 0; i < 420; i++) {
    const buf = d.slice(4 + i * 80, 4 + (i + 1) * 80)
    const species = buf[0x20] | (buf[0x21] << 8)
    if (species) occ++
    try { PK3.fromSlotBytes(buf.buffer) } catch (e) { errs.push(`box${Math.floor(i / 30) + 1}/slot${(i % 30) + 1}: ${String(e)}`) }
  }
  return { rawOccupied: occ, slotErrors: errs }
}

function analyze(file: string) {
  const pristine = new Uint8Array(fs.readFileSync(file))
  const rec: any = { file: path.basename(file), size: pristine.length }
  const bytes = new Uint8Array(pristine)
  const per: string[] = []
  const passing: any[] = []
  for (const cls of ORDER) {
    try { const ok = cls.fileIsSave(new Uint8Array(pristine)); per.push(`${cls.name}=${ok}`); if (ok) passing.push(cls) }
    catch (e) { per.push(`${cls.name}=THROWS(${String(e)})`) }
  }
  const top = Math.max(0, ...passing.map((c) => c.detectionPriority ?? 0))
  const matches = passing.filter((c) => (c.detectionPriority ?? 0) === top)
  rec.perClass = per.join(' ')
  rec.matches = matches.map((m) => m.name)
  let cls: any = matches.length === 1 ? matches[0] : undefined
  rec.detected = cls ? cls.name : matches.length > 1 ? 'AMBIGUOUS' : 'UNRECOGNIZED'
  const forceName = process.env.FORCE_CLASS
  let forced = false
  if (!cls) {
    const guess = forceName ?? (pristine.length >= 0x20000 ? 'G3SAV' : 'G2SAV')
    cls = ORDER.find((c) => c.name === guess)
    forced = true
    rec.forcedClass = guess
  }
  rec.usedClass = cls.name
  rec.forced = forced
  const b1 = new Uint8Array(pristine)
  const built: any = capture(() => buildSaveFile(pathData(file), b1, cls))
  if (built.err) { rec.buildError = built.err; return rec }
  const res: any = built.v
  if (res.data === undefined) { rec.buildError = String(res.error); rec.buildLogs = built.logs; return rec }
  const save: any = res.data
  rec.buildLogs = built.logs
  rec.origin = OriginGames.gameNameFull(save.origin)
  rec.ot = save.name
  rec.tid = save.tid
  rec.sid = save.sid
  rec.invalid = save.invalid
  rec.currentPCBox = save.currentPCBox
  rec.boxCount = save.boxes.length
  rec.boxCounts = boxCounts(save)
  rec.loaded = total(save)
  Object.assign(rec, rawStats(pristine, cls.name))
  try { if (save.root) { rec.partyLua = save.root.get('party')?.size; rec.moneyOH = save.money } } catch (e) { rec.partyLua = String(e) }
  if (cls.name === 'G3SAV') { try { Object.assign(rec, g3Slots(save)) } catch (e) { rec.g3slotsErr = String(e) }
    try { const p = save.primarySave; rec.gen3 = `gameCode=${p.gameCode} key=0x${p.securityKey.toString(16)} copy=0x${(p.securityKeyCopy ?? 0).toString(16)} sig=0x${p.signature.toString(16)} idx=${p.saveIndex} off=0x${save.primarySaveOffset.toString(16)} backup=${!!save.backupSave}` } catch {} }
  const w1 = capture(() => (save.prepareWriter() as any).bytes as Uint8Array)
  if (w1.err) rec.writeNoEditErr = w1.err
  else {
    rec.writeNoEdit = diff(pristine, w1.v!)
    const reb = capture(() => buildSaveFile(pathData(file), new Uint8Array(w1.v!), cls))
    const rr: any = reb.v
    rec.reloadNoEdit = reb.err ?? (rr.data === undefined ? `ERR ${rr.error}` : total(rr.data))
  }
  const built2: any = capture(() => buildSaveFile(pathData(file), new Uint8Array(pristine), cls))
  const save2: any = built2.v?.data
  if (save2) {
    const ub: any[] = []
    for (let b = 0; b < (cls.name === 'G1SAV' ? 12 : save2.boxes.length); b++) { if (!save2.boxes[b]) continue; for (let s = 0; s < save2.boxes[b].boxSlots.length; s++) ub.push({ box: b, boxSlot: s }) }
    save2.updatedBoxSlots = ub
    const w2 = capture(() => (save2.prepareWriter() as any).bytes as Uint8Array)
    rec.touchAllLogs = w2.logs.slice(0, 5)
    if (w2.err) rec.writeTouchErr = w2.err
    else {
      rec.writeTouch = diff(pristine, w2.v!)
      const reb = capture(() => buildSaveFile(pathData(file), new Uint8Array(w2.v!), cls))
      const rr: any = reb.v
      rec.reloadTouch = reb.err ?? (rr.data === undefined ? `ERR ${rr.error}` : total(rr.data))
      if (rr?.data) { rec.reloadTouchCounts = boxCounts(rr.data).join(','); rec.touchFieldDiffs = fpDiff(fps(save2), fps(rr.data)).slice(0, 400) }
    }
  }
  return rec
}

test('batch', () => {
  const files = fs.readFileSync(LIST, 'utf8').split('\n').filter(Boolean)
  const out: string[] = []
  for (const f of files) {
    let rec: any
    try { rec = analyze(f) } catch (e) { rec = { file: path.basename(f), fatal: String(e) } }
    out.push(JSON.stringify(rec))
  }
  fs.writeFileSync(OUTF, out.join('\n') + '\n')
})
