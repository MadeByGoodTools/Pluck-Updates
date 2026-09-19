'use strict';

const MSI_SUCCESS_CODES = [0, 1641, 3010];

function createUninstallPlan(item) {
  const productCode = String(item.PSChildName || '').trim();
  if (item.WindowsInstaller && /^\{[0-9a-f-]{36}\}$/i.test(productCode)) {
    return {
      file: 'msiexec.exe',
      args: ['/x', productCode, '/passive', '/norestart'],
      successCodes: MSI_SUCCESS_CODES
    };
  }

  let command = String(item.QuietUninstallString || item.UninstallString || '').trim();
  if (!command) return null;
  command = command.replace(/(msiexec(?:\.exe)?\s+[^\r\n]*?)\/I(?=\s*\{)/i, '$1/X');
  const successCodes = /^\s*"?msiexec(?:\.exe)?\b/i.test(command) ? MSI_SUCCESS_CODES : [0];
  return { file: 'cmd.exe', args: ['/d', '/s', '/c', command], successCodes };
}

module.exports = { createUninstallPlan };
