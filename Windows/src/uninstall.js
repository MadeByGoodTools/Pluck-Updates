'use strict';

const path = require('path');

const MSI_SUCCESS_CODES = [0, 1641, 3010];
const INNO_QUIET_ARGS = ['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART'];

function splitExecutable(command) {
  const value = String(command || '').trim();
  if (!value) return null;
  if (value.startsWith('"')) {
    const closingQuote = value.indexOf('"', 1);
    if (closingQuote > 1) {
      return { file: value.slice(1, closingQuote), remainder: value.slice(closingQuote + 1).trim() };
    }
  }
  const match = /^(.+?\.(?:exe|com|bat|cmd))(?=\s|$)(.*)$/i.exec(value);
  return match ? { file: match[1], remainder: match[2].trim() } : null;
}

function parseWindowsArguments(commandLine) {
  const args = [];
  let index = 0;
  while (index < commandLine.length) {
    while (/\s/.test(commandLine[index] || '')) index += 1;
    if (index >= commandLine.length) break;
    let value = '';
    let quoted = false;
    let slashes = 0;
    while (index < commandLine.length) {
      const char = commandLine[index];
      if (char === '\\') {
        slashes += 1;
        index += 1;
        continue;
      }
      if (char === '"') {
        value += '\\'.repeat(Math.floor(slashes / 2));
        if (slashes % 2) value += '"';
        else quoted = !quoted;
        slashes = 0;
        index += 1;
        continue;
      }
      value += '\\'.repeat(slashes);
      slashes = 0;
      if (!quoted && /\s/.test(char)) break;
      value += char;
      index += 1;
    }
    value += '\\'.repeat(slashes);
    args.push(value);
    while (/\s/.test(commandLine[index] || '')) index += 1;
  }
  return args;
}

function normalizeMsiCommand(command) {
  return command.replace(/(msiexec(?:\.exe)?\s+[^\r\n]*?)\/I(?=\s*\{)/i, '$1/X');
}

function directPlan(command, options = {}) {
  const executable = splitExecutable(command);
  if (!executable) return null;
  const extension = path.extname(executable.file).toLowerCase();
  if (!['.exe', '.com'].includes(extension) || /[&|<>]/.test(executable.remainder)) return null;
  return {
    file: executable.file,
    args: parseWindowsArguments(executable.remainder),
    successCodes: options.successCodes || [0],
    label: options.label || 'registered uninstaller',
    quiet: Boolean(options.quiet)
  };
}

function shellPlan(command, options = {}) {
  return {
    file: 'cmd.exe',
    args: ['/d', '/s', '/c', command],
    successCodes: options.successCodes || [0],
    label: options.label || 'registered uninstaller',
    quiet: Boolean(options.quiet)
  };
}

function planForCommand(command, options = {}) {
  const normalized = normalizeMsiCommand(String(command || '').trim());
  return directPlan(normalized, options) || shellPlan(normalized, options);
}

function isInno(executable, item) {
  return /(?:^|[\\/])unins\d*\.exe$/i.test(executable?.file || '') || /_is1$/i.test(String(item.PSChildName || ''));
}

function isSquirrel(executable, command) {
  return /(?:^|[\\/])update\.exe$/i.test(executable?.file || '') && /--uninstall\b/i.test(command);
}

function isLikelyNsis(executable, item) {
  return /(?:^|[\\/])uninstall(?:er)?\.exe$/i.test(executable?.file || '') && !item.WindowsInstaller;
}

function uniquePlans(plans) {
  const seen = new Set();
  return plans.filter(plan => {
    if (!plan) return false;
    const key = JSON.stringify([plan.file.toLowerCase(), plan.args]);
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

function createUninstallPlans(item) {
  if (item.Kind === 'Appx' && item.PackageFullName) {
    const packageName = String(item.PackageFullName).replace(/'/g, "''");
    return [{
      file: 'powershell.exe',
      args: ['-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', `Remove-AppxPackage -Package '${packageName}' -ErrorAction Stop`],
      successCodes: [0], label: 'Windows app package removal', quiet: true
    }];
  }

  const productCode = String(item.PSChildName || '').trim();
  if (item.WindowsInstaller && /^\{[0-9a-f-]{36}\}$/i.test(productCode)) {
    return [
      { file: 'msiexec.exe', args: ['/x', productCode, '/passive', '/norestart'], successCodes: MSI_SUCCESS_CODES, label: 'MSI quiet removal', quiet: true },
      { file: 'msiexec.exe', args: ['/x', productCode, '/norestart'], successCodes: MSI_SUCCESS_CODES, label: 'MSI removal', quiet: false }
    ];
  }

  const quietCommand = String(item.QuietUninstallString || '').trim();
  const normalCommand = String(item.UninstallString || '').trim();
  if (!quietCommand && !normalCommand) return [];
  const normalExecutable = splitExecutable(normalCommand);
  const plans = [];

  if (quietCommand) {
    plans.push(planForCommand(quietCommand, { label: 'vendor quiet removal', quiet: true }));
  } else if (isInno(normalExecutable, item)) {
    plans.push({ file: normalExecutable.file, args: [...parseWindowsArguments(normalExecutable.remainder), ...INNO_QUIET_ARGS], successCodes: [0], label: 'Inno Setup quiet removal', quiet: true });
  } else if (isSquirrel(normalExecutable, normalCommand)) {
    const args = parseWindowsArguments(normalExecutable.remainder);
    if (!args.some(arg => /^(-s|--silent)$/i.test(arg))) args.push('--silent');
    plans.push({ file: normalExecutable.file, args, successCodes: [0], label: 'Squirrel quiet removal', quiet: true });
  } else if (isLikelyNsis(normalExecutable, item)) {
    plans.push({ file: normalExecutable.file, args: [...parseWindowsArguments(normalExecutable.remainder), '/S'], successCodes: [0], label: 'NSIS quiet removal', quiet: true });
  }

  if (normalCommand) {
    const successCodes = /^\s*"?msiexec(?:\.exe)?\b/i.test(normalCommand) ? MSI_SUCCESS_CODES : [0];
    plans.push(planForCommand(normalCommand, { successCodes, label: 'vendor removal', quiet: false }));
  }
  return uniquePlans(plans);
}

function createUninstallPlan(item) {
  return createUninstallPlans(item)[0] || null;
}

module.exports = { createUninstallPlan, createUninstallPlans, parseWindowsArguments, splitExecutable };
