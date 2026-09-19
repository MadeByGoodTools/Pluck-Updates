'use strict';

const MSI_SUCCESS_CODES = [0, 1641, 3010];
const INNO_SETUP_QUIET_ARGS = ['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART'];

function splitExecutable(command) {
  if (command.startsWith('"')) {
    const closingQuote = command.indexOf('"', 1);
    if (closingQuote > 1) {
      return { file: command.slice(1, closingQuote), remainder: command.slice(closingQuote + 1).trim() };
    }
  }
  const match = /^(.+?\.(?:exe|com|bat|cmd))(?=\s|$)(.*)$/i.exec(command);
  return match ? { file: match[1], remainder: match[2].trim() } : null;
}

function quoteUnquotedExecutable(command) {
  if (command.startsWith('"')) return command;
  const match = /^(.+?\.(?:exe|com|bat|cmd))(?=\s|$)(.*)$/i.exec(command);
  if (!match || !/\s/.test(match[1])) return command;
  return `"${match[1]}"${match[2]}`;
}

function addInnoSetupQuietFlags(command, hasQuietCommand) {
  if (hasQuietCommand || !/(?:^|[\\/])unins\d*\.exe\b/i.test(command)) return command;
  if (/\/(?:silent|verysilent)\b/i.test(command)) return command;
  return `${command} /VERYSILENT /SUPPRESSMSGBOXES /NORESTART`;
}

function createUninstallPlan(item) {
  const productCode = String(item.PSChildName || '').trim();
  if (item.WindowsInstaller && /^\{[0-9a-f-]{36}\}$/i.test(productCode)) {
    return {
      file: 'msiexec.exe',
      args: ['/x', productCode, '/passive', '/norestart'],
      successCodes: MSI_SUCCESS_CODES
    };
  }

  const hasQuietCommand = Boolean(String(item.QuietUninstallString || '').trim());
  let command = String(item.QuietUninstallString || item.UninstallString || '').trim();
  if (!command) return null;
  command = command.replace(/(msiexec(?:\.exe)?\s+[^\r\n]*?)\/I(?=\s*\{)/i, '$1/X');
  const executable = splitExecutable(command);
  if (!hasQuietCommand && executable && !executable.remainder && /(?:^|[\\/])unins\d*\.exe$/i.test(executable.file)) {
    return { file: executable.file, args: INNO_SETUP_QUIET_ARGS, successCodes: [0] };
  }
  command = addInnoSetupQuietFlags(command, hasQuietCommand);
  command = quoteUnquotedExecutable(command);
  const successCodes = /^\s*"?msiexec(?:\.exe)?\b/i.test(command) ? MSI_SUCCESS_CODES : [0];
  return { file: 'cmd.exe', args: ['/d', '/s', '/c', command], successCodes };
}

module.exports = { createUninstallPlan };
