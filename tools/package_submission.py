"""Export contest source files, check TD dependencies and create SHA256 manifest.

No drive formatting, deletion, source rewriting or third-party downloads.
"""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


def check_project(root):
    project = root / 'src/td_project/anshibo.al'
    # TD emits an unescaped ampersand in the UsedInP&R attribute.
    tree = ET.fromstring(project.read_text(encoding='utf-8-sig').replace('UsedInP&R', 'UsedInPandR'))
    if tree.get('Path') != '.':
        raise RuntimeError('TD project root must be relative')
    references = [n.get('Path') for n in tree.iter('File')]
    missing = [p for p in references if not (project.parent / p).is_file()]
    if missing:
        raise RuntimeError(f'Missing project dependencies: {missing}')
    return len(references)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    if output.exists():
        raise RuntimeError('Output already exists; choose an unused directory')
    refs = check_project(ROOT)
    tracked = subprocess.check_output(['git', 'ls-files', '-z'], cwd=ROOT).decode('utf-8').split('\0')
    docs = {'SOURCE_ORIGIN.md', 'SOURCE_GUIDE.md', 'RESOURCE_MANAGEMENT.md',
            'PREFETCH.md', 'TRANSITIONS.md', 'EVENT_PROTOCOL.md', 'UART_CONTROL.md',
            'GRADED_ALERTS.md'}
    files = [p for p in tracked if p and (
        p.startswith(('src/', 'tb/', 'tools/', 'tf_resources/', 'measurements/'))
        or (p.startswith('sim/') and p.endswith('.ps1')) or p in docs)]
    files += ['firmware/anshibo_prefetch.bit']
    # Include user-provided scaling test resources, without changing their Git status.
    assets = ROOT / 'assets/phase8_scaling_test'
    if assets.exists():
        files += [p.relative_to(ROOT).as_posix() for p in assets.glob('*.BMP')]
    output.mkdir(parents=True)
    for name in sorted(set(files)):
        dest = output / name
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / name, dest)
    check_project(output)
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT).decode().strip()
    readme = '''# 校园信息发布与分级应急系统源码包

硬件：HX4S20C，EG4S20BG256。开发工具：Anlogic TD 6.2.1。

## 编译与运行

1. 将源码包完整解压到本地目录；TD打开src/td_project/anshibo.al，顶层top。
2. 使用工程内引脚和时序约束，执行综合、布局布线及Generate Bitstream。
3. 命令行构建：在src/td_project目录运行TD的td_commands_prompt.exe ../../tools/build_td.tcl。工具安装路径按本机修改。
4. 随包已验证固件firmware/anshibo_prefetch.bit可用BitWriter的PROGRAM_SRAM下载。断电启动需按开发板Flash流程固化。
5. FAT32 TF根目录复制tf_resources/NORMAL和ALERT；PLAYLIST.TXT可选。资源规则见RESOURCE_MANAGEMENT.md。

## 目录

- src：RTL、PLL/FIFO配置、官方加密IP和约束，保持相对路径。
- tb、sim：测试平台及运行脚本；ModelSim默认路径可在脚本中配置。量化测试见sim/run_quantitative_modelsim.ps1。
- tools：串口终端、字库和资源生成工具；launch_uart.cmd启动可选后台终端。图片处理及显示不依赖电脑。
- tf_resources：日常与应急测试底图；assets：不同尺寸的缩放测试图。
- measurements：历史验证记录及最新预加载时序报告；每条记录只适用于其注明版本与模型条件。
- SOURCE_GUIDE.md：模块阅读索引。SOURCE_ORIGIN.md：官方模块、IP与扩展说明。

## 范围与依赖

默认启用FAT32文件管理、图片缩放、双缓冲预读、SLIDE转场、亮度/对比度、字幕波形、分级预警与可选串口事件发布。视频研究工具及历史测试仅为开发记录，不属于当前产品运行路径。运行时间显示不是实时时钟；提示音由FPGA生成。

Python生成工具使用Python 3及Pillow（涉及字体/图片时）；Windows字体生成需要本机字体，随包已有字形数据可直接编译，无需重新生成。保留官方加密IP，需要TD支持对应器件。无需使用电脑CPU辅助图像或音频处理。

SHA256SUMS.txt包含文件校验值。PACKAGE_AUDIT.json包含导出版本和检查结果。
'''
    (output / 'README.md').write_text(readme, encoding='utf-8')
    audit = {'source_commit': commit, 'project_dependencies_checked': refs,
             'firmware_sha256': hashlib.sha256((output / 'firmware/anshibo_prefetch.bit').read_bytes()).hexdigest(),
             'hardware_validation': 'User confirmed prefetch firmware normal on 2026-10-08',
             'excluded': ['Git metadata', 'TD run cache', 'ModelSim work library', 'old firmware'],
             'physical_latency_measured': False}
    (output / 'PACKAGE_AUDIT.json').write_text(json.dumps(audit, indent=2), encoding='utf-8')
    manifest = []
    for p in sorted(output.rglob('*')):
        if p.is_file():
            manifest.append(f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.relative_to(output).as_posix()}')
    (output / 'SHA256SUMS.txt').write_text('\n'.join(manifest)+'\n', encoding='utf-8')
    print(json.dumps({'output': str(output), 'files': len(manifest)+1,
                      'bytes': sum(p.stat().st_size for p in output.rglob('*') if p.is_file()),
                      'dependencies': refs}, ensure_ascii=False))


if __name__ == '__main__':
    main()
