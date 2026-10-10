import type { HAArea, HADevice, HAConfigEntry } from './types.js';

const SUPERVISOR_TOKEN = process.env.SUPERVISOR_TOKEN || '';
const WS_URL = 'ws://supervisor/core/websocket';
const WS_TIMEOUT_MS = 30_000;

// The registries are only available over the Home Assistant websocket API;
// the REST API has no endpoint for them (a POST to /core/api answers 405).
// Each call opens a connection through the Supervisor proxy, authenticates
// with the Supervisor token, sends one command and closes again. The tools
// are called rarely, so a persistent connection is not worth it. Node.js 22
// and newer have a global WebSocket.
function wsCommand<T>(type: string, extraFields: Record<string, unknown> = {}): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const ws = new WebSocket(WS_URL);
    const finish = (error?: string, result?: T) => {
      clearTimeout(timer);
      ws.close();
      if (error) reject(new Error(`HA websocket command ${type} failed: ${error}`));
      else resolve(result as T);
    };
    const timer = setTimeout(() => finish(`no answer within ${WS_TIMEOUT_MS / 1000} s`), WS_TIMEOUT_MS);

    ws.addEventListener('message', event => {
      const msg = JSON.parse(String(event.data));
      if (msg.type === 'auth_required') {
        ws.send(JSON.stringify({ type: 'auth', access_token: SUPERVISOR_TOKEN }));
      } else if (msg.type === 'auth_ok') {
        ws.send(JSON.stringify({ id: 1, type, ...extraFields }));
      } else if (msg.type === 'auth_invalid') {
        finish(`authentication failed: ${msg.message}`);
      } else if (msg.type === 'result' && msg.id === 1) {
        if (msg.success) finish(undefined, msg.result as T);
        else finish(`${msg.error?.code}: ${msg.error?.message}`);
      }
    });
    ws.addEventListener('error', () => finish(`cannot connect to ${WS_URL}`));
    // A promise settles only once, so this does nothing after a result
    ws.addEventListener('close', () => finish('connection closed before the result'));
  });
}

// Errors are not caught here: the tool call then reports them, instead of an
// empty list that looks like a Home Assistant without areas or devices.

export async function listAreas(): Promise<HAArea[]> {
  return wsCommand<HAArea[]>('config/area_registry/list');
}

export async function searchDevices(query?: string): Promise<HADevice[]> {
  const devices = await wsCommand<HADevice[]>('config/device_registry/list');
  if (!query) return devices;

  const q = query.toLowerCase();
  return devices.filter(d =>
    (d.name || '').toLowerCase().includes(q) ||
    (d.name_by_user || '').toLowerCase().includes(q) ||
    (d.manufacturer || '').toLowerCase().includes(q) ||
    (d.model || '').toLowerCase().includes(q)
  );
}

export async function getConfigEntries(): Promise<HAConfigEntry[]> {
  return wsCommand<HAConfigEntry[]>('config_entries/get');
}
