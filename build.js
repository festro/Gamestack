#!/usr/bin/env node
// GameStack doc builder — outputs GameStack.docx + GameStack.html
// Usage: node build.js [--docx] [--html]  (default: both)

const {
  Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell,
  HeadingLevel, AlignmentType, BorderStyle, WidthType, ShadingType, LevelFormat,
} = require('docx');
const fs = require('fs');
const path = require('path');

const args = process.argv.slice(2);
const buildDocx = args.length === 0 || args.includes('--docx');
const buildHtml = args.length === 0 || args.includes('--html');

const OUT_DIR = path.resolve(__dirname, 'output');
if (!fs.existsSync(OUT_DIR)) fs.mkdirSync(OUT_DIR);

// ══════════════════════════════════════════════════════════════════════════════
// SHARED DATA
// ══════════════════════════════════════════════════════════════════════════════

const META = {
  title:    'GameStack',
  subtitle: 'Infrastructure & Operations Documentation',
  version:  'v1.4',
  date:     'Mar 23 2026',
  owner:    'your-username / YourNetwork',
};

// Content types:
//   { type: 'h2', text }
//   { type: 'p',  text }
//   { type: 'table2', rows: [[key, val], ...] }
//   { type: 'table3', headers: [...], rows: [[...], ...] }
//   { type: 'bullets', items: [{ text, status? }] }
//     status: 'done' | 'warn' | 'open' | undefined (neutral)

const SECTIONS = [
  {
    title: 'Identity & Network',
    content: [
      { type: 'table2', rows: [
        ['Owner',          'Brandon (your-username)'],
        ['Network Name',   'YourNetwork'],
        ['Public Domain',  'yourdomain.com'],
        ['Daily Driver OS','Windows'],
        ['Server OS',      'Debian Linux (Your Linux OS on GameStack Host)'],
        ['Mesh VPN',       'Tailscale via Your Router — all LAN devices auto-enrolled'],
      ]},
    ],
  },
  {
    title: 'Hardware Inventory',
    content: [
      { type: 'h2', text: 'GMKTec NucBox GameStack Host — GameStack Host' },
      { type: 'table2', rows: [
        ['CPU',       'Your CPU'],
        ['GPU',       'Your GPU (iGPU)'],
        ['RAM',       'Your RAM'],
        ['Storage',   'Your Storage'],
        ['Wi-Fi',     'Your Wi-Fi adapter'],
        ['OS',        'Your Linux OS (Wayland)'],
        ['IP',        'YOUR_HOST_IP (static via NetworkManager)'],
        ['User/Host', 'your-username / your-hostname'],
        ['DNS',       'Cloudflare 1.1.1.1 / 1.0.0.1 (pinned via nmcli)'],
      ]},
      { type: 'h2', text: 'Your Streaming Client' },
      { type: 'table2', rows: [
        ['CPU',       'Your CPU'],
        ['GPU',       'Your GPU'],
        ['RAM',       'Your RAM'],
        ['Storage',   'Your Storage'],
        ['Wi-Fi',     'Your Wi-Fi adapter'],
        ['OS',        'Your Client OS'],
        ['Firmware',  'Custom firmware'],
        ['IP',        'YOUR_CLIENT_IP'],
        ['Moonlight', 'Built from source (Trixie too new for prebuilts)'],
      ]},
      { type: 'h2', text: 'Your Router — Current Router' },
      { type: 'table2', rows: [
        ['Wi-Fi',    'Dual-band Wi-Fi 7'],
        ['Ethernet', 'Dual 2.5G'],
        ['Tailscale','Running natively'],
        ['IP',       'YOUR_ROUTER_IP'],
        ['Role',     'Portable network hub — full stack travels as self-contained LAN'],
      ]},
      { type: 'h2', text: 'Your Router 2 — Planned Router Replacement' },
      { type: 'table2', rows: [
        ['Tailscale', 'Already configured'],
        ['IP',        'YOUR_ROUTER2_IP'],
        ['Trigger',   'When GameStack Host goes wired'],
        ['Notes',     'Your Router kept for Wi-Fi capability until wired transition'],
      ]},
      { type: 'h2', text: 'Gaming PC' },
      { type: 'table2', rows: [
        ['CPU', 'Your CPU'],
        ['GPU', 'Your GPU'],
        ['OS',  'Windows'],
        ['IP',  'YOUR_PC_IP (DHCP)'],
      ]},
    ],
  },
  {
    title: 'ISP & External Network',
    content: [
      { type: 'table2', rows: [
        ['ISP',           'Your ISP (residential)'],
        ['Public IP',     'YOUR_PUBLIC_IP (dynamic — DDNS not yet configured)'],
        ['Topology',      'Triple NAT: Internet → ISP Modem → Asus Router → Your Router → GameStack Host'],
        ['DMZ',           "Your Router (YOUR_UPSTREAM_ROUTER_IP) DMZ'd on Asus router — all inbound traffic passes through"],
        ['Port Forwards', 'Game ports forwarded → YOUR_HOST_IP on Your Router'],
        ['DDNS',          'Not yet configured — Cloudflare A record requires manual update on IP change'],
      ]},
    ],
  },
  {
    title: 'GameStack Overview',
    content: [
      { type: 'p', text: 'A self-contained portable gaming LAN stack running on the GameStack Host, streamable to the Streaming client via Moonlight/Wolf.' },
      { type: 'table2', rows: [
        ['GitHub',      'https://github.com/festro/Gamestack'],
        ['Version',     'v1.4'],
        ['Path',        '/home/your-username/gamestack/'],
        ['Wolf Config', '/home/your-username/gamestack/wolf-config/'],
        ['AMP Web UI',  'http://YOUR_HOST_IP:8080'],
        ['Wolf API',    'http://YOUR_HOST_IP:47989'],
      ]},
      { type: 'h2', text: 'Stack Components' },
      { type: 'table3', headers: ['Container', 'Image', 'Role'], rows: [
        ['amp',           'mitchtalmadge/amp-dockerized:latest',          'Game server management panel'],
        ['wolf',          'ghcr.io/games-on-whales/wolf:stable',          'Moonlight streaming host'],
        ['WolfPulseAudio','ghcr.io/games-on-whales/pulseaudio:master',    'Audio server for Wolf'],
        ['wolf-webrtc',   'local build (wolf-webrtc-sidecar/)',            'WebRTC browser streaming sidecar'],
        ['portal',        'nginx:alpine',                                  'GameStack portal UI — dashboard, AMP, docs'],
      ]},
      { type: 'h2', text: 'Access Points' },
      { type: 'table3', headers: ['Service', 'Address', 'Notes'], rows: [
        ['AMP Web UI',    'http://YOUR_HOST_IP:8080',  'Game server management — LAN only'],
        ['Wolf Pairing',  'http://YOUR_HOST_IP:47989', 'Moonlight pairing endpoint'],
        ['Game Server',   'game.yourdomain.com:GAME_PORT', 'Public — DNS Only on Cloudflare (YOUR_PUBLIC_IP)'],
        ['Game Query',    'game.yourdomain.com:QUERY_PORT','UDP (if applicable)'],
        ['Matrix',        'yourdomain.com',                'Proxied via Cloudflare'],
      ]},
    ],
  },
  {
    title: 'Completed Work',
    content: [
      { type: 'h2', text: 'Streaming client' },
      { type: 'bullets', items: [
        { status: 'done', text: 'Custom firmware flashed' },
        { status: 'done', text: 'Your Client OS installed' },
        { status: 'done', text: 'Moonlight built from source' },
        { status: 'done', text: 'PulseAudio/PipeWire audio working' },
        { status: 'done', text: 'Moonlight paired to Wolf at YOUR_HOST_IP' },
        { status: 'done', text: 'EGLFS/EGL fallback rendering confirmed working (DRM permission errors are cosmetic)' },
      ]},
      { type: 'h2', text: 'Wolf Streaming' },
      { type: 'bullets', items: [
        { status: 'done', text: 'HEVC/H264/AV1 zero-copy VA-API on /dev/dri/renderD128' },
        { status: 'done', text: 'Input confirmed working' },
        { status: 'done', text: 'network_mode: host — fixes UDP 47998/48000 video issues' },
        { status: 'done', text: 'Wolf socket symlink persisted via systemd wolf-sock-symlink.service' },
        { status: 'done', text: 'Stream connects — HEVC decode, VAAPI, audio init all confirmed' },
        { status: 'warn', text: 'Wolf UI container not launching — Wolf returns empty response to launch requests. Binary backtrace dump in wolf-config/cfg/' },
        { status: 'warn', text: 'Audio pulsesrc error reading data -1 — GStreamer audio pipeline dying post-connect' },
      ]},
      { type: 'h2', text: 'GameStack Tooling (Mar 23 2026)' },
      { type: 'bullets', items: [
        { status: 'done', text: 'build.js orphaned ] syntax error fixed — node build.js runs clean' },
        { status: 'done', text: 'configure.sh confirm() newline bug fixed — run_apply now executes correctly after wizard' },
        { status: 'done', text: 'ampinstmgr resetlogin replaced with container restart instruction — command broken without TTY' },
        { status: 'done', text: 'amp_activate_licence() added to configure.sh — AMP API login, ActivateAMPLicence, SetConfigs for new instance key, fully hands-free' },
        { status: 'done', text: 'sterilize.sh — commit message updated to v1.4, set -e fragility fixed, .env/ampdata purge section added' },
        { status: 'done', text: 'docker-compose.yml — duplicate /dev/dri volumes entry removed from wolf-webrtc' },
        { status: 'done', text: 'sidecar.py — codec probe added, detects H264 vs HEVC, refuses with actionable error if HEVC detected' },
        { status: 'done', text: '.env symlink removed — each directory (Gamestack/ and Gamestack_Live/) has independent .env' },
        { status: 'done', text: 'v1.4 committed and pushed to github.com/festro/Gamestack' },
      ]},
      { type: 'h2', text: 'Network' },
      { type: 'bullets', items: [
        { status: 'done', text: 'GameStack Host static IP YOUR_HOST_IP via NetworkManager' },
        { status: 'done', text: 'DNS pinned to Cloudflare 1.1.1.1/1.0.0.1' },
        { status: 'done', text: 'Cloudflare DNS — game.yourdomain.com (DNS Only) pointing to YOUR_PUBLIC_IP' },
        { status: 'done', text: 'Cloudflare DNS — yourdomain.com proxied for Matrix' },
        { status: 'done', text: 'AMP record removed from public DNS' },
        { status: 'done', text: "Triple NAT identified and resolved — Your Router DMZ'd on Asus router" },
        { status: 'done', text: 'UDP game port forwards added to Your Router → YOUR_HOST_IP' },
        
        { status: 'warn', text: 'DDNS not configured — ISP IP is dynamic, will eventually break game.yourdomain.com' },
      ]},
    ],
  },
  {
    title: 'Planned Hardware & Software Changes',
    content: [
      { type: 'table3', headers: ['Item', 'Details', 'Config Changes Required'], rows: [
        ['Streaming client Wi-Fi', 'Swap current CNVi card → Your Wi-Fi adapter (CNVi slot only)',       'None — driver support built into kernel'],
        ['Router swap',      'Your Router → Router 2 (when GameStack Host goes wired)',             'Recreate port forwards; update DNS connection name on GameStack Host (currently your-router-connection-name); verify static IP routing'],
        ['DDNS',             'Cloudflare A record auto-update for dynamic IP',          'Set up ddclient or Cloudflare API script; point game.yourdomain.com automatically on IP change'],
      ]},
    ],
  },
  {
    title: 'Key Technical Notes',
    content: [
      { type: 'bullets', items: [
        { text: 'Wolf runs as root (uid 0) — XDG_RUNTIME_DIR (/tmp/sockets) owned by uid 1000' },
        { text: 'Wolf socket: /tmp/sockets/wolf.sock — symlinked to /var/run/wolf/wolf.sock via systemd service' },
        { text: 'AMP uses fixed MAC to prevent licence deactivation on restart' },
        { text: "Streaming client M.2 slot is CNVi only — standard PCIe cards won't work" },
        { text: 'Your Client OS uses TDE, not KDE Plasma' },
        { text: 'Docker Compose v2 (docker compose with space)' },
        { text: 'Your Linux OS on GameStack Host runs Wayland by default' },
        { text: 'GameStack is fully portable — tar the folder, move to any Linux + Docker + AMD GPU machine, run setup.sh' },
        { text: 'Wolf app state folders use numeric session IDs as folder names' },
        { text: 'Network is triple NAT: Internet → ISP Modem → Asus Router (YOUR_MODEM_IP) → Your Router (YOUR_UPSTREAM_ROUTER_IP / YOUR_ROUTER_IP) → GameStack Host' },
        { text: "Your Router is DMZ'd on Asus router — Asus forwards all unsolicited inbound to YOUR_UPSTREAM_ROUTER_IP" },
        { text: 'Spectrum public IP is dynamic (currently YOUR_PUBLIC_IP) — DDNS setup required for reliability' },
        { text: 'Any proxied service: keep proxied via Cloudflare — use .well-known delegation when federation needed' },
        { text: 'wolf-webrtc sidecar codec probe: detects H264 vs HEVC before building GStreamer pipeline — Wolf must be set to H264 for WebRTC path' },
        { text: '.env is independent in Gamestack/ and Gamestack_Live/ — no symlink, each dir manages its own config' },
        { text: 'Key paths: live=~/Git/Gamestack_Live/, git=~/Git/Gamestack/, data=/home/festro33/Gamestack/' },
      ]},
    ],
  },
  {
    title: 'Next Session Priorities',
    content: [
      { type: 'bullets', items: [
        { status: 'open', text: 'Wolf UI — read backtrace dump in wolf-config/cfg/, consider testing ghcr.io/games-on-whales/wolf:master' },
        { status: 'open', text: 'Wolf audio — pulsesrc error reading data -1, investigate PulseAudio socket timing/permissions between wolf and WolfPulseAudio containers' },
        { status: 'open', text: 'DDNS — set up ddclient or Cloudflare API script for play.layonet.org dynamic IP rotation' },
        { status: 'open', text: 'Portal end-to-end test — verify AMP iframe and link fixes against live stack after fresh configure run' },
        { status: 'open', text: 'Router 2 transition — when K8 Plus goes wired: swap router, recreate port forwards, update DNS connection name' },
        { status: 'open', text: 'Streaming client CNVi Wi-Fi swap — Your Wi-Fi adapter' },
        { status: 'open', text: 'Steam in Wolf — config.toml entry exists, activate and test session launch' },
        { status: 'open', text: 'Push v1.5 commit after Wolf UI/audio resolved' },
      ]},
    ],
  },
];

// ══════════════════════════════════════════════════════════════════════════════
// DOCX RENDERER
// ══════════════════════════════════════════════════════════════════════════════

function buildDocxFile() {
  const bd = { style: BorderStyle.SINGLE, size: 1, color: 'CCCCCC' };
  const bh = { style: BorderStyle.SINGLE, size: 1, color: '888888' };
  const borders   = { top: bd, bottom: bd, left: bd, right: bd };
  const hBorders  = { top: bh, bottom: bh, left: bh, right: bh };

  function cell(text, w, isHeader = false) {
    return new TableCell({
      borders: isHeader ? hBorders : borders,
      width: { size: w, type: WidthType.DXA },
      shading: { fill: isHeader ? 'D5E8F0' : 'FFFFFF', type: ShadingType.CLEAR },
      margins: { top: 80, bottom: 80, left: 120, right: 120 },
      children: [new Paragraph({ children: [new TextRun({ text, bold: isHeader })] })],
    });
  }

  function twoColTable(rows) {
    return new Table({
      width: { size: 9360, type: WidthType.DXA },
      columnWidths: [3600, 5760],
      rows: rows.map(([k, v]) => new TableRow({ children: [cell(k, 3600), cell(v, 5760)] })),
    });
  }

  function threeColTable(headers, rows, widths = [2400, 3560, 3400]) {
    return new Table({
      width: { size: 9360, type: WidthType.DXA },
      columnWidths: widths,
      rows: [
        new TableRow({ children: headers.map((h, i) => cell(h, widths[i], true)) }),
        ...rows.map(r => new TableRow({ children: r.map((v, i) => cell(v, widths[i])) })),
      ],
    });
  }

  function renderItem(item) {
    if (item.type === 'h2') {
      return [new Paragraph({ heading: HeadingLevel.HEADING_2, children: [new TextRun(item.text)] })];
    }
    if (item.type === 'p') {
      return [new Paragraph({ children: [new TextRun({ text: item.text, color: '333333' })] })];
    }
    if (item.type === 'table2') {
      return [twoColTable(item.rows), new Paragraph({ children: [new TextRun('')] })];
    }
    if (item.type === 'table3') {
      return [threeColTable(item.headers, item.rows), new Paragraph({ children: [new TextRun('')] })];
    }
    if (item.type === 'bullets') {
      return item.items.map(b => {
        const prefix = b.status === 'done' ? '✅ '
                     : b.status === 'warn' ? '⚠️ '
                     : b.status === 'open' ? '🔲 ' : '';
        return new Paragraph({
          numbering: { reference: 'bullets', level: 0 },
          children: [new TextRun(prefix + b.text)],
        });
      });
    }
    return [];
  }

  const children = [
    new Paragraph({
      alignment: AlignmentType.CENTER,
      spacing: { before: 0, after: 240 },
      children: [new TextRun({ text: META.title, bold: true, size: 52, font: 'Arial', color: '1F4E79' })],
    }),
    new Paragraph({
      alignment: AlignmentType.CENTER,
      spacing: { before: 0, after: 480 },
      children: [new TextRun({ text: META.subtitle, size: 26, font: 'Arial', color: '595959' })],
    }),
  ];

  for (const section of SECTIONS) {
    children.push(
      new Paragraph({ heading: HeadingLevel.HEADING_1, children: [new TextRun(section.title)] })
    );
    for (const item of section.content) {
      children.push(...renderItem(item));
    }
    children.push(new Paragraph({ children: [new TextRun('')] }));
  }

  const doc = new Document({
    numbering: {
      config: [{
        reference: 'bullets',
        levels: [{ level: 0, format: LevelFormat.BULLET, text: '•', alignment: AlignmentType.LEFT,
          style: { paragraph: { indent: { left: 720, hanging: 360 } } } }],
      }],
    },
    styles: {
      default: { document: { run: { font: 'Arial', size: 22 } } },
      paragraphStyles: [
        { id: 'Heading1', name: 'Heading 1', basedOn: 'Normal', next: 'Normal', quickFormat: true,
          run: { size: 32, bold: true, font: 'Arial', color: '1F4E79' },
          paragraph: { spacing: { before: 320, after: 160 }, outlineLevel: 0 } },
        { id: 'Heading2', name: 'Heading 2', basedOn: 'Normal', next: 'Normal', quickFormat: true,
          run: { size: 26, bold: true, font: 'Arial', color: '2E74B5' },
          paragraph: { spacing: { before: 240, after: 120 }, outlineLevel: 1 } },
      ],
    },
    sections: [{
      properties: { page: { size: { width: 12240, height: 15840 }, margin: { top: 1440, right: 1440, bottom: 1440, left: 1440 } } },
      children,
    }],
  });

  return Packer.toBuffer(doc);
}

// ══════════════════════════════════════════════════════════════════════════════
// HTML RENDERER
// ══════════════════════════════════════════════════════════════════════════════

function buildHtmlFile() {
  function esc(s) {
    return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
  }

  function autoLink(s) {
    return esc(s).replace(/((https?:\/\/)[^\s<]+|(\d{1,3}\.){3}\d{1,3}(:\d+)?|[a-z0-9.-]+\.(org|io|com)(:\d+)?(\/?[^\s<]*)?)/g, m => {
      const href = m.startsWith('http') ? m : 'http://' + m;
      return `<a href="${href}" target="_blank" rel="noopener">${m}</a>`;
    });
  }

  function renderItem(item) {
    if (item.type === 'h2') {
      return `<h2>${esc(item.text)}</h2>`;
    }
    if (item.type === 'p') {
      return `<p>${autoLink(item.text)}</p>`;
    }
    if (item.type === 'table2') {
      const rows = item.rows.map(([k, v]) =>
        `<tr><td class="kv-key">${esc(k)}</td><td class="kv-val">${autoLink(v)}</td></tr>`
      ).join('');
      return `<table class="kv-table">${rows}</table>`;
    }
    if (item.type === 'table3') {
      const head = item.headers.map(h => `<th>${esc(h)}</th>`).join('');
      const rows = item.rows.map(r =>
        `<tr>${r.map(c => `<td>${autoLink(c)}</td>`).join('')}</tr>`
      ).join('');
      return `<table class="data-table"><thead><tr>${head}</tr></thead><tbody>${rows}</tbody></table>`;
    }
    if (item.type === 'bullets') {
      const lis = item.items.map(b => {
        const icon = b.status === 'done' ? '<span class="ic done">✓</span>'
                   : b.status === 'warn' ? '<span class="ic warn">!</span>'
                   : b.status === 'open' ? '<span class="ic open">○</span>'
                   : '<span class="ic neutral">–</span>';
        return `<li>${icon}<span>${autoLink(b.text)}</span></li>`;
      }).join('');
      return `<ul class="status-list">${lis}</ul>`;
    }
    return '';
  }

  const navItems = SECTIONS.map((s, i) =>
    `<li><a href="#s${i}">${esc(s.title)}</a></li>`
  ).join('');

  const sectionHtml = SECTIONS.map((s, i) => `
    <section id="s${i}">
      <h1>${esc(s.title)}</h1>
      ${s.content.map(renderItem).join('\n')}
    </section>`
  ).join('');

  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>${esc(META.title)}</title>
<style>
@import url('https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;600&family=Inter:wght@300;400;500;600&display=swap');

*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}

:root{
  --bg:#0e1117;--bg2:#151b26;--bg3:#1c2333;--border:#2a3347;
  --accent:#4a9eff;--accent2:#7ec8ff;--text:#cdd6f4;--muted:#6b7a99;
  --done:#3ddc97;--warn:#f5a623;--open:#7c8db5;
  --nav-w:220px;--mono:'JetBrains Mono',monospace;--sans:'Inter',sans-serif;
}

html{scroll-behavior:smooth}
body{background:var(--bg);color:var(--text);font-family:var(--sans);font-size:14.5px;line-height:1.7;display:flex;min-height:100vh}

nav{width:var(--nav-w);min-width:var(--nav-w);background:var(--bg2);border-right:1px solid var(--border);position:sticky;top:0;height:100vh;overflow-y:auto;display:flex;flex-direction:column}
.nav-header{padding:24px 20px 16px;border-bottom:1px solid var(--border)}
.nav-header .logo{font-family:var(--mono);font-size:15px;font-weight:600;color:var(--accent);letter-spacing:.04em}
.nav-header .version{font-family:var(--mono);font-size:11px;color:var(--muted);margin-top:3px}
nav ul{list-style:none;padding:12px 0;flex:1}
nav ul li a{display:block;padding:7px 20px;color:var(--muted);text-decoration:none;font-size:12.5px;transition:color .15s,background .15s,border-color .15s;border-left:2px solid transparent;line-height:1.4}
nav ul li a:hover,nav ul li a.active{color:var(--accent2);background:rgba(74,158,255,.06);border-left-color:var(--accent)}
.nav-footer{padding:14px 20px;border-top:1px solid var(--border);font-family:var(--mono);font-size:10px;color:var(--muted)}

main{flex:1;padding:48px 56px;max-width:900px}
.doc-title{font-family:var(--mono);font-size:28px;font-weight:600;color:var(--accent);letter-spacing:-.01em;margin-bottom:4px}
.doc-subtitle{font-size:13px;color:var(--muted);font-weight:300;margin-bottom:48px;padding-bottom:24px;border-bottom:1px solid var(--border);letter-spacing:.03em;text-transform:uppercase}

section{margin-bottom:52px}
section h1{font-family:var(--mono);font-size:13px;font-weight:600;color:var(--accent);text-transform:uppercase;letter-spacing:.12em;margin-bottom:18px;padding-bottom:8px;border-bottom:1px solid var(--border)}
section h2{font-family:var(--sans);font-size:13px;font-weight:600;color:var(--text);margin:24px 0 10px;padding-left:10px;border-left:2px solid var(--accent)}
p{color:var(--text);margin-bottom:14px;font-weight:300}
a{color:var(--accent);text-decoration:none}
a:hover{text-decoration:underline}

.kv-table{width:100%;border-collapse:collapse;margin-bottom:8px;font-size:13.5px}
.kv-table tr{border-bottom:1px solid var(--border)}
.kv-table tr:last-child{border-bottom:none}
.kv-table tr:hover td{background:rgba(255,255,255,.02)}
.kv-key{width:30%;padding:8px 14px 8px 0;color:var(--muted);font-family:var(--mono);font-size:12px;vertical-align:top;white-space:nowrap}
.kv-val{padding:8px 0;color:var(--text);font-weight:400}

.data-table{width:100%;border-collapse:collapse;margin-bottom:8px;font-size:13.5px}
.data-table th{text-align:left;padding:8px 12px;background:var(--bg3);color:var(--muted);font-family:var(--mono);font-size:11px;font-weight:600;text-transform:uppercase;letter-spacing:.08em;border-bottom:1px solid var(--border)}
.data-table td{padding:9px 12px;border-bottom:1px solid var(--border);vertical-align:top;font-weight:400}
.data-table tbody tr:last-child td{border-bottom:none}
.data-table tbody tr:hover td{background:rgba(255,255,255,.02)}

.status-list{list-style:none;display:flex;flex-direction:column;gap:7px}
.status-list li{display:flex;align-items:flex-start;gap:10px;font-size:13.5px;font-weight:400}
.ic{display:inline-flex;align-items:center;justify-content:center;width:18px;min-width:18px;height:18px;margin-top:2px;border-radius:3px;font-family:var(--mono);font-size:10px;font-weight:600}
.ic.done{background:rgba(61,220,151,.15);color:var(--done)}
.ic.warn{background:rgba(245,166,35,.15);color:var(--warn)}
.ic.open{background:rgba(124,141,181,.12);color:var(--open);border:1px solid var(--open)}
.ic.neutral{background:var(--bg3);color:var(--muted)}

::-webkit-scrollbar{width:6px}
::-webkit-scrollbar-track{background:var(--bg2)}
::-webkit-scrollbar-thumb{background:var(--border);border-radius:3px}

@media(max-width:700px){nav{display:none}main{padding:24px 20px}}
</style>
</head>
<body>
<nav id="sidebar">
  <div class="nav-header">
    <div class="logo">${esc(META.title)}</div>
    <div class="version">${esc(META.version)} · ${esc(META.date)}</div>
  </div>
  <ul>${navItems}</ul>
  <div class="nav-footer">${esc(META.owner)}</div>
</nav>
<main>
  <div class="doc-title">${esc(META.title)}</div>
  <div class="doc-subtitle">${esc(META.subtitle)}</div>
  ${sectionHtml}
</main>
<script>
const sections = document.querySelectorAll('section[id]');
const links = document.querySelectorAll('nav a');
const obs = new IntersectionObserver(entries => {
  entries.forEach(e => {
    if (e.isIntersecting) {
      links.forEach(l => l.classList.remove('active'));
      const a = document.querySelector('nav a[href="#' + e.target.id + '"]');
      if (a) a.classList.add('active');
    }
  });
}, { rootMargin: '-20% 0px -70% 0px' });
sections.forEach(s => obs.observe(s));
</script>
</body>
</html>`;
}

// ══════════════════════════════════════════════════════════════════════════════
// MAIN
// ══════════════════════════════════════════════════════════════════════════════

(async () => {
  const tasks = [];

  if (buildDocx) {
    tasks.push(
      buildDocxFile().then(buf => {
        fs.writeFileSync(path.join(OUT_DIR, 'GameStack.docx'), buf);
        console.log('✓ GameStack.docx');
      })
    );
  }

  if (buildHtml) {
    fs.writeFileSync(path.join(OUT_DIR, 'GameStack.html'), buildHtmlFile());
    console.log('✓ GameStack.html');
  }

  await Promise.all(tasks);
})();
