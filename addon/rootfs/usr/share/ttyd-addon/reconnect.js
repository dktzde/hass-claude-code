/*
 * Claude Code add-on: reconnect the web terminal on its own.
 *
 * The ttyd service adds this script to the <head> of ttyd's page, before
 * ttyd's own code, so it sees every WebSocket that ttyd opens.
 *
 * Home Assistant lets the browser into the add-on with an Ingress session
 * (cookie "ingress_session"). The Home Assistant page around the terminal
 * renews it once a minute, but only while that page runs. A sleeping laptop,
 * a phone in the background or a frozen tab lets the session expire. When
 * the terminal's connection breaks, ttyd 1.7.7 shows "Press ⏎ to Reconnect"
 * and makes exactly one attempt with the expired cookie: the Supervisor
 * answers 401 ("No valid ingress session" in its log), ttyd turns off its
 * own reconnect and shows the same text again. Only reloading Home Assistant
 * created a new session.
 *
 * This script waits until the page is visible, then asks ttyd's /token
 * endpoint (same address as ttyd uses) whether the add-on can be reached:
 *
 * - 200: the session is valid. Reload the terminal page; tmux attaches the
 *   running session again.
 * - 401 or 403: the session expired. Reload Home Assistant (the top page),
 *   which creates a new session, as a manual reload does. At most once a
 *   minute; in between keep asking, because Home Assistant may renew the
 *   session by itself.
 * - anything else (add-on or Home Assistant restarting, network down): ask
 *   again after 2 s, 4 s, 8 s ... up to 30 s.
 *
 * ttyd's own reconnect and "Press ⏎" stay as they are; this script only acts
 * when the connection is still down after a moment.
 */
(function () {
  'use strict';

  var NativeWebSocket = window.WebSocket;
  if (typeof NativeWebSocket !== 'function') {
    return;
  }

  // Wait after a lost connection before checking, so ttyd's own reconnect
  // can finish first
  var FIRST_CHECK = 2000;
  // Backoff between checks while the add-on cannot be reached
  var RETRY_MIN = 2000;
  var RETRY_MAX = 30000;
  // Reload limits, counted per browser tab (sessionStorage)
  var WINDOW = 60000;
  var MAX_TERMINAL_RELOADS = 3;
  var MAX_TOP_RELOADS = 1;

  var current = null; // ttyd's latest WebSocket
  var timer = null;
  var checking = false;
  var delay = RETRY_MIN;

  function log(message) {
    console.log('[claude-code] ' + message);
  }

  // ttyd's address for the token, see html/src/components/app.tsx of ttyd
  function tokenUrl() {
    var path = window.location.pathname.replace(/[/]+$/, '');
    return window.location.protocol + '//' + window.location.host + path + '/token';
  }

  function isTtyd(protocols) {
    return protocols === 'tty' ||
      (Array.isArray(protocols) && protocols.indexOf('tty') >= 0);
  }

  function lost() {
    return current !== null &&
      (current.readyState === NativeWebSocket.CLOSING ||
       current.readyState === NativeWebSocket.CLOSED);
  }

  function schedule(ms) {
    if (timer !== null) {
      clearTimeout(timer);
    }
    timer = setTimeout(check, ms);
  }

  function retry() {
    schedule(delay);
    delay = Math.min(delay * 2, RETRY_MAX);
  }

  // true while fewer than max reloads of this kind happened in the last
  // minute; records the reload. Without sessionStorage: always true for the
  // terminal (no loop protection), false for the top page (no reload).
  function allowReload(key, max) {
    var now = Date.now();
    var times;
    try {
      times = JSON.parse(window.sessionStorage.getItem(key) || '[]');
      if (!Array.isArray(times)) {
        times = [];
      }
      times = times.filter(function (t) {
        return typeof t === 'number' && now - t < WINDOW;
      });
      if (times.length >= max) {
        return false;
      }
      times.push(now);
      window.sessionStorage.setItem(key, JSON.stringify(times));
      return true;
    } catch (e) {
      return key === 'claudeCodeTerminalReloads';
    }
  }

  function reloadTerminal() {
    if (!allowReload('claudeCodeTerminalReloads', MAX_TERMINAL_RELOADS)) {
      log('the terminal was reloaded ' + MAX_TERMINAL_RELOADS +
          ' times within a minute; press Enter or reload the page');
      return;
    }
    log('connection lost, reloading the terminal');
    window.location.reload();
  }

  function reloadHomeAssistant() {
    var top = null;
    try {
      // Throws when the top page has another origin
      if (window.top !== window && window.top.location.href) {
        top = window.top;
      }
    } catch (e) {
      top = null;
    }
    if (top === null) {
      // Opened without Home Assistant around it, or in a foreign page:
      // nothing here can renew the session
      retry();
      return;
    }
    if (!allowReload('claudeCodeTopReloads', MAX_TOP_RELOADS)) {
      // Home Assistant renews the session once a minute while it runs
      retry();
      return;
    }
    log('Ingress session expired, reloading Home Assistant');
    top.location.reload();
  }

  function check() {
    timer = null;
    if (!lost() || checking) {
      return;
    }
    if (document.visibilityState === 'hidden') {
      // visibilitychange starts the next check
      return;
    }
    checking = true;
    fetch(tokenUrl(), { cache: 'no-store', credentials: 'same-origin' })
      .then(function (response) {
        checking = false;
        if (!lost()) {
          return;
        }
        if (response.ok) {
          reloadTerminal();
        } else if (response.status === 401 || response.status === 403) {
          reloadHomeAssistant();
        } else {
          retry();
        }
      }, function () {
        checking = false;
        retry();
      });
  }

  function checkNow() {
    if (lost()) {
      delay = RETRY_MIN;
      schedule(0);
    }
  }

  function watch(socket) {
    current = socket;
    socket.addEventListener('open', function () {
      if (socket === current) {
        delay = RETRY_MIN;
        if (timer !== null) {
          clearTimeout(timer);
          timer = null;
        }
      }
    });
    socket.addEventListener('close', function () {
      if (socket === current) {
        delay = RETRY_MIN;
        schedule(FIRST_CHECK);
      }
    });
  }

  class ClaudeCodeWebSocket extends NativeWebSocket {
    constructor(url, protocols) {
      if (protocols === undefined) {
        super(url);
      } else {
        super(url, protocols);
      }
      if (isTtyd(protocols)) {
        watch(this);
      }
    }
  }

  window.WebSocket = ClaudeCodeWebSocket;

  document.addEventListener('visibilitychange', function () {
    if (document.visibilityState === 'visible') {
      checkNow();
    }
  });
  window.addEventListener('online', checkNow);
})();
