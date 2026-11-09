import { workflow, node, trigger, expr } from '@n8n/workflow-sdk';

const webhook = trigger({
  type: 'n8n-nodes-base.webhook',
  version: 2.1,
  config: {
    name: 'Webhook',
    position: [0, 0],
    parameters: {
      httpMethod: 'POST',
      path: 'findaro-verify',
      responseMode: 'responseNode',
      authentication: 'none',
    },
  },
  output: [{ body: { sessionId: 'cs_test_123' } }],
});

const prepare = node({
  type: 'n8n-nodes-base.code',
  version: 2,
  config: {
    name: 'Prepare Retrieve',
    position: [260, 0],
    parameters: {
      mode: 'runOnceForAllItems',
      language: 'javaScript',
      jsCode: `const body = $input.item.json.body || $input.item.json;
const headers = $input.item.json.headers || {};
const sessionId = body.sessionId || body.session_id;
if (!sessionId) throw new Error('sessionId requerido');
const getEnv = (name) => {
  let v;
  try { v = $env[name]; } catch (e) { v = undefined; }
  if (v === undefined || v === null || v === '') {
    try { v = process.env[name]; } catch (e2) {}
  }
  return v;
};

// Validación de secreto compartido en cabecera
const expectedSecret = getEnv('FINDARO_GATEWAY_SECRET');
if (expectedSecret) {
  const secretHeader = headers['x-findaro-gateway-secret'] || headers['x-gateway-secret'];
  if (!secretHeader || secretHeader !== expectedSecret) {
    throw new Error('No autorizado: secreto de pasarela ausente o inválido');
  }
}

const stripeKey = getEnv('STRIPE_SK_MAIN');
if (!stripeKey) throw new Error('STRIPE_SK_MAIN ausente');
return [{ json: { sessionId, stripeKey } }];`,
    },
  },
  output: [{ sessionId: 'cs_test_123', stripeKey: 'sk_test_x' }],
});

const retrieve = node({
  type: 'n8n-nodes-base.httpRequest',
  version: 4.4,
  config: {
    name: 'Stripe Retrieve Session',
    position: [520, 0],
    parameters: {
      method: 'GET',
      url: expr('https://api.stripe.com/v1/checkout/sessions/{{ $json.sessionId }}'),
      sendHeaders: true,
      headerParameters: {
        parameters: [
          { name: 'Authorization', value: expr('Bearer {{ $json.stripeKey }}') },
        ],
      },
    },
  },
  output: [{
    id: 'cs_test_123',
    payment_status: 'paid',
    status: 'complete',
    customer_details: { email: 'a@b.com', name: 'Ana' },
    payment_intent: 'pi_123',
    metadata: { service_id: 'order-1', customer_email: 'a@b.com', customer_name: 'Ana' },
  }],
});

const format = node({
  type: 'n8n-nodes-base.code',
  version: 2,
  config: {
    name: 'Format Verify',
    position: [780, 0],
    parameters: {
      mode: 'runOnceForAllItems',
      language: 'javaScript',
      jsCode: `const s = $input.item.json;
const paid = s.payment_status === 'paid' || s.status === 'complete';
const email = s.customer_details?.email || s.customer_email || s.metadata?.customer_email || null;
const name = s.customer_details?.name || s.metadata?.customer_name || null;
const paymentIntent = typeof s.payment_intent === 'string' ? s.payment_intent : (s.payment_intent?.id || null);
const amountTotal = typeof s.amount_total === 'number' ? s.amount_total : null;
const currency = typeof s.currency === 'string' ? s.currency.toLowerCase() : null;
const appId = s.metadata?.app_id || s.metadata?.tradingAppSlug || null;
return [{ json: {
  success: true,
  data: {
    paid,
    sessionId: s.id,
    email,
    name,
    paymentIntent,
    orderId: s.metadata?.service_id || s.metadata?.purchase_id || null,
    amountTotal,
    currency,
    appId,
  }
} }];`,
    },
  },
  output: [{ success: true, data: { paid: true, sessionId: 'cs_test_123', email: 'a@b.com', name: 'Ana', paymentIntent: 'pi_123', orderId: 'order-1', amountTotal: 3900, currency: 'usd', appId: 'findaro' } }],
});

const respond = node({
  type: 'n8n-nodes-base.respondToWebhook',
  version: 1.5,
  config: {
    name: 'Respond',
    position: [1040, 0],
    parameters: {
      respondWith: 'json',
      responseBody: expr('{{ $json }}'),
    },
  },
  output: [{ success: true }],
});

export default workflow('findaro-verify', 'Findaro - Verify Checkout')
  .add(webhook)
  .to(prepare)
  .to(retrieve)
  .to(format)
  .to(respond);
