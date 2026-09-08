"""将 PNG 图标尺寸装入标准 ICNS 容器，不依赖 iconutil 的系统服务。"""
from pathlib import Path
import struct
import sys

source, target = map(Path, sys.argv[1:])
sizes = {
    b"ic07": "icon_128x128.png", b"ic08": "icon_256x256.png",
    b"ic09": "icon_512x512.png", b"ic10": "icon_512x512@2x.png",
    b"ic11": "icon_16x16@2x.png", b"ic12": "icon_32x32@2x.png",
    b"ic13": "icon_128x128@2x.png", b"ic14": "icon_256x256@2x.png",
}
chunks = []
for kind, filename in sizes.items():
    data = (source / filename).read_bytes()
    chunks.append(kind + struct.pack(">I", len(data) + 8) + data)
payload = b"".join(chunks)
target.write_bytes(b"icns" + struct.pack(">I", len(payload) + 8) + payload)
