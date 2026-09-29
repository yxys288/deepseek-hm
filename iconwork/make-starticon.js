const { spawnSync } = require('child_process');
const fs = require('fs');
const path = require('path');

// 生成启动页图标：透明底 + 官方蓝色鲸鱼（鲸鱼尺寸 720/1024，与旧白底版一致）。
// 方式：headless Edge --screenshot + --default-background-color=00000000（透明通道）。
// 产物：entry/src/main/resources/base/media/startIcon.png（+ iconwork/start-icon.png 存档）
// 用法: node iconwork/make-starticon.js

// 浏览器可执行文件：默认按 Windows 常见安装位置，可用环境变量 EDGE 覆盖。
const EDGE = process.env.EDGE || 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe';
// 路径一律相对**仓库根**解析（不依赖当前工作目录）
const ROOT = path.resolve(__dirname, '..');
const PROFILE = path.join(ROOT, 'iconwork', '.tmp-shot');
const FILE = 'file:///' + path.join(ROOT, 'iconwork', 'start-icon.html').replace(/\\/g, '/');
const OUT_WORK = path.join(ROOT, 'iconwork', 'start-icon.png');
const OUT = path.join(ROOT, 'entry', 'src', 'main', 'resources', 'base', 'media', 'startIcon.png');

if (fs.existsSync(PROFILE)) {
  fs.rmSync(PROFILE, { recursive: true, force: true });
}

const r = spawnSync(EDGE, [
  '--headless=new', '--disable-gpu', '--no-first-run', '--no-default-browser-check',
  '--disable-sync', '--disable-extensions',
  '--user-data-dir=' + PROFILE,
  '--window-size=1024,1024',
  '--force-device-scale-factor=1',
  '--default-background-color=00000000',
  '--screenshot=' + OUT_WORK,
  FILE
], { stdio: 'inherit', timeout: 60000 });

if (!fs.existsSync(OUT_WORK)) {
  console.error('ERR: screenshot not produced');
  process.exit(1);
}
fs.copyFileSync(OUT_WORK, OUT);
console.log(JSON.stringify({ ok: true, bytes: fs.statSync(OUT).size, out: OUT }));
try { fs.rmSync(PROFILE, { recursive: true, force: true }); } catch (e) { }
