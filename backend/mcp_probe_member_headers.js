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
    method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ apiKey, hmac, timestamp: ts, nonce }),
  });
  const { token } = await partnerRes.json();

  const variants = [
    ['x-member-token only', { 'x-member-token': token }],
    ['auth + x-member-token', { Authorization: `Bearer ${token}`, 'x-member-token': token }],
    ['all + x-member-token', { Authorization: `Bearer ${token}`, 'x-partner-token': token, 'x-api-key': apiKey, 'x-member-token': token }],
    ['member auth bearer', { Authorization: `Member ${token}`, 'x-partner-token': token, 'x-api-key': apiKey }],
    ['x-auth-token', { 'x-auth-token': token, 'x-partner-token': token, 'x-api-key': apiKey }],
    ['x-user-token', { 'x-user-token': token, 'x-partner-token': token, 'x-api-key': apiKey }],
  ];

  for (const [name, headers] of variants) {
    const res = await fetch(`${base}/mcp/hotel/search-destinations`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', ...headers },
      body: JSON.stringify({ type: 'DESTINATION', query: 'london' }),
    });
    const txt = await res.text();
    console.log(`--- ${name}: ${res.status}`);
    console.log(txt.slice(0, 260));
  }
})();
