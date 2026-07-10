require('dotenv').config();
const crypto = require('crypto');

(async () => {
  const base = process.env.MCP_BASE_URL;
  const apiKey = process.env.MCP_API_KEY;
  const apiSecret = process.env.MCP_API_SECRET;
  const ts = Math.floor(Date.now() / 1000);
  const nonce = crypto.randomUUID();
  const hmac = crypto.createHmac('sha256', apiSecret).update(`${apiKey}:${ts}:${nonce}`).digest('base64url');
  const partnerRes = await fetch(`${base}/mcp/auth/partner-token`, {
    method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ apiKey, hmac, timestamp: ts, nonce })
  });
  const { token } = await partnerRes.json();
  const headers = { Authorization: `Bearer ${token}`, 'x-api-key': apiKey, 'x-partner-token': token };
  for (const method of ['GET', 'POST', 'OPTIONS']) {
    const res = await fetch(`${base}/mcp/auth/login`, {
      method,
      headers: { 'content-type': 'application/json', ...headers },
      body: method === 'POST' ? JSON.stringify({}) : undefined,
    });
    console.log(method, res.status, await res.text());
  }
})();
