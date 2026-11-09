export const SPANISH_COUNTRIES = new Set([
  'ES', // España
  'MX', // México
  'AR', // Argentina
  'CO', // Colombia
  'CL', // Chile
  'PE', // Perú
  'VE', // Venezuela
  'EC', // Ecuador
  'GT', // Guatemala
  'CU', // Cuba
  'BO', // Bolivia
  'DO', // República Dominicana
  'HN', // Honduras
  'PY', // Paraguay
  'SV', // El Salvador
  'NI', // Nicaragua
  'CR', // Costa Rica
  'PA', // Panamá
  'UY', // Uruguay
  'PR', // Puerto Rico
  'GQ', // Guinea Ecuatorial
]);

export function detectLanguageFromHeaders(headers: Headers, cookieLang?: string | null, explicitLang?: string | null): 'en' | 'es' {
  if (explicitLang === 'en' || explicitLang === 'es') {
    return explicitLang;
  }
  if (cookieLang === 'en' || cookieLang === 'es') {
    return cookieLang;
  }

  // 1. Cloudflare IP country header (ISO 3166-1 alpha-2, e.g. "US", "MX", "ES")
  const cfCountry = (
    headers.get('cf-ipcountry') ||
    headers.get('x-vercel-ip-country') ||
    headers.get('x-country') ||
    headers.get('geoip-country-code') ||
    ''
  ).toUpperCase().trim();

  if (cfCountry && cfCountry !== 'XX' && cfCountry !== 'T1') {
    return SPANISH_COUNTRIES.has(cfCountry) ? 'es' : 'en';
  }

  // 2. Accept-Language header fallback
  const acceptLang = (headers.get('accept-language') || '').toLowerCase();
  if (acceptLang.startsWith('es') || acceptLang.includes(',es') || acceptLang.includes(';es')) {
    return 'es';
  }

  // Default for all international visitors: English
  return 'en';
}
