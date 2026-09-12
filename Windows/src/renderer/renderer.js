const $ = selector => document.querySelector(selector);
const format = bytes => bytes ? new Intl.NumberFormat(undefined, { style: 'unit', unit: bytes >= 1073741824 ? 'gigabyte' : 'megabyte', maximumFractionDigits: bytes >= 1073741824 ? 1 : 0 }).format(bytes / (bytes >= 1073741824 ? 1073741824 : 1048576)) : '—';
let apps = [];
let reclaimables = [];

function esc(value) { const node = document.createElement('span'); node.textContent = value || ''; return node.innerHTML; }

function renderApps() {
  $('#apps').innerHTML = apps.map(app => `<label class="row"><input type="checkbox" data-app="${app.id}"><img src="../../assets/app.png" alt=""><span><strong>${esc(app.name)}</strong><small>${app.fast ? 'Fast removal · ' : ''}${esc(app.detail)}</small></span><b>${format(app.size)}</b></label>`).join('') || '<p class="loading">No registered uninstallers found.</p>';
  document.querySelectorAll('[data-app]').forEach(box => box.addEventListener('change', updateAppButton));
  updateAppButton();
}

function updateAppButton() {
  const count = document.querySelectorAll('[data-app]:checked').length;
  $('#uninstallButton').disabled = count === 0;
  $('#appCount').textContent = count ? `${count} selected` : `${apps.length} applications`;
}

function renderReclaimables() {
  const total = reclaimables.reduce((sum, item) => sum + item.size, 0);
  $('#purgeable').textContent = format(total);
  $('#reclaimables').innerHTML = reclaimables.map(item => `<label class="row"><input type="checkbox" data-reclaim="${item.id}" checked><img src="../../assets/folder.png" alt=""><span><strong>${esc(item.name)}</strong><small>${esc(item.detail)}</small></span><b>${format(item.size)}</b></label>`).join('') || '<p class="loading">No large safe cleanup items found.</p>';
  document.querySelectorAll('[data-reclaim]').forEach(box => box.addEventListener('change', updateReclaimButton));
  updateReclaimButton();
}

function updateReclaimButton() {
  $('#reclaimButton').disabled = document.querySelectorAll('[data-reclaim]:checked').length === 0;
}

async function load() {
  const [snapshot, appList, cleanup] = await Promise.all([window.pluck.snapshot(), window.pluck.scanApps(), window.pluck.scanReclaimable()]);
  apps = appList; reclaimables = cleanup;
  $('#free').textContent = format(snapshot.free);
  $('#permissionText').textContent = snapshot.admin ? '✓ Administrator access enabled' : 'Standard access · administrator is optional';
  $('#admin').hidden = snapshot.admin;
  renderApps(); renderReclaimables();
  const total = reclaimables.reduce((sum, item) => sum + item.size, 0);
  $('#available').textContent = format(snapshot.free + total);
}

document.querySelectorAll('nav button').forEach(button => button.addEventListener('click', () => {
  document.querySelectorAll('nav button,.tab').forEach(node => node.classList.remove('active'));
  button.classList.add('active'); $(`#${button.dataset.tab}`).classList.add('active');
}));

$('#uninstallButton').addEventListener('click', async () => {
  const ids = [...document.querySelectorAll('[data-app]:checked')].map(box => box.dataset.app);
  await window.pluck.uninstall(ids);
});
$('#reclaimButton').addEventListener('click', async () => {
  const ids = [...document.querySelectorAll('[data-reclaim]:checked')].map(box => box.dataset.reclaim);
  const result = await window.pluck.reclaim(ids);
  if (result.ok) { reclaimables = await window.pluck.scanReclaimable(); renderReclaimables(); }
});
$('#scan').addEventListener('click', async () => { reclaimables = await window.pluck.scanReclaimable(); renderReclaimables(); });
$('#emptyTrash').addEventListener('click', () => window.pluck.emptyTrash());
$('#admin').addEventListener('click', () => window.pluck.restartAsAdmin());
$('#quit').addEventListener('click', () => window.pluck.quit());

load();
