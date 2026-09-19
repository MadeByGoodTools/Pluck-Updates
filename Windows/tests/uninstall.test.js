'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { createUninstallPlan } = require('../src/uninstall');

const productCode = '{12345678-1234-1234-1234-123456789ABC}';

test('builds a direct MSI uninstall plan from the registry product code', () => {
  assert.deepEqual(createUninstallPlan({ WindowsInstaller: 1, PSChildName: productCode }), {
    file: 'msiexec.exe',
    args: ['/x', productCode, '/passive', '/norestart'],
    successCodes: [0, 1641, 3010]
  });
});

test('converts an MSI maintenance command into an uninstall command', () => {
  const plan = createUninstallPlan({ UninstallString: `MsiExec.exe /I${productCode}` });
  assert.equal(plan.args[3], `MsiExec.exe /X${productCode}`);
  assert.deepEqual(plan.successCodes, [0, 1641, 3010]);
});

test('prefers the registered quiet command', () => {
  const plan = createUninstallPlan({
    QuietUninstallString: '"C:\\Apps\\Example\\uninstall.exe" /quiet',
    UninstallString: '"C:\\Apps\\Example\\uninstall.exe"'
  });
  assert.equal(plan.args[3], '"C:\\Apps\\Example\\uninstall.exe" /quiet');
  assert.deepEqual(plan.successCodes, [0]);
});

test('quotes an unquoted uninstall executable whose path contains spaces', () => {
  const plan = createUninstallPlan({
    UninstallString: 'C:\\Program Files\\Example App\\remove.exe /uninstall'
  });
  assert.equal(plan.args[3], '"C:\\Program Files\\Example App\\remove.exe" /uninstall');
});

test('runs an Inno Setup uninstaller quietly without allowing a restart', () => {
  const plan = createUninstallPlan({
    PSChildName: 'Old Classic Calculator for Windows 11 and Windows 10_is1',
    UninstallString: 'C:\\Program Files\\OldClassicCalc\\unins000.exe'
  });
  assert.equal(plan.file, 'C:\\Program Files\\OldClassicCalc\\unins000.exe');
  assert.deepEqual(plan.args, ['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART']);
});

test('does not modify vendor-provided quiet Inno Setup arguments', () => {
  const plan = createUninstallPlan({
    QuietUninstallString: '"C:\\Program Files\\Example\\unins000.exe" /SILENT /NORESTART',
    UninstallString: '"C:\\Program Files\\Example\\unins000.exe"'
  });
  assert.equal(plan.args[3], '"C:\\Program Files\\Example\\unins000.exe" /SILENT /NORESTART');
});

test('returns null when Windows provides no uninstall command', () => {
  assert.equal(createUninstallPlan({}), null);
});
