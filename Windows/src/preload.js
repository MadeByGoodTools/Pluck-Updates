const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('pluck', {
  snapshot: () => ipcRenderer.invoke('snapshot'),
  scanApps: () => ipcRenderer.invoke('scan-apps'),
  scanReclaimable: () => ipcRenderer.invoke('scan-reclaimable'),
  uninstall: ids => ipcRenderer.invoke('uninstall', ids),
  reclaim: ids => ipcRenderer.invoke('reclaim', ids),
  emptyTrash: () => ipcRenderer.invoke('empty-trash'),
  restartAsAdmin: () => ipcRenderer.invoke('restart-admin'),
  quit: () => ipcRenderer.send('quit')
});
