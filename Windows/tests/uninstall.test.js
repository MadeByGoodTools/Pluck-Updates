'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { createUninstallPlan, createUninstallPlans, parseWindowsArguments } = require('../src/uninstall');

const productCode = '{12345678-1234-1234-1234-123456789ABC}';

test('builds quiet and visible MSI plans from the product code', () => {
  const plans = createUninstallPlans({ WindowsInstaller: 1, PSChildName: productCode });
  assert.equal(plans.length, 2);
  assert.deepEqual(plans[0].args, ['/x', productCode, '/passive', '/norestart']);
  assert.deepEqual(plans[0].successCodes, [0, 1641, 3010]);
  assert.equal(plans[1].quiet, false);
});

test('converts an MSI maintenance command into a direct uninstall command', () => {
  const plan = createUninstallPlan({ UninstallString: `MsiExec.exe /I${productCode}` });
  assert.equal(plan.file.toLowerCase(), 'msiexec.exe');
  assert.deepEqual(plan.args, [`/X${productCode}`]);
  assert.deepEqual(plan.successCodes, [0, 1641, 3010]);
});

test('prefers the registered quiet command and retains a visible fallback', () => {
  const plans = createUninstallPlans({
    QuietUninstallString: '"C:\\Apps\\Example\\uninstall.exe" /quiet',
    UninstallString: '"C:\\Apps\\Example\\uninstall.exe"'
  });
  assert.deepEqual(plans[0].args, ['/quiet']);
  assert.equal(plans[0].quiet, true);
  assert.deepEqual(plans[1].args, []);
  assert.equal(plans[1].quiet, false);
});

test('runs an unquoted executable path with spaces directly', () => {
  const plan = createUninstallPlan({ UninstallString: 'C:\\Program Files\\Example App\\remove.exe /uninstall' });
  assert.equal(plan.file, 'C:\\Program Files\\Example App\\remove.exe');
  assert.deepEqual(plan.args, ['/uninstall']);
});

test('runs the reported Old Classic Calculator Inno uninstaller quietly then visibly', () => {
  const plans = createUninstallPlans({
    PSChildName: 'Old Classic Calculator for Windows 11 and Windows 10_is1',
    UninstallString: 'C:\\Program Files\\OldClassicCalc\\unins000.exe'
  });
  assert.equal(plans[0].file, 'C:\\Program Files\\OldClassicCalc\\unins000.exe');
  assert.deepEqual(plans[0].args, ['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART']);
  assert.deepEqual(plans[1].args, []);
});

test('recognizes NSIS uninstallers and adds a visible fallback', () => {
  const plans = createUninstallPlans({ UninstallString: '"C:\\Apps\\Example\\Uninstall.exe"' });
  assert.deepEqual(plans[0].args, ['/S']);
  assert.equal(plans[0].label, 'NSIS quiet removal');
  assert.deepEqual(plans[1].args, []);
});

test('recognizes Squirrel commands and appends the silent switch', () => {
  const plans = createUninstallPlans({ UninstallString: '"C:\\Apps\\Example\\Update.exe" --uninstall' });
  assert.deepEqual(plans[0].args, ['--uninstall', '--silent']);
  assert.equal(plans[0].label, 'Squirrel quiet removal');
});

test('builds an MSIX removal plan without interpolating quotes', () => {
  const plan = createUninstallPlan({ Kind: 'Appx', PackageFullName: "Vendor.App_1.0_x64__abc'def" });
  assert.equal(plan.file, 'powershell.exe');
  assert.match(plan.args.at(-1), /abc''def/);
});

test('parses quoted Windows command arguments', () => {
  assert.deepEqual(parseWindowsArguments('/remove "C:\\Data Files\\state.json" /quiet'), [
    '/remove', 'C:\\Data Files\\state.json', '/quiet'
  ]);
});

test('returns null when Windows provides no uninstall command', () => {
  assert.equal(createUninstallPlan({}), null);
});
