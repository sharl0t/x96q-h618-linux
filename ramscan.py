#!/usr/bin/env python3
"""
Physical RAM map: allocates N MiB of anonymous memory, finds the PHYSICAL address of every page via
/proc/self/pagemap, writes + verifies several patterns, and reports which physical ranges return wrong data.
Run as root on the box (stop the desktop first so that more RAM is free):
    sudo systemctl stop lightdm
    sudo python3 ramscan.py 1000
    sudo systemctl start lightdm
Writes a summary to ramscan.json (readable by everyone).
"""
import ctypes, json, mmap, os, struct, sys, time

PAGE = 4096
MASK = (1 << 64) - 1
MIB = int(sys.argv[1]) if len(sys.argv) > 1 else 900
N = MIB * 256
if os.geteuid() != 0:
    sys.exit('run as root (pagemap needs it)')

t0 = time.time()
m = mmap.mmap(-1, N * PAGE, flags=mmap.MAP_PRIVATE | mmap.MAP_ANONYMOUS, prot=mmap.PROT_READ | mmap.PROT_WRITE)
mv = memoryview(m)
for i in range(N):                       # fault every page in
    m[i * PAGE] = 1
libc = ctypes.CDLL('libc.so.6', use_errno=True)
addr = ctypes.addressof(ctypes.c_char.from_buffer(m))
if libc.mlock(ctypes.c_void_p(addr), ctypes.c_size_t(N * PAGE)) != 0:
    print('warning: mlock failed (errno %d), pages may move' % ctypes.get_errno())

with open('/proc/self/pagemap', 'rb') as f:
    f.seek((addr // PAGE) * 8)
    raw = f.read(N * 8)
ents = struct.unpack('<%dQ' % N, raw)
pfns = []
for e in ents:
    if not (e >> 63) & 1:
        sys.exit('page not present in pagemap')
    pfns.append(e & ((1 << 55) - 1))
if not any(pfns):
    sys.exit('PFNs are zero (kernel hides them?)')
lo, hi = min(pfns) * PAGE, (max(pfns) + 1) * PAGE
print('got %d MiB; physical span 0x%x - 0x%x (%.0f MiB); %.1fs' % (MIB, lo, hi, (hi - lo) / 2**20, time.time() - t0))

def patterns(k, pfn):
    if k == 0:
        w = (pfn * 0x9E3779B97F4A7C15 + 0x1234567) & MASK
    elif k == 1:
        w = (~((pfn * 0x9E3779B97F4A7C15 + 0x1234567) & MASK)) & MASK
    elif k == 2:
        w = 0x5555555555555555
    else:
        w = 0xAAAAAAAAAAAAAAAA
    return struct.pack('<Q', w) * 512

bad = {}                                  # pfn -> number of failing passes
for k in range(4):
    t = time.time()
    for i in range(N):
        mv[i * PAGE:(i + 1) * PAGE] = patterns(k, pfns[i])
    nbad = 0
    for i in range(N):
        if mv[i * PAGE:(i + 1) * PAGE] != patterns(k, pfns[i]):
            bad[pfns[i]] = bad.get(pfns[i], 0) + 1
            nbad += 1
    print('pass %d: %d bad pages (%.1fs)' % (k, nbad, time.time() - t))
    sys.stdout.flush()

# ---- summary per 32 MiB physical window ---------------------------------------------------------------
WIN = 32 * 2**20
tested, wbad = {}, {}
for p in pfns:
    w = (p * PAGE) // WIN
    tested[w] = tested.get(w, 0) + 1
for p in bad:
    w = (p * PAGE) // WIN
    wbad[w] = wbad.get(w, 0) + 1
print('\nphysical window (32 MiB)   tested pages   bad pages')
for w in sorted(tested):
    print('0x%08x-0x%08x   %6d   %6d   %s' % (w * WIN, (w + 1) * WIN - 1, tested[w], wbad.get(w, 0),
                                              'BAD' if wbad.get(w, 0) else 'ok'))
out = {'mib': MIB, 'span': [lo, hi], 'tested': {hex(w * WIN): c for w, c in tested.items()},
       'bad': {hex(w * WIN): c for w, c in wbad.items()},
       'bad_pfns_sample': sorted(bad)[:200]}
with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'ramscan.json'), 'w') as f:
    json.dump(out, f, indent=1)
os.chmod(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'ramscan.json'), 0o644)
print('total bad pages: %d of %d (%.1f%%)' % (len(bad), N, 100.0 * len(bad) / N))
