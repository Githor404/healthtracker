"""R344 (a): synthetic Apple Health exports, zipped the ways zip-gate needs.

    python -I make-ah-zip.py OUTDIR            the small three-source set
    python -I make-ah-zip.py OUTDIR --big MB   one zip of at least MB megabytes (the budget)

FIXTURE-SYNTHETIC (CLAUDE.md): every source name, value and time here is made up.
"Sample Apple Watch" and "Sample iPhone" stand for the device names an export
carries (on a real phone those carry their owner's name, which never enters this
repo); "Oura" and "Dexcom G7" are app names.

The zip records are written by hand, not by zipfile, because the gate needs shapes
zipfile will not make on a small file: Zip64 directory records, and a compression
method this app does not read (12). Layout per APPNOTE 6.3.x.
"""
import os
import random
import struct
import sys
import zlib

OFF = '-0400'
TYPES_Q = 'HKQuantityTypeIdentifier'
TYPES_C = 'HKCategoryTypeIdentifier'
WATCH, PHONE, OURA, DEX = 'Sample Apple Watch', 'Sample iPhone', 'Oura', 'Dexcom G7'


def stamp(day, minute, sec=0):
    return '2026-09-%02d %02d:%02d:%02d %s' % (day, minute // 60, minute % 60, sec, OFF)


def rec(typ, src, unit, day, minute, value, end_min=None, sec=0):
    s = stamp(day, minute, sec)
    e = stamp(day, end_min if end_min is not None else minute, sec)
    u = (' unit="%s"' % unit) if unit else ''
    return (' <Record type="%s" sourceName="%s" sourceVersion="1"%s creationDate="%s"'
            ' startDate="%s" endDate="%s" value="%s"/>\n' % (typ, src, u, s, s, e, value))


def head():
    return ('<?xml version="1.0" encoding="UTF-8"?>\n'
            '<!DOCTYPE HealthData [\n<!ELEMENT HealthData (ExportDate,Me,(Record|Workout)*)>\n]>\n'
            '<HealthData locale="en_CA">\n'
            ' <ExportDate value="2026-09-06 10:00:00 %s"/>\n'
            ' <Me HKCharacteristicTypeIdentifierBiologicalSex="HKBiologicalSexNotSet"/>\n' % OFF)


def small_records():
    """The three-source set. Returns the XML body lines."""
    out = []
    G = TYPES_Q + 'BloodGlucose'
    S = TYPES_Q + 'StepCount'
    # Glucose: Dexcom G7, 1-3 Sep, every 5 min = 864 readings. Every 50th carries a
    # MetadataEntry child, as the real file does, so the record spans three lines.
    n = 0
    for day in (1, 2, 3):
        for m in range(0, 1440, 5):
            v = round(5.6 + 1.9 * ((m // 5 + day * 7) % 23) / 23.0, 1)
            line = rec(G, DEX, 'mmol&lt;180.1558800000541&gt;/L', day, m, v)
            if n % 50 == 0:
                line = (line[:-3] + '>\n  <MetadataEntry key="HKMetadataKeyBloodGlucoseMealTime" value="1"/>\n'
                        ' </Record>\n')
            out.append(line)
            n += 1
    # Steps. 1-2 Sep: the Watch has the most; 3 Sep: no Watch, Oura has more than the
    # iPhone; 4-5 Sep: no glucose, so today's rule keeps none of them.
    for day, src, per, mins in ((1, WATCH, 120, range(420, 1320, 15)), (1, OURA, 90, range(420, 1320, 30)),
                                (1, PHONE, 40, range(480, 1200, 60)),
                                (2, WATCH, 110, range(400, 1300, 15)), (2, OURA, 80, range(400, 1300, 30)),
                                (2, PHONE, 30, range(480, 1200, 60)),
                                (3, OURA, 95, range(420, 1320, 20)), (3, PHONE, 50, range(480, 1200, 60)),
                                (4, OURA, 70, range(420, 1320, 30)), (5, PHONE, 60, range(480, 1200, 60))):
        for m in mins:
            out.append(rec(S, src, 'count', day, m, per + (m % 7), end_min=m + 5))
    # Types not imported in this version: counted per type and source, nothing stored.
    for m in range(0, 500):
        out.append(rec(TYPES_Q + 'HeartRate', WATCH, 'count/min', 1 + m // 200, (m * 3) % 1440, 60 + m % 30))
    for m in range(0, 200):
        out.append(rec(TYPES_Q + 'HeartRate', OURA, 'count/min', 2 + m // 100, (m * 5) % 1440, 55 + m % 20))
    for m in range(0, 20):
        out.append(rec(TYPES_Q + 'HeartRateVariabilitySDNN', WATCH, 'ms', 1 + m // 10, 60 * (m % 10), 30 + m))
    for m in range(0, 30):
        out.append(rec(TYPES_Q + 'RespiratoryRate', OURA, 'count/min', 1 + m // 10, 30 * (m % 10), 14 + m % 3))
    for m in range(0, 300):
        out.append(rec(TYPES_Q + 'ActiveEnergyBurned', WATCH, 'kcal', 1 + m // 150, 420 + m % 150, 1.2))
    for m in range(0, 40):
        out.append(rec(TYPES_C + 'SleepAnalysis', OURA, None, 2 + m // 20, 10 * (m % 20), 'HKCategoryValueSleepAnalysisAsleepCore',
                       end_min=10 * (m % 20) + 9))
    # Not <Record>: never counted.
    out.append(' <Workout workoutActivityType="HKWorkoutActivityTypeWalking" duration="30" sourceName="%s"'
               ' startDate="%s" endDate="%s"/>\n' % (WATCH, stamp(1, 600), stamp(1, 630)))
    out.append(' <ActivitySummary dateComponents="2026-09-01" activeEnergyBurned="400"/>\n')
    return out


def small_xml():
    return (head() + ''.join(small_records()) + '</HealthData>\n').encode('utf-8')


# ---- the zip writer ----------------------------------------------------------
DOS_TIME, DOS_DATE = (10 << 11) | (0 << 5), ((2026 - 1980) << 9) | (9 << 5) | 6
FF32 = 0xFFFFFFFF


class Zip:
    def __init__(self, path, zip64=False):
        self.f = open(path, 'wb')
        self.zip64 = zip64
        self.cd = []

    def add(self, name, chunks, method=8, level=6):
        """chunks: an iterable of bytes. method 8 deflates, 0 stores, anything else is
        written as deflate bytes under that method number (the gate refuses it unread)."""
        nb = name.encode('utf-8')
        off = self.f.tell()
        ver = 45 if self.zip64 else 20
        extra_len = 20 if self.zip64 else 0
        self.f.write(b'\0' * (30 + len(nb) + extra_len))     # header, fixed below
        crc, usize, csize = 0, 0, 0
        co = zlib.compressobj(level, zlib.DEFLATED, -15) if method != 0 else None
        for c in chunks:
            crc = zlib.crc32(c, crc)
            usize += len(c)
            out = co.compress(c) if co else c
            csize += len(out)
            self.f.write(out)
        if co:
            out = co.flush()
            csize += len(out)
            self.f.write(out)
        end = self.f.tell()
        self.f.seek(off)
        if self.zip64:
            self.f.write(struct.pack('<IHHHHHIIIHH', 0x04034b50, ver, 0, method, DOS_TIME, DOS_DATE,
                                     crc, FF32, FF32, len(nb), extra_len))
            self.f.write(nb)
            self.f.write(struct.pack('<HHQQ', 1, 16, usize, csize))
        else:
            self.f.write(struct.pack('<IHHHHHIIIHH', 0x04034b50, ver, 0, method, DOS_TIME, DOS_DATE,
                                     crc, csize, usize, len(nb), 0))
            self.f.write(nb)
        self.f.seek(end)
        self.cd.append((nb, method, crc, csize, usize, off))

    def close(self):
        cd_off = self.f.tell()
        for nb, method, crc, csize, usize, off in self.cd:
            if self.zip64:
                ex = struct.pack('<HHQQQ', 1, 24, usize, csize, off)
                self.f.write(struct.pack('<IHHHHHHIIIHHHHHII', 0x02014b50, 45, 45, 0, method, DOS_TIME, DOS_DATE,
                                         crc, FF32, FF32, len(nb), len(ex), 0, 0, 0, 0, FF32))
                self.f.write(nb + ex)
            else:
                self.f.write(struct.pack('<IHHHHHHIIIHHHHHII', 0x02014b50, 20, 20, 0, method, DOS_TIME, DOS_DATE,
                                         crc, csize, usize, len(nb), 0, 0, 0, 0, 0, off))
                self.f.write(nb)
        cd_size = self.f.tell() - cd_off
        n = len(self.cd)
        if self.zip64:
            e64 = self.f.tell()
            self.f.write(struct.pack('<IQHHIIQQQQ', 0x06064b50, 44, 45, 45, 0, 0, n, n, cd_size, cd_off))
            self.f.write(struct.pack('<IIQI', 0x07064b50, 0, e64, 1))
            self.f.write(struct.pack('<IHHHHIIH', 0x06054b50, 0, 0, 0xFFFF, 0xFFFF, FF32, FF32, 0))
        else:
            self.f.write(struct.pack('<IHHHHIIH', 0x06054b50, 0, 0, n, n, cd_size, cd_off, 0))
        self.f.close()


CDA = b'<?xml version="1.0"?>\n<ClinicalDocument/>\n'


def write_small(outdir):
    os.makedirs(outdir, exist_ok=True)
    xml = small_xml()
    with open(os.path.join(outdir, 'export.xml'), 'wb') as f:
        f.write(xml)
    parts = [xml[i:i + 40000] for i in range(0, len(xml), 40000)]
    z = Zip(os.path.join(outdir, 'deflate-folder.zip'))
    z.add('apple_health_export/export_cda.xml', [CDA])
    z.add('apple_health_export/export.xml', parts)
    z.close()
    z = Zip(os.path.join(outdir, 'stored-root.zip'))
    z.add('export.xml', parts, method=0)
    z.close()
    z = Zip(os.path.join(outdir, 'zip64.zip'), zip64=True)
    z.add('apple_health_export/export_cda.xml', [CDA])
    z.add('apple_health_export/export.xml', parts)
    z.close()
    z = Zip(os.path.join(outdir, 'noexport.zip'))
    z.add('apple_health_export/export_cda.xml', [CDA])
    z.close()
    z = Zip(os.path.join(outdir, 'method12.zip'))
    z.add('apple_health_export/export.xml', parts, method=12)
    z.close()
    whole = open(os.path.join(outdir, 'deflate-folder.zip'), 'rb').read()
    with open(os.path.join(outdir, 'truncated.zip'), 'wb') as f:
        f.write(whole[:len(whole) // 2])
    for n in sorted(os.listdir(outdir)):
        print('%-20s %10d' % (n, os.path.getsize(os.path.join(outdir, n))))


def big_chunks(target_bytes, state):
    """The small set's records first (so glucose and steps are present), then bulk
    records IN THE ORDER A REAL EXPORT WRITES THEM: measured on the user's 10 Oct
    export (counts only), 1,141,020 records in 27 runs of one type and 7,530 runs of
    one type and source -- types in long blocks, the source changing every ~150
    records, time running forward within a block. Values random enough that deflate
    does not shrink them to nothing: the budget needs a zip that is big ZIPPED.
    The mix leans on steps (10 %, the real file ~5 %), the type the import parses."""
    yield (head() + ''.join(small_records())).encode('utf-8')
    rnd = random.Random(344)
    srcs = (WATCH, OURA, PHONE)
    mix = (((TYPES_Q + 'ActiveEnergyBurned', 'kcal'), 6), ((TYPES_Q + 'HeartRate', 'count/min'), 2.5),
           ((TYPES_Q + 'StepCount', 'count'), 1), ((TYPES_Q + 'RespiratoryRate', 'count/min'), 0.5))
    BLOCK = 100000          # records per block of one type, before the next type
    k = 0
    while state['csize']() < target_bytes:
        (t, u), w = mix[k % len(mix)]
        k += 1
        n, src, run, ms = int(BLOCK * w), srcs[rnd.randrange(3)], 0, 0
        buf = []
        for i in range(n):
            if run <= 0:
                src, run = srcs[rnd.randrange(3)], rnd.randrange(50, 250)
            run -= 1
            ms += rnd.randrange(20, 400)
            day, mi = ms // 86400, (ms // 60) % 1440
            y, mo, d = 2021 + (day // 300) % 5, 1 + (day // 25) % 12, 1 + day % 25
            s = '%04d-%02d-%02d %02d:%02d:%02d %s' % (y, mo, d, mi // 60, mi % 60, ms % 60, OFF)
            buf.append(' <Record type="%s" sourceName="%s" sourceVersion="%d.%d" unit="%s" creationDate="%s"'
                       ' startDate="%s" endDate="%s" value="%.4f"/>\n'
                       % (t, src, rnd.randrange(20), rnd.randrange(99), u, s, s, s, rnd.random() * 150))
            if len(buf) >= 20000:
                yield ''.join(buf).encode('utf-8')
                buf = []
                if state['csize']() >= target_bytes:
                    break
        if buf:
            yield ''.join(buf).encode('utf-8')
    yield b'</HealthData>\n'


def write_big(outdir, mb):
    os.makedirs(outdir, exist_ok=True)
    path = os.path.join(outdir, 'big-%dmb.zip' % mb)
    z = Zip(path)
    z.add('apple_health_export/export_cda.xml', [CDA])
    state = {'csize': lambda: z.f.tell()}
    z.add('apple_health_export/export.xml', big_chunks(mb * 1048576, state))
    z.close()
    nb, method, crc, csize, usize, off = z.cd[-1]
    print('%s zipped %d text %d' % (path, os.path.getsize(path), usize))


if __name__ == '__main__':
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    if '--big' in sys.argv:
        write_big(sys.argv[1], int(sys.argv[sys.argv.index('--big') + 1]))
    else:
        write_small(sys.argv[1])
