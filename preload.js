const { contextBridge, ipcRenderer } = require('electron');

// Named "taskIsland" (not "island") so it doesn't collide with the #island element on window.
contextBridge.exposeInMainWorld('taskIsland', {
  on: (channel, fn) => ipcRenderer.on(channel, (_e, data) => fn(data)),
  answer: (id, answer) => ipcRenderer.send('answer', { id, answer }),
  setClickable: on => ipcRenderer.send('clickable', on),
});
