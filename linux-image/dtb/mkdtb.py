#!/usr/bin/env python3
"""Adds no-map reserved RAM regions to a flattened device tree. Pure Python, no libfdt/dtc needed.

    python3 -I mkdtb.py in.dtb out.dtb 0x70000000:0x10000000 [base:size ...]

Each region becomes /reserved-memory/badram@<base> { reg = <0 base 0 size>; no-map; }.
On the X96Q / H618 box the range 0x70000000-0x7fffffff has no memory behind it, so Linux must not use it.
The input is the board DTB of the Armbian image, /boot/dtb/allwinner/sun50i-h313-x96q-lpddr3.dtb."""
import struct, sys

MAGIC, BEGIN, END_NODE, PROP, NOP, END = 0xd00dfeed, 1, 2, 3, 4, 9


def u32(b, o):
    return struct.unpack('>I', b[o:o + 4])[0]


def pad4(n):
    return (n + 3) & ~3


def add_regions(dtb, regions):
    assert u32(dtb, 0) == MAGIC, 'not a device tree blob'
    total, off_st, off_str, off_rsv = u32(dtb, 4), u32(dtb, 8), u32(dtb, 12), u32(dtb, 16)
    sz_str, sz_st = u32(dtb, 32), u32(dtb, 36)
    assert off_rsv < off_st < off_str and off_str + sz_str <= total, 'unexpected layout'
    head, struct_blk = bytearray(dtb[:off_st]), bytes(dtb[off_st:off_st + sz_st])
    strings = bytearray(dtb[off_str:off_str + sz_str])

    # walk the structure block; the new nodes go right after the properties of /reserved-memory (where libfdt puts them)
    pos, path, inside, insert_at = 0, [], None, None
    while pos < len(struct_blk) and insert_at is None:
        tok = u32(struct_blk, pos)
        if tok == BEGIN:
            end = struct_blk.index(b'\0', pos + 4)
            name = struct_blk[pos + 4:end].decode()
            if inside is None and path + [name] == ['', 'reserved-memory']:
                inside = len(path) + 1
            elif inside is not None and len(path) == inside:
                insert_at = pos                              # first child node
            path.append(name)
            pos += 4 + pad4(end - (pos + 4) + 1)
        elif tok == END_NODE:
            if inside is not None and len(path) == inside:
                insert_at = pos                              # no children: end of the node
            path.pop()
            pos += 4
        elif tok == PROP:
            pos += 12 + pad4(u32(struct_blk, pos + 4))
        elif tok == NOP:
            pos += 4
        else:
            break
    assert insert_at is not None, '/reserved-memory not found'

    def name_off(name):
        key = name.encode() + b'\0'
        i = bytes(strings).find(key)          # libfdt also reuses an existing string, even as a suffix of another
        if i < 0:
            i = len(strings)
            strings.extend(key)
        return i

    new = bytearray()
    for base, size in regions:
        node = ('badram@%x' % base).encode() + b'\0'
        new += struct.pack('>I', BEGIN) + node + b'\0' * (pad4(len(node)) - len(node))
        new += struct.pack('>III', PROP, 0, name_off('no-map'))                # libfdt puts the newest property first
        new += struct.pack('>III', PROP, 16, name_off('reg')) + struct.pack('>4I', base >> 32, base & 0xffffffff,
                                                                            size >> 32, size & 0xffffffff)
        new += struct.pack('>I', END_NODE)
    struct_blk = struct_blk[:insert_at] + bytes(new) + struct_blk[insert_at:]
    off_str2 = off_st + len(struct_blk)
    head[4:8] = struct.pack('>I', off_str2 + len(strings))
    head[12:16] = struct.pack('>I', off_str2)
    head[32:36] = struct.pack('>I', len(strings))
    head[36:40] = struct.pack('>I', len(struct_blk))
    return bytes(head) + struct_blk + bytes(strings)


if __name__ == '__main__':
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    regs = [tuple(int(x, 0) for x in a.split(':')) for a in sys.argv[3:]]
    out = add_regions(open(sys.argv[1], 'rb').read(), regs)
    open(sys.argv[2], 'wb').write(out)
    print('wrote', sys.argv[2], len(out), 'bytes')
