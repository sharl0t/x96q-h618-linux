#!/usr/bin/env python3
"""Makes the board-specific SPL from the stock one of the Armbian X96Q v1.3 image (no prebuilt loader is shipped).

    python3 -I patch-spl.py <armbian-image.img | stock-spl.bin> <out-spl.bin>

Input: either the raw image (the SPL is the 40 KiB at offset 8 KiB) or the 40960-byte SPL itself.
Three changes, then the eGON checksum is recomputed:
  1. DRAM clock 600 -> 720 MHz (word at 0x7b88: 0x258 -> 0x2d0), as the Android loader of this board runs it.
  2. dram tpr6 0x3300c080 -> 0x2fa88080 (word at 0x7ba8), the value of the Android profile of this board.
  3. The size trim of the Armbian patch (size*3/4, 2 GiB -> 1.5 GiB) becomes size*7/8 (-> 1792 MiB). This box has
     768 MiB at 0x40000000 and 768 MiB at 0x80000000; 0xA0000000-0xAFFFFFFF is real memory, the hole at 0x70000000
     is excluded by the device tree. Code at 0x1a8c: `add x19,x19,x19,lsl#1` -> `sub x19,x19,x19,lsr#3`,
     at 0x1a94: `lsr x19,x19,#2` -> `nop`.
"""
import struct, sys

SPL_OFFSET, SPL_SIZE = 8 * 1024, 40960
STAMP = 0x5F0A6C39          # value of the checksum field while the sum is computed


def checksum(b):
    b = bytearray(b)
    b[12:16] = struct.pack('<I', STAMP)
    return sum(struct.unpack('<%dI' % (len(b) // 4), bytes(b))) & 0xFFFFFFFF


def word(b, off):
    return struct.unpack('<I', b[off:off + 4])[0]


def main(src, dst):
    raw = open(src, 'rb').read(SPL_OFFSET + SPL_SIZE)
    spl = bytearray(raw[SPL_OFFSET:SPL_OFFSET + SPL_SIZE] if len(raw) > SPL_SIZE else raw)
    assert len(spl) == SPL_SIZE and spl[4:12] == b'eGON.BT0', 'not an Allwinner SPL'
    assert checksum(spl) == word(spl, 12), 'the input SPL checksum is wrong'
    expect = {0x7b88: (0x258, 0x2d0), 0x7ba8: (0x3300c080, 0x2fa88080),
              0x1a8c: (0x8b130673, 0xcb530e73), 0x1a94: (0xd342fe73, 0xd503201f)}
    for off, (old, new) in expect.items():
        assert word(spl, off) == old, 'unexpected word at 0x%x: this is not the Armbian X96Q v1.3 SPL' % off
        spl[off:off + 4] = struct.pack('<I', new)
    spl[12:16] = struct.pack('<I', checksum(spl))
    open(dst, 'wb').write(spl)
    print('ok', dst)


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(*sys.argv[1:])
