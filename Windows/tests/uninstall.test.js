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

test('returns null when Windows provides no uninstall command', () => {
  assert.equal(createUninstallPlan({}), null);
});
