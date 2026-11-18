/**
 * Render web service for the Colab game starter.
 * Zero dependencies: serves ./public with the script as text/plain
 * so `curl -fsSL https://<service>.onrender.com/buffy-start.sh | sh` works.
 */
const http = require('http');
const fs = require('fs');
const path = require('path');

const PUBLIC = path.join(__dirname, 'public');
const PORT = process.env.PORT || 10000;

const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.sh': 'text/plain; charset=utf-8',
  '.txt': 'text/plain; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.ico': 'image/x-icon',
};

function send(res, status, body, type, head) {
  res.writeHead(status, {
    'content-type': type,
    'cache-control': 'no-store',
    'x-content-type-options': 'nosniff',
  });
  if (head || !body) return res.end();
  res.end(body);
}

const server = http.createServer((req, res) => {
  const head = req.method === 'HEAD';
  let pathname;
  try {
    pathname = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
  } catch {
    return send(res, 400, 'Bad request', 'text/plain; charset=utf-8', head);
  }

  if (pathname === '/healthz') return send(res, 200, 'ok', 'text/plain; charset=utf-8', head);

  // alias: /buffy-start.sh -> kaggle-start.sh
  if (pathname === '/buffy-start.sh') pathname = '/kaggle-start.sh';

  let rel = pathname.replace(/^\/+/, '');
  if (rel === '' || rel.endsWith('/')) rel += 'index.html';

  const file = path.join(PUBLIC, rel);
  if (!file.startsWith(PUBLIC + path.sep)) {
    return send(res, 403, 'Forbidden', 'text/plain; charset=utf-8', head);
  }

  fs.readFile(file, (err, data) => {
    if (err) return send(res, 404, 'Not found: ' + pathname, 'text/plain; charset=utf-8', head);
    const type = TYPES[path.extname(file).toLowerCase()] || 'application/octet-stream';
    send(res, 200, data, type, head);
  });
});

server.listen(PORT, '0.0.0.0', () => {
  console.log('listening on 0.0.0.0:' + PORT);
});
