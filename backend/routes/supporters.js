const express = require('express');
const router = express.Router();
const Stripe = require('stripe');
const { query } = require('../db');

const stripe = Stripe(process.env.STRIPE_SECRET_KEY);

// POST /supporters/checkout
// Creates a Stripe Checkout Session for the one-time $5 Dev Supporter payment.
// Optionally accepts { email } to pre-fill Stripe's email field.
router.post('/checkout', async (req, res) => {
  try {
    const email = typeof req.body?.email === 'string' ? req.body.email.trim() : undefined;
    const tier = req.body?.tier === 'founder' ? 'founder' : 'dev_supporter';
    const isFounder = tier === 'founder';
    const session = await stripe.checkout.sessions.create({
      ui_mode: 'hosted_page',
      mode: 'payment',
      billing_address_collection: 'auto',
      phone_number_collection: { enabled: false },
      automatic_tax: { enabled: false },
      allow_promotion_codes: false,
      submit_type: 'auto',
      integration_identifier: 'hosted_web_0001',
      origin_context: 'web',
      line_items: [
        {
          price_data: {
            currency: 'usd',
            unit_amount: isFounder ? 1000 : 500,
            product_data: {
              name: isFounder ? 'Founder – Kuvacult' : 'Dev Supporter – Kuvacult',
              description: isFounder
                ? 'One-time Founder upgrade. Animated borders, extra customisation, and everything in Dev Supporter.'
                : 'One-time lifetime supporter. Deeply customisable profiles coming first to supporters.',
            },
          },
          quantity: 1,
        },
      ],
      customer_email: email || undefined,
      metadata: { tier },
      success_url: `${process.env.APP_URL}/supporters/thanks`,
      cancel_url: `${process.env.APP_URL}/supporters/cancel`,
    });
    res.json({ url: session.url });
  } catch (err) {
    console.error('supporters/checkout error:', err.message);
    res.status(500).json({ error: 'Failed to create checkout session' });
  }
});

// POST /supporters/webhook
// Stripe webhook — receives checkout.session.completed and records the supporter's email.
// Requires raw body (mounted in server.js before express.json()).
router.post('/webhook', async (req, res) => {
  const sig = req.headers['stripe-signature'];
  let event;
  try {
    event = stripe.webhooks.constructEvent(req.body, sig, process.env.STRIPE_WEBHOOK_SECRET);
  } catch (err) {
    console.error('Stripe webhook signature error:', err.message);
    return res.status(400).send(`Webhook Error: ${err.message}`);
  }

  if (event.type === 'checkout.session.completed') {
    const session = event.data.object;
    const email = session.customer_details?.email || session.customer_email;
    const tier = session.metadata?.tier || 'dev_supporter';
    const isFounder = tier === 'founder';
    if (email) {
      try {
        await query(
          `INSERT INTO supporters (email, stripe_session_id)
           VALUES ($1, $2)
           ON CONFLICT (email) DO NOTHING`,
          [email.toLowerCase(), session.id]
        );
        await query(
          `UPDATE users SET is_supporter = TRUE${isFounder ? ', is_founder = TRUE' : ''} WHERE lower(email) = $1`,
          [email.toLowerCase()]
        );
      } catch (err) {
        console.error('supporters webhook DB error:', err.message);
      }
    }
  }

  res.json({ received: true });
});

const _thanksHtml = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Thanks for supporting Kuvacult</title>
<link rel="icon" href="assets/sun.png">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Instrument+Serif:ital@0;1&family=JetBrains+Mono:wght@400&display=swap" rel="stylesheet">
<style>
  html, body { margin: 0; height: 100%; background: #0A0A0A; }
  body { display: flex; align-items: center; justify-content: center; overflow: hidden; color: #f3e4cf; font-family: 'JetBrains Mono', ui-monospace, monospace; -webkit-font-smoothing: antialiased; }
  @keyframes spin { to { transform: rotate(360deg); } }
  @keyframes breath { 0%, 100% { opacity: .55; } 50% { opacity: .95; } }
  @keyframes boil { 0% { filter: url(#a); } 33% { filter: url(#b); } 66% { filter: url(#c); } 100% { filter: url(#a); } }
  .wrap { position: relative; display: flex; flex-direction: column; align-items: center; gap: 22px; text-align: center; padding: 24px; }
  .glow { position: fixed; left: 50%; top: 40%; width: 640px; height: 640px; margin: -320px 0 0 -320px; border-radius: 50%; pointer-events: none;
          background: radial-gradient(circle, rgba(255,166,71,.16) 0%, rgba(255,140,43,.04) 40%, rgba(0,0,0,0) 68%); animation: breath 6s ease-in-out infinite; }
  .mark { position: relative; width: 180px; height: 180px; display: flex; align-items: center; justify-content: center; }
  .mark svg { position: absolute; inset: 0; animation: spin 80s linear infinite; }
  .mark img { position: relative; width: 104px; height: 104px; animation: boil 420ms steps(1) infinite; }
  h1 { margin: 0; font-family: 'Instrument Serif', serif; font-weight: 400; font-size: clamp(36px, 6vw, 52px); line-height: 1; color: #f7ecdc; }
  h1 em { color: #E9C468; }
  p { margin: 0; max-width: 470px; font-size: 13px; line-height: 1.85; color: rgba(243,228,207,.72); }
  @media (prefers-reduced-motion: reduce) { * { animation: none !important; } }
</style>
</head>
<body>
<svg width="0" height="0" style="position:absolute" aria-hidden="true">
  <filter id="a" x="-20%" y="-20%" width="140%" height="140%"><feTurbulence type="fractalNoise" baseFrequency=".06" numOctaves="3" seed="3" result="n"/><feDisplacementMap in="SourceGraphic" in2="n" scale="3" xChannelSelector="R" yChannelSelector="G"/></filter>
  <filter id="b" x="-20%" y="-20%" width="140%" height="140%"><feTurbulence type="fractalNoise" baseFrequency=".06" numOctaves="3" seed="11" result="n"/><feDisplacementMap in="SourceGraphic" in2="n" scale="3" xChannelSelector="R" yChannelSelector="G"/></filter>
  <filter id="c" x="-20%" y="-20%" width="140%" height="140%"><feTurbulence type="fractalNoise" baseFrequency=".06" numOctaves="3" seed="19" result="n"/><feDisplacementMap in="SourceGraphic" in2="n" scale="3" xChannelSelector="R" yChannelSelector="G"/></filter>
</svg>
<div class="glow"></div>
<main class="wrap">
  <div class="mark">
    <svg viewBox="0 0 180 180" width="180" height="180" aria-hidden="true"><g fill="none" stroke="#E3BE5E" stroke-linecap="round" style="animation: boil 420ms steps(1) infinite"><circle cx="90" cy="90" r="86" stroke-width="1" opacity=".4"/><circle cx="90" cy="90" r="74" stroke-width="1.3" stroke-dasharray="2 8" opacity=".55"/></g></svg>
    <img src="assets/sun.png" alt="Kuvacult">
  </div>
  <h1>Thanks for supporting <em>Kuvacult.</em></h1>
  <p>Your support means a lot. Close this page and return to the app — your supporter badge will show up shortly.</p>
</main>
</body>
</html>`;

const path = require('path');
const fs   = require('fs');

router.get('/thanks', (_req, res) => {
  res.send(_thanksHtml);
});

router.get('/assets/sun.png', (_req, res) => {
  const sunPath = path.join(__dirname, '../../assets/brand/sun.png');
  if (fs.existsSync(sunPath)) {
    res.sendFile(sunPath);
  } else {
    res.status(404).end();
  }
});

router.get('/cancel', (_req, res) => {
  res.send(`<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Cancelled – Kuvacult</title><style>html,body{margin:0;height:100%;background:#0A0A0A}body{display:flex;align-items:center;justify-content:center;font-family:'JetBrains Mono',ui-monospace,monospace;color:#f3e4cf;text-align:center;padding:24px}.wrap{max-width:420px}h1{font-family:'Instrument Serif',serif;font-weight:400;font-size:clamp(28px,5vw,44px);color:#f7ecdc;margin:0 0 16px}p{font-size:13px;line-height:1.85;color:rgba(243,228,207,.72);margin:0}</style><link href="https://fonts.googleapis.com/css2?family=Instrument+Serif:ital@0;1&family=JetBrains+Mono:wght@400&display=swap" rel="stylesheet"></head><body><main class="wrap"><h1>No worries.</h1><p>You can become a supporter any time from the app. Close this page to return to Kuvacult.</p></main></body></html>`);
});

module.exports = router;
