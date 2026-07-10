require('dotenv').config();
const crypto = require('crypto');

async function getPartnerToken() {
  const base = process.env.MCP_BASE_URL;
  const apiKey = process.env.MCP_API_KEY;
  const apiSecret = process.env.MCP_API_SECRET;
  const ts = Math.floor(Date.now() / 1000);
  const nonce = crypto.randomUUID();
  const hmac = crypto.createHmac('sha256', apiSecret).update(`${apiKey}:${ts}:${nonce}`).digest('base64url');
  const res = await fetch(`${base}/mcp/auth/partner-token`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ apiKey, hmac, timestamp: ts, nonce }),
  });
  return (await res.json()).token;
}

(async () => {
  const base = process.env.MCP_BASE_URL;
  const apiKey = process.env.MCP_API_KEY;
  const partner = await getPartnerToken();

  const attempts = [
    ['no-auth empty-body', {}, {}],
    ['no-auth apiKey body', {}, { apiKey }],
    ['bearer-partner empty-body', { Authorization: `Bearer ${partner}` }, {}],
    ['bearer-partner apiKey', { Authorization: `Bearer ${partner}` }, { apiKey }],
    ['partner headers apiKey', { Authorization: `Bearer ${partner}`, 'x-partner-token': partner, 'x-api-key': apiKey }, { apiKey }],
    ['partner headers email/pass placeholders', { Authorization: `Bearer ${partner}`, 'x-partner-token': partner, 'x-api-key': apiKey }, { email: 'test@example.com', password: 'x' }],
  ];

  for (const [name, headers, body] of attempts) {
    const res = await fetch(`${base}/mcp/auth/login`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', ...headers },
      body: JSON.stringify(body),
    });
    const txt = await res.text();
    console.log(`--- ${name}: ${res.status}`);
    console.log(txt);
  }
})();
