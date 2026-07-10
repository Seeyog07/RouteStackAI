require('dotenv').config();
const crypto = require('crypto');

const base = process.env.MCP_BASE_URL;
const apiKey = process.env.MCP_API_KEY;
const apiSecret = process.env.MCP_API_SECRET;

(async () => {
  const ts = Math.floor(Date.now() / 1000);
  const nonce = crypto.randomUUID();
  const hmac = crypto
    .createHmac('sha256', apiSecret)
    .update(`${apiKey}:${ts}:${nonce}`)
    .digest('base64url');

  const authRes = await fetch(`${base}/mcp/auth/partner-token`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ apiKey, hmac, timestamp: ts, nonce }),
  });

  const authText = await authRes.text();
  console.log('auth status', authRes.status);
  let token = '';
  try {
    const authJson = JSON.parse(authText);
    token = String(authJson.token || '');
    console.log('auth keys', Object.keys(authJson));
    console.log('token prefix', token.slice(0, 24));
  } catch {
    console.log('auth parse fail', authText.slice(0, 300));
    return;
  }

  const reqBody = { type: 'DESTINATION', query: 'london' };
  const variants = [
    ['Authorization only', { Authorization: `Bearer ${token}` }, reqBody],
    ['x-partner-token only', { 'x-partner-token': token }, reqBody],
    ['Auth + x-api-key', { Authorization: `Bearer ${token}`, 'x-api-key': apiKey }, reqBody],
    ['x-partner-token + x-api-key', { 'x-partner-token': token, 'x-api-key': apiKey }, reqBody],
    ['all headers', { Authorization: `Bearer ${token}`, 'x-partner-token': token, 'x-api-key': apiKey }, reqBody],
    ['all headers + body token', { Authorization: `Bearer ${token}`, 'x-partner-token': token, 'x-api-key': apiKey }, { ...reqBody, token }],
    ['all headers + bearer token value', { Authorization: `Bearer ${token}`, 'x-partner-token': `Bearer ${token}`, 'x-api-key': apiKey }, reqBody],
    ['all headers + source PARTNER', { Authorization: `Bearer ${token}`, 'x-partner-token': token, 'x-api-key': apiKey }, { ...reqBody, source: 'PARTNER' }],
  ];

  for (const [name, headers, body] of variants) {
    const res = await fetch(`${base}/mcp/hotel/search-destinations`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', ...headers },
      body: JSON.stringify(body),
    });
    const text = await res.text();
    console.log(`--- ${name}: ${res.status}`);
    console.log(text.slice(0, 240));
  }
})();
