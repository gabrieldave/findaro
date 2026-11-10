import { workflow, node, trigger, expr } from '@n8n/workflow-sdk';

const webhook = trigger({
  type: 'n8n-nodes-base.webhook',
  version: 2.1,
  config: {
    name: 'Webhook',
    position: [0, 0],
    parameters: {
      httpMethod: 'POST',
      path: 'findaro-payment',
      responseMode: 'responseNode',
      authentication: 'none',
    },
  },
  output: [{
    body: {
      appId: 'findaro',
      event: 'payment.create_checkout_session',
      data: {
        amount: 59,
        currency: 'usd',
        serviceTitle: 'FINDARO',
        customerEmail: 'test@example.com',
        successUrl: 'https://findaro.iareal.net/gracias?session_id={CHECKOUT_SESSION_ID}',
        cancelUrl: 'https://findaro.iareal.net/comprar',
      },
    },
  }],
});

const parseRequest = node({
  type: 'n8n-nodes-base.code',
  version: 2,
  config: {
    name: 'Parse Request',
    position: [260, 0],
    parameters: {
      mode: 'runOnceForAllItems',
      language: 'javaScript',
      jsCode: `const body = $input.item.json.body || $input.item.json;
const headers = $input.item.json.headers || {};
if (!body.appId) throw new Error('appId es requerido');
if (!body.event) throw new Error('event es requerido');
if (!body.data) throw new Error('data es requerido');
if (body.appId !== 'findaro') throw new Error('appId no permitido');
if (body.event !== 'payment.create_checkout_session') throw new Error('evento no soportado');

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
if (!stripeKey || String(stripeKey).includes('REEMPLAZA')) {
  throw new Error('STRIPE_SK_MAIN ausente en n8n');
}
return [{ json: { appId: body.appId, data: body.data, stripeKey } }];`,
    },
  },
  output: [{
    appId: 'findaro',
    stripeKey: 'sk_test_x',
    data: {
      amount: 59,
      currency: 'usd',
      serviceTitle: 'FINDARO',
      customerEmail: 'test@example.com',
      successUrl: 'https://findaro.iareal.net/gracias?session_id={CHECKOUT_SESSION_ID}',
      cancelUrl: 'https://findaro.iareal.net/comprar',
    },
  }],
});

const prepareSession = node({
  type: 'n8n-nodes-base.code',
  version: 2,
  config: {
    name: 'Prepare Stripe Session',
    position: [520, 0],
    parameters: {
      mode: 'runOnceForAllItems',
      language: 'javaScript',
      jsCode: `const input = $input.item.json;
const data = input.data || {};

// Validar y fijar importe en servidor según tier (incluye precios promo y post-promo con/sin referido)
const tier = data.tier === 'family' ? 'family' : 'personal';
const lang = data.lang === 'en' ? 'en' : 'es';
const validAmounts = tier === 'family' ? [59, 53, 79, 73] : [39, 35, 59, 55];
const requestedAmount = Number(data.amount);
if (!validAmounts.includes(requestedAmount)) {
  throw new Error('Importe inválido para el tier ' + tier + ': ' + requestedAmount);
}

const amount = Math.round(requestedAmount * 100);
const currency = (data.currency || 'usd').toLowerCase();
if (currency !== 'usd') throw new Error('Moneda no soportada: ' + currency);

const defaultTitle = lang === 'en'
  ? (tier === 'family' ? 'FINDARO — Family Plan (5 Macs)' : 'FINDARO — Personal Plan (2 Macs)')
  : (tier === 'family' ? 'FINDARO — Plan Familiar (5 Macs)' : 'FINDARO — Plan Personal (2 Macs)');
const title = data.serviceTitle || defaultTitle;
const description = data.serviceDescription || (lang === 'en' ? 'Lifetime license with automatic updates' : 'Licencia de por vida con actualizaciones');
const formParams = [];
formParams.push('payment_method_types[]=card');
formParams.push('mode=payment');
formParams.push('locale=' + lang);
formParams.push('success_url=' + encodeURIComponent(data.successUrl));
formParams.push('cancel_url=' + encodeURIComponent(data.cancelUrl));
if (data.customerEmail) formParams.push('customer_email=' + encodeURIComponent(data.customerEmail));
formParams.push('line_items[0][price_data][currency]=' + currency);
formParams.push('line_items[0][price_data][product_data][name]=' + encodeURIComponent(title));
formParams.push('line_items[0][price_data][product_data][description]=' + encodeURIComponent(description));
formParams.push('line_items[0][price_data][unit_amount]=' + amount);
formParams.push('line_items[0][quantity]=1');
formParams.push('metadata[app_id]=findaro');
formParams.push('metadata[tier]=' + tier);
formParams.push('metadata[lang]=' + lang);
if (data.serviceId) formParams.push('metadata[service_id]=' + encodeURIComponent(String(data.serviceId)));
if (data.customerEmail) formParams.push('metadata[customer_email]=' + encodeURIComponent(data.customerEmail));
if (data.customerName) formParams.push('metadata[customer_name]=' + encodeURIComponent(data.customerName));
if (data.metadata && data.metadata.purchaseId) {
  formParams.push('metadata[purchase_id]=' + encodeURIComponent(String(data.metadata.purchaseId)));
}
return [{ json: { stripeKey: input.stripeKey, formBody: formParams.join('&') } }];`,
    },
  },
  output: [{ stripeKey: 'sk_test_x', formBody: 'mode=payment' }],
});

const stripeCreate = node({
  type: 'n8n-nodes-base.httpRequest',
  version: 4.4,
  config: {
    name: 'Stripe Create Session',
    position: [780, 0],
    parameters: {
      method: 'POST',
      url: 'https://api.stripe.com/v1/checkout/sessions',
      sendHeaders: true,
      headerParameters: {
        parameters: [
          { name: 'Authorization', value: expr('Bearer {{ $json.stripeKey }}') },
        ],
      },
      sendBody: true,
      contentType: 'raw',
      rawContentType: 'application/x-www-form-urlencoded',
      body: expr('{{ $json.formBody }}'),
    },
  },
  output: [{ id: 'cs_test_123', url: 'https://checkout.stripe.com/c/pay/cs_test_123' }],
});

const formatSuccess = node({
  type: 'n8n-nodes-base.code',
  version: 2,
  config: {
    name: 'Format Success',
    position: [1040, 0],
    parameters: {
      mode: 'runOnceForAllItems',
      language: 'javaScript',
      jsCode: `const stripeResponse = $input.item.json;
let responseData = stripeResponse;
if (typeof stripeResponse === 'string') {
  try { responseData = JSON.parse(stripeResponse); } catch (e) { responseData = stripeResponse; }
}
const url = responseData.url || responseData.object?.url;
const sessionId = responseData.id || responseData.object?.id;
if (!url || !sessionId) throw new Error('Respuesta invalida de Stripe');
return [{ json: { success: true, data: { url, sessionId } } }];`,
    },
  },
  output: [{ success: true, data: { url: 'https://checkout.stripe.com/c/pay/cs_test_123', sessionId: 'cs_test_123' } }],
});

const successResponse = node({
  type: 'n8n-nodes-base.respondToWebhook',
  version: 1.5,
  config: {
    name: 'Success Response',
    position: [1300, 0],
    parameters: {
      respondWith: 'json',
      responseBody: expr('{{ $json }}'),
    },
  },
  output: [{ success: true }],
});

export default workflow('findaro-payment', 'Findaro - Payment Checkout')
  .add(webhook)
  .to(parseRequest)
  .to(prepareSession)
  .to(stripeCreate)
  .to(formatSuccess)
  .to(successResponse);
