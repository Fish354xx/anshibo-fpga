"""Check the media container against its byte layout and padding contract."""
import struct
import tempfile
from pathlib import Path
from PIL import Image
from pack_tf_clip import pack_frames

with tempfile.TemporaryDirectory() as temp:
    root = Path(temp)
    frames = []
    for index, color in enumerate(((255, 0, 0), (0, 255, 0))):
        path = root / f'{index:04d}.png'
        Image.new('RGB', (8, 6), color).save(path)
        frames.append(path)
    for width, height in ((160, 120), (320, 240)):
        output = root / 'clip.avtf'
        sectors = pack_frames(frames, output, width, height, 8)
        data = output.read_bytes()
        magic, version, w, h, fps, count, stride, size = struct.unpack('<4sHHHHIII', data[:24])
        assert (magic, version, w, h, fps, count, stride) == (b'AVTF', 1, width, height, 8, 2, sectors)
        assert len(data) == 512 + count * stride * 512
        for index, color in enumerate(((255, 0, 0), (0, 255, 0))):
            start = 512 + index * stride * 512
            assert data[start:start + 2] == b'BM'
            assert struct.unpack('<I', data[start + 2:start + 6])[0] == size
            assert data[start + 54:start + 57] == bytes(reversed(color))
            assert set(data[start + size:start + stride * 512]) <= {0}
    try:
        pack_frames([], root / 'empty.avtf')
        raise AssertionError('Empty clip accepted')
    except ValueError:
        pass
print('TF CLIP PACK: ALL CHECKS PASSED')
