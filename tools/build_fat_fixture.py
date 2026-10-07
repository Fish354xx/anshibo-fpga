"""Build sparse FAT32 test sectors; this tool never accesses a physical drive."""
from pathlib import Path
import struct
import argparse

root = Path(__file__).resolve().parents[1]
sectors = {}
volume, reserved, fatsz, total, spc = 2048, 32, 4096, 1048576, 2
data_start = volume + reserved + 2 * fatsz
fat_start = volume + reserved + fatsz  # Active FAT 1; FAT 0 is intentionally empty.


def put32(buffer, offset, value):
    struct.pack_into('<I', buffer, offset, value)


def lba(cluster):
    return data_start + (cluster - 2) * spc


def entry(name, cluster, size=0, directory=False):
    result = bytearray(32)
    result[:11] = name.encode('ascii')
    result[11] = 0x10 if directory else 0x20
    struct.pack_into('<H', result, 20, cluster >> 16)
    struct.pack_into('<H', result, 26, cluster & 65535)
    put32(result, 28, size)
    return result


def bmp(identifier, width=32, height=24, bits=24):
    stride = (width * 3 + 3) & ~3
    pixels = bytearray()
    for y in range(height):
        for x in range(width):
            pixels.extend((x, y, identifier))
        pixels.extend(bytes(stride - width * 3))
    header = bytearray(54)
    header[:2] = b'BM'
    put32(header, 2, 54 + len(pixels))
    put32(header, 10, 54)
    put32(header, 14, 40)
    put32(header, 18, width)
    put32(header, 22, height)
    struct.pack_into('<HHI', header, 26, 1, bits, 0)
    return bytes(header + pixels)


def file_data(data, chain):
    for i, start in enumerate(chain):
        for n in range(spc):
            pos = (i * spc + n) * 512
            sectors[lba(start) + n] = bytearray(data[pos:pos + 512].ljust(512, b'\0'))
        next_cluster = chain[i + 1] if i + 1 < len(chain) else 0x0fffffff
        # Upper reserved bits must not change the 28-bit cluster link.
        fat = sectors.setdefault(fat_start + start // 128, bytearray(512))
        put32(fat, (start % 128) * 4, next_cluster | 0xa0000000)


mbr = bytearray(512)
mbr[450] = 0x0c
put32(mbr, 454, volume)
put32(mbr, 458, total)
mbr[510:512] = b'\x55\xaa'
sectors[0] = mbr
boot = bytearray(512)
boot[0] = 0xeb
struct.pack_into('<H', boot, 11, 512)
boot[13] = spc
struct.pack_into('<H', boot, 14, reserved)
boot[16] = 2
put32(boot, 32, total)
put32(boot, 36, fatsz)
struct.pack_into('<H', boot, 40, 0x81)
put32(boot, 44, 2)
boot[510:512] = b'\x55\xaa'
sectors[volume] = boot
long_names = bytearray(512)
for i in range(16):
    long_names[i * 32] = 0x41
    long_names[i * 32 + 11] = 0x0f
deleted = bytearray(512)
for i in range(16):
    deleted[i * 32] = 0xe5
root_data = bytearray(2048)
root_data[:512], root_data[512:1024] = long_names, deleted
config = b'004.BMP,8\r\n001.BMP,3\n#repeat\n004.BMP,1\n999.BMP,6\n'
root_data[1024:1056] = entry('NORMAL     ', 3, directory=True)
root_data[1056:1088] = entry('ALERT      ', 4, directory=True)
root_data[1088:1120] = entry('PLAYLISTTXT', 120, len(config))
file_data(root_data, [2, 40])
normal_data = bytearray(2048)
normal_data[:512], normal_data[512:1024] = long_names, deleted
files = [(4, [350, 930, 640]), (1, [150, 900, 700]), (2, [270, 820, 510])]
for i, (identifier, chain) in enumerate(files):
    data = bmp(identifier)
    normal_data[1024 + i * 32:1056 + i * 32] = entry(f'{identifier:03d}     BMP', chain[0], len(data))
    file_data(data, chain)
invalid = bmp(3, bits=32)
normal_data[1120:1152] = entry('003     BMP', 650, len(invalid))
file_data(invalid, [650, 951, 741])
file_data(normal_data, [3, 60])
emergency = bmp(9, 1, 1)
alert_data = bytearray(1024)
alert_data[:32] = entry('EVAC    BMP', 500, len(emergency))
file_data(alert_data, [4])
file_data(emergency, [500])
file_data(config, [120])
parser = argparse.ArgumentParser()
parser.add_argument('--variant', choices=['default', 'limits', 'bom', 'superfloppy', 'invalid'], default='default')
args = parser.parse_args()
if args.variant == 'limits':
    directory = bytearray(1024)
    for i, identifier in enumerate(range(20, 0, -1)):
        content = bmp(identifier, 1, 1)
        chain = [1000 + identifier]
        file_data(content, chain)
        directory[i * 32:(i + 1) * 32] = entry(f'{identifier:03d}     BMP', chain[0], len(content))
    file_data(directory, [3])
    root_data[1088] = 0xe5
    file_data(root_data, [2, 40])
elif args.variant == 'bom':
    config = b'\xef\xbb\xbf004.BMP,08\r\n001.BMP,3\n004.BMP,1'
    put32(root_data, 1116, len(config))
    file_data(root_data, [2, 40])
    file_data(config, [120])
elif args.variant == 'invalid':
    struct.pack_into('<H', sectors[volume], 11, 1024)
elif args.variant == 'superfloppy':
    sectors = {address - volume: payload for address, payload in sectors.items() if address >= volume}
if len(sectors) > 128:
    raise ValueError('Fixture exceeds testbench map')
pages = sorted(sectors.items())
lbas = [address for address, _ in pages] + [0xffffffff] * (128 - len(pages))
payload = b''.join(data for _, data in pages) + bytes((128 - len(pages)) * 512)
(root / 'sim/fat_fixture_lbas.hex').write_text('\n'.join(f'{n:08x}' for n in lbas), encoding='ascii')
(root / 'sim/fat_fixture_bytes.hex').write_text('\n'.join(f'{n:02x}' for n in payload), encoding='ascii')
print(f'Variant {args.variant}; built {len(pages)} sparse sectors: fragmented root, NORMAL and BMPs, active FAT 1, playlist and invalid BMP')
