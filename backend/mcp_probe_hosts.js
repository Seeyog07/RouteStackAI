require('dotenv').config();
const crypto = require('crypto');

(async () => {
  const hosts = ['https://mcp.routestack.ai', 'https://evolvemcp.routestack.ai'];
  const apiKey = process.env.MCP_API_KEY;
  const apiSecret = process.env.MCP_API_SECRET;

  for (const base of hosts) {
    const ts = Math.floor(Date.now() / 1000);
    const nonce = crypto.randomUUID();
    const hmac = crypto.createHmac('sha256', apiSecret).update(`${apiKey}:${ts}:${nonce}`).digest('base64url');

    const partnerRes = await fetch(`${base}/mcp/auth/partner-token`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ apiKey, hmac, timestamp: ts, nonce }),
    });
    const partnerText = await partnerRes.text();

    let token = '';
    try { token = JSON.parse(partnerText).token || ''; } catch {}

    console.log(`=== ${base} partner-token: ${partnerRes.status}`);
    console.log(partnerText.slice(0, 200));

    const loginRes = await fetch(`${base}/mcp/auth/login`, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        Authorization: token ? `Bearer ${token}` : '',
        'x-partner-token': token,
        'x-api-key': apiKey,
      },
      body: JSON.stringify({}),
    });
    console.log(`=== ${base} login: ${loginRes.status}`);
    console.log((await loginRes.text()).slice(0, 260));

    const dataRes = await fetch(`${base}/mcp/hotel/search-destinations`, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        Authorization: token ? `Bearer ${token}` : '',
        'x-partner-token': token,
        'x-api-key': apiKey,
      },
      body: JSON.stringify({ type: 'DESTINATION', query: 'london' }),
    });
    console.log(`=== ${base} search-destinations: ${dataRes.status}`);
    console.log((await dataRes.text()).slice(0, 260));
  }
})();
