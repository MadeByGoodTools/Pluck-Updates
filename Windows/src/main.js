const { app, BrowserWindow, Tray, ipcMain, nativeImage, screen, shell, dialog } = require('electron');
const { execFile, spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');
const crypto = require('crypto');
const { createUninstallPlan } = require('./uninstall');

let tray;
let panel;
let applications = new Map();
let reclaimables = new Map();
let suspendAutoHide = false;

app.setAppUserModelId('ca.goodtools.pluck');
if (!app.requestSingleInstanceLock()) app.quit();

function runPowerShell(script) {
  return new Promise((resolve, reject) => {
    execFile('powershell.exe', ['-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', script],
      { windowsHide: true, maxBuffer: 16 * 1024 * 1024 },
      (error, stdout, stderr) => error ? reject(new Error(stderr.trim() || error.message)) : resolve(stdout.trim()));
  });
}

function runProcess(file, args, options = {}) {
  return new Promise((resolve, reject) => {
    const { successCodes = [0], ...spawnOptions } = options;
    const child = spawn(file, args, { windowsHide: false, stdio: 'ignore', ...spawnOptions });
    child.once('error', reject);
    child.once('exit', (code, signal) => {
      if (successCodes.includes(code)) resolve();
      else reject(new Error(`${path.basename(file)} exited with ${code ?? signal ?? 'an unknown error'}`));
    });
  });
}

async function showPanelMessage(options) {
  suspendAutoHide = true;
  try {
    return await dialog.showMessageBox(panel, options);
  } finally {
    suspendAutoHide = false;
  }
}

async function isAdministrator() {
  try {
    return (await runPowerShell("([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]'Administrator')")).toLowerCase() === 'true';
  } catch { return false; }
}

async function storageSnapshot() {
  try {
    const raw = await runPowerShell("Get-CimInstance Win32_LogicalDisk -Filter \"DeviceID='C:'\" | Select-Object Size,FreeSpace | ConvertTo-Json -Compress");
    const disk = JSON.parse(raw);
    return { total: Number(disk.Size || 0), free: Number(disk.FreeSpace || 0) };
  } catch { return { total: 0, free: 0 }; }
}

async function directorySize(target) {
  let total = 0;
  const pending = [target];
  while (pending.length) {
    const current = pending.pop();
    let entries;
    try { entries = await fs.promises.readdir(current, { withFileTypes: true }); } catch { continue; }
    for (const entry of entries) {
      const full = path.join(current, entry.name);
      if (entry.isSymbolicLink()) continue;
      if (entry.isDirectory()) pending.push(full);
      else if (entry.isFile()) {
        try { total += (await fs.promises.stat(full)).size; } catch { }
      }
    }
  }
  return total;
}

function createPanel() {
  panel = new BrowserWindow({
    width: 600,
    height: 680,
    show: false,
    frame: false,
    resizable: false,
    maximizable: false,
    fullscreenable: false,
    skipTaskbar: true,
    alwaysOnTop: true,
    backgroundColor: '#17181c',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true
    }
  });
  panel.loadFile(path.join(__dirname, 'renderer', 'index.html'));
  panel.on('blur', () => { if (!suspendAutoHide) panel.hide(); });
  panel.on('close', event => { if (!app.isQuitting) { event.preventDefault(); panel.hide(); } });
}

function positionAndShow() {
  if (!panel) return;
  const display = screen.getDisplayNearestPoint(screen.getCursorScreenPoint());
  const area = display.workArea;
  const [width, height] = panel.getSize();
  panel.setPosition(Math.round(area.x + area.width - width - 12), Math.round(area.y + area.height - height - 12));
  panel.show();
  panel.focus();
}

app.whenReady().then(() => {
  createPanel();
  const icon = nativeImage.createFromPath(path.join(__dirname, '..', 'assets', 'pluck.png')).resize({ width: 20, height: 20 });
  tray = new Tray(icon);
  tray.setToolTip('Pluck — uninstall apps and reclaim space');
  tray.on('click', () => panel.isVisible() ? panel.hide() : positionAndShow());
  panel.once('ready-to-show', positionAndShow);
});

app.on('second-instance', positionAndShow);
app.on('window-all-closed', () => {});

ipcMain.handle('snapshot', async () => ({ ...(await storageSnapshot()), admin: await isAdministrator() }));

async function scanInstalledApps() {
  const script = `
    $roots = @(
      'HKLM:\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*',
      'HKLM:\\Software\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*',
      'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*'
    )
    @(Get-ItemProperty $roots -ErrorAction SilentlyContinue |
      Where-Object { $_.DisplayName -and ($_.UninstallString -or $_.QuietUninstallString) } |
      Select-Object DisplayName,Publisher,DisplayVersion,EstimatedSize,InstallLocation,WindowsInstaller,PSPath,PSChildName,UninstallString,QuietUninstallString |
      Sort-Object DisplayName -Unique) | ConvertTo-Json -Compress
  `;
  try {
    const raw = await runPowerShell(script);
    const values = raw ? JSON.parse(raw) : [];
    const list = Array.isArray(values) ? values : [values];
    applications.clear();
    return list.map(value => {
      const id = crypto.randomUUID();
      applications.set(id, value);
      const install = String(value.InstallLocation || '');
      const localPrograms = path.join(process.env.LOCALAPPDATA || '', 'Programs').toLowerCase();
      const fast = Boolean(install) && path.resolve(install).toLowerCase().startsWith(localPrograms + path.sep) && !value.WindowsInstaller;
      return {
        id,
        name: value.DisplayName,
        detail: [value.Publisher, value.DisplayVersion].filter(Boolean).join(' · ') || 'Installed application',
        size: Number(value.EstimatedSize || 0) * 1024,
        fast
      };
    });
  } catch { return []; }
}

ipcMain.handle('scan-apps', scanInstalledApps);

ipcMain.handle('scan-reclaimable', async () => {
  const local = process.env.LOCALAPPDATA || path.join(os.homedir(), 'AppData', 'Local');
  const programData = process.env.ProgramData || 'C:\\ProgramData';
  const candidates = [
    { name: 'Temporary files', target: process.env.TEMP || path.join(local, 'Temp'), detail: 'Windows and application temporary files', contentsOnly: true },
    { name: 'Crash reports', target: path.join(local, 'CrashDumps'), detail: 'Application crash diagnostics' },
    { name: 'Graphics cache', target: path.join(local, 'D3DSCache'), detail: 'Regenerable DirectX shader data' },
    { name: 'Internet cache', target: path.join(local, 'Microsoft', 'Windows', 'INetCache'), detail: 'Regenerable web cache' },
    { name: 'Windows error reports', target: path.join(programData, 'Microsoft', 'Windows', 'WER', 'ReportArchive'), detail: 'Archived Windows diagnostics' },
    { name: 'npm cache', target: path.join(local, 'npm-cache'), detail: 'Regenerable developer package cache' },
    { name: 'pnpm store', target: path.join(local, 'pnpm', 'store'), detail: 'Regenerable developer package cache' }
  ];
  const found = await Promise.all(candidates.map(async candidate => {
    try {
      await fs.promises.access(candidate.target);
      const size = await directorySize(candidate.target);
      return size >= 10 * 1024 * 1024 ? { ...candidate, size } : null;
    } catch { return null; }
  }));
  reclaimables.clear();
  return found.filter(Boolean).sort((a, b) => b.size - a.size).map(value => {
    const id = crypto.randomUUID();
    reclaimables.set(id, value);
    return { id, name: value.name, detail: value.detail, size: value.size };
  });
});

ipcMain.handle('uninstall', async (_event, ids) => {
  const chosen = ids.map(id => applications.get(id)).filter(Boolean);
  if (!chosen.length) return { ok: false, completed: 0, failed: 0 };
  const answer = await showPanelMessage({
    type: 'warning',
    buttons: ['Uninstall', 'Cancel'],
    defaultId: 1,
    cancelId: 1,
    title: 'Pluck',
    message: `Uninstall ${chosen.length === 1 ? chosen[0].DisplayName : `${chosen.length} applications`}?`,
    detail: 'Pluck directly removes eligible per-user apps. Complex apps with MSI packages, services, or system components use their registered uninstaller so Windows is not left damaged.'
  });
  if (answer.response !== 0) return { ok: false, cancelled: true, completed: 0, failed: 0 };

  panel.hide();
  const completed = [];
  const failures = [];
  for (const item of chosen) {
    try {
      if (isFastRemovalEligible(item)) await fastRemove(item);
      else await runRegisteredUninstaller(item);
      completed.push(item.DisplayName);
    } catch (error) {
      failures.push({ name: item.DisplayName, message: error.message });
    }
  }

  positionAndShow();
  if (failures.length) {
    await showPanelMessage({
      type: 'warning',
      buttons: ['OK'],
      title: 'Pluck',
      message: `${failures.length} ${failures.length === 1 ? 'app was' : 'apps were'} not removed`,
      detail: failures.map(failure => `${failure.name}: ${failure.message}`).join('\n')
    });
  }
  return { ok: failures.length === 0, completed: completed.length, failed: failures.length };
});

async function runRegisteredUninstaller(item) {
  const plan = createUninstallPlan(item);
  if (!plan) throw new Error('No registered uninstall command was found.');
  await runProcess(plan.file, plan.args, { successCodes: plan.successCodes });
}

function isFastRemovalEligible(item) {
  const install = String(item.InstallLocation || '');
  if (!install || item.WindowsInstaller) return false;
  const localPrograms = path.join(process.env.LOCALAPPDATA || '', 'Programs').toLowerCase();
  const normalized = path.resolve(install).toLowerCase();
  return Boolean(localPrograms) && normalized.startsWith(localPrograms + path.sep) && normalized !== localPrograms;
}

function psQuote(value) { return `'${String(value).replace(/'/g, "''")}'`; }

async function fastRemove(item) {
  const install = path.resolve(item.InstallLocation);
  const name = String(item.DisplayName || '').replace(/[<>:"/\\|?*]/g, '').trim();
  const backupRoot = path.join(process.env.LOCALAPPDATA || os.tmpdir(), 'Pluck', 'Removal Records');
  await fs.promises.mkdir(backupRoot, { recursive: true });
  await fs.promises.writeFile(path.join(backupRoot, `${Date.now()}-${name || 'app'}.json`), JSON.stringify(item, null, 2));

  await runPowerShell(`Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.StartsWith(${psQuote(install)}, [System.StringComparison]::OrdinalIgnoreCase) } | Stop-Process -Force -ErrorAction SilentlyContinue`).catch(() => {});
  try {
    await fs.promises.access(install);
    await shell.trashItem(install);
  } catch (error) {
    throw new Error(`Could not move the application folder to the Recycle Bin: ${error.message}`);
  }

  const targets = [];
  for (const root of [process.env.APPDATA, process.env.LOCALAPPDATA]) {
    if (!root || !name) continue;
    const candidate = path.join(root, name);
    if (path.resolve(candidate).toLowerCase() !== install.toLowerCase()) targets.push(candidate);
  }
  for (const target of targets) {
    try { await fs.promises.access(target); await shell.trashItem(target); } catch { }
  }
  if (item.PSPath) await runPowerShell(`Remove-Item -LiteralPath ${psQuote(item.PSPath)} -Recurse -Force -ErrorAction SilentlyContinue`).catch(() => {});
}

ipcMain.handle('reclaim', async (_event, ids) => {
  const chosen = ids.map(id => reclaimables.get(id)).filter(Boolean);
  if (!chosen.length) return { ok: false, reclaimed: 0 };
  const total = chosen.reduce((sum, item) => sum + item.size, 0);
  const answer = await dialog.showMessageBox(panel, {
    type: 'warning',
    buttons: ['Reclaim Space', 'Cancel'],
    defaultId: 1,
    cancelId: 1,
    title: 'Pluck',
    message: `Reclaim ${Math.max(0.1, total / 1073741824).toFixed(1)} GB?`,
    detail: 'The safe temporary and cache items shown in Pluck will move to the Recycle Bin. Passwords, browser profiles, documents, and application settings are excluded.'
  });
  if (answer.response !== 0) return { ok: false, reclaimed: 0 };
  let reclaimed = 0;
  for (const item of chosen) {
    const targets = item.contentsOnly
      ? await fs.promises.readdir(item.target).then(names => names.map(name => path.join(item.target, name))).catch(() => [])
      : [item.target];
    for (const target of targets) {
      try {
        const stat = await fs.promises.stat(target);
        const size = stat.isDirectory() ? await directorySize(target) : stat.size;
        await shell.trashItem(target);
        reclaimed += size;
      } catch { }
    }
  }
  return { ok: true, reclaimed };
});

ipcMain.handle('empty-trash', async () => {
  const answer = await dialog.showMessageBox(panel, {
    type: 'warning', buttons: ['Empty Recycle Bin', 'Cancel'], defaultId: 1, cancelId: 1,
    message: 'Empty the Recycle Bin permanently?', detail: 'This cannot be undone.'
  });
  if (answer.response !== 0) return false;
  try { await runPowerShell('(New-Object -ComObject Shell.Application).NameSpace(10).Items() | ForEach-Object { Remove-Item $_.Path -Recurse -Force -ErrorAction SilentlyContinue }'); return true; }
  catch { return false; }
});

ipcMain.handle('restart-admin', async () => {
  const executable = process.execPath.replace(/'/g, "''");
  spawn('powershell.exe', ['-NoProfile', '-Command', `Start-Process -FilePath '${executable}' -Verb RunAs`], { detached: true, windowsHide: true, stdio: 'ignore' }).unref();
  app.quit();
  return true;
});

ipcMain.on('quit', () => { app.isQuitting = true; app.quit(); });
