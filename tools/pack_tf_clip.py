"""Prepare a sector-aligned BMP frame container for the planned TF player.

This tool prepares assets only. Current firmware does not play AVTF files.
"""
import argparse
import io
import struct
from pathlib import Path
from PIL import Image


def pack_frames(paths, output, width=160, height=120, fps=8):
    if not paths or not 1 <= fps <= 10:
        raise ValueError('Provide frames and an integer frame rate from 1 to 10')
    if (width, height) not in ((160, 120), (320, 240)):
        raise ValueError('Supported frame sizes: 160x120 or 320x240')
    bmp_length = 54 + ((width * 3 + 3) // 4 * 4) * height
    frame_sectors = (bmp_length + 511) // 512
    header = struct.pack('<4sHHHHIII', b'AVTF', 1, width, height, fps,
                         len(paths), frame_sectors, bmp_length)
    output = Path(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open('wb') as stream:
        stream.write(header.ljust(512, b'\0'))
        for path in paths:
            with Image.open(path) as image:
                image = image.convert('RGB').resize((width, height), Image.Resampling.LANCZOS)
                buffer = io.BytesIO()
                image.save(buffer, format='BMP')
            data = buffer.getvalue()
            if len(data) != bmp_length or data[:2] != b'BM':
                raise ValueError('Unexpected BMP encoder output')
            stream.write(data.ljust(frame_sectors * 512, b'\0'))
    return frame_sectors


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('frames', type=Path, help='Directory of numerically ordered frame images')
    parser.add_argument('output', type=Path)
    parser.add_argument('--fps', type=int, default=8)
    parser.add_argument('--width', type=int, default=160, choices=[160, 320])
    args = parser.parse_args()
    paths = sorted(p for p in args.frames.iterdir()
                   if p.suffix.lower() in {'.png', '.jpg', '.jpeg', '.bmp'})
    sectors = pack_frames(paths, args.output, args.width, args.width * 3 // 4, args.fps)
    print(f'Prepared {len(paths)} frames, {sectors} sectors/frame; firmware support pending')
