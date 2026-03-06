#!/usr/bin/env node
'use strict';

const http = require('http');
const net = require('net');

const TTYD_PORT = 7682;
const ingressPort = parseInt(process.argv[2]);

if (!ingressPort) {
  console.error('Usage: ttyd-proxy.js <ingress-port>');
  process.exit(1);
}

const ESC_INJECT = `<style>
  #esc-btn {
    position: fixed; bottom: 16px; right: 16px; z-index: 9999;
    padding: 12px 22px;
    background: rgba(50,50,50,0.88);
    color: #e0e0e0;
    border: 1px solid rgba(255,255,255,0.2);
    border-radius: 8px;
    font-size: 18px;
    font-family: sans-serif;
    cursor: pointer;
    user-select: none;
    -webkit-user-select: none;
    touch-action: manipulation;
  }
  #esc-btn:active { background: rgba(90,90,90,0.95); }
</style>
<button id="esc-btn">ESC</button>
<script>
(function () {
  // Intercept WebSocket to keep a reference for fallback input sending
  var _WS = window.WebSocket;
  var _ws = null;
  window.WebSocket = new Proxy(_WS, {
    construct: function(target, args) {
      var ws = new target(...args);
      _ws = ws;
      return ws;
    }
  });

  function sendEsc() {
    // Primary: dispatch keyboard event to xterm.js input element
    var el = document.querySelector('.xterm-helper-textarea') ||
             document.querySelector('.xterm textarea');
    if (el) {
      el.focus();
      ['keydown', 'keyup'].forEach(function(type) {
        el.dispatchEvent(new KeyboardEvent(type, {
          key: 'Escape', code: 'Escape', keyCode: 27, which: 27,
          bubbles: true, cancelable: true
        }));
      });
      return;
    }
    // Fallback: send ESC via ttyd WebSocket (JSON protocol)
    if (_ws && _ws.readyState === WebSocket.OPEN) {
      try { _ws.send(JSON.stringify({ type: 1, data: btoa('\x1b') })); } catch (e) {}
    }
  }

  var btn = document.getElementById('esc-btn');
  // touchend prevents 300ms click delay on mobile and avoids double-fire
  btn.addEventListener('touchend', function(e) {
    e.preventDefault();
    sendEsc();
  });
  btn.addEventListener('click', sendEsc);
})();
</script>
</body>`;

const server = http.createServer((req, res) => {
  const proxyHeaders = Object.assign({}, req.headers, {
    host: '127.0.0.1:' + TTYD_PORT,
    'accept-encoding': 'identity', // disable compression so we can inject HTML
  });

  const proxy = http.request({
    hostname: '127.0.0.1',
    port: TTYD_PORT,
    path: req.url,
    method: req.method,
    headers: proxyHeaders,
  }, (pRes) => {
    const ct = pRes.headers['content-type'] || '';
    if (ct.includes('text/html')) {
      const chunks = [];
      pRes.on('data', c => chunks.push(c));
      pRes.on('end', () => {
        let body = Buffer.concat(chunks).toString('utf8');
        body = body.includes('</body>')
          ? body.replace('</body>', ESC_INJECT)
          : body + ESC_INJECT;
        const outHeaders = Object.assign({}, pRes.headers, {
          'content-length': Buffer.byteLength(body),
          'content-type': 'text/html; charset=utf-8',
        });
        delete outHeaders['transfer-encoding'];
        res.writeHead(pRes.statusCode, outHeaders);
        res.end(body);
      });
    } else {
      res.writeHead(pRes.statusCode, pRes.headers);
      pRes.pipe(res);
    }
  });

  proxy.on('error', (e) => {
    console.error('Proxy error:', e.message);
    if (!res.headersSent) { res.writeHead(502); res.end('Bad Gateway'); }
  });
  req.pipe(proxy);
});

// Transparent WebSocket proxy (tunnel mode)
server.on('upgrade', (req, socket, head) => {
  const conn = net.connect(TTYD_PORT, '127.0.0.1', () => {
    let raw = `${req.method} ${req.url} HTTP/1.1\r\n`;
    for (const [k, v] of Object.entries(req.headers)) {
      raw += `${k}: ${v}\r\n`;
    }
    raw += '\r\n';
    conn.write(raw);
    if (head && head.length) conn.write(head);
    conn.pipe(socket);
    socket.pipe(conn);
  });
  conn.on('error', () => socket.destroy());
  socket.on('error', () => conn.destroy());
});

server.listen(ingressPort, '0.0.0.0', () => {
  console.log(`ttyd-proxy: ingress port ${ingressPort} → ttyd port ${TTYD_PORT}`);
});
