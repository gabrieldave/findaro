import { NextResponse } from 'next/server';
import type { NextRequest } from 'next/server';
import { SPANISH_COUNTRIES } from './lib/geo';

export function middleware(request: NextRequest) {
  const { pathname, searchParams } = request.nextUrl;

  // 1. Direct access to static HTML filenames -> redirect cleanly to root with ?lang= to keep URL short
  if (pathname === '/findaro-landing-en.html') {
    const url = new URL('/?lang=en', request.url);
    searchParams.forEach((value, key) => {
      if (key !== 'lang') url.searchParams.set(key, value);
    });
    const res = NextResponse.redirect(url, 301);
    res.cookies.set('findaro_lang', 'en', { maxAge: 60 * 60 * 24 * 365, path: '/' });
    return res;
  }

  if (pathname === '/findaro-landing.html') {
    const url = new URL('/?lang=es', request.url);
    searchParams.forEach((value, key) => {
      if (key !== 'lang') url.searchParams.set(key, value);
    });
    const res = NextResponse.redirect(url, 301);
    res.cookies.set('findaro_lang', 'es', { maxAge: 60 * 60 * 24 * 365, path: '/' });
    return res;
  }

  // 2. Language Detection
  const queryLang = searchParams.get('lang');
  const cookieLang = request.cookies.get('findaro_lang')?.value;

  let targetLang: 'en' | 'es';

  if (queryLang === 'en' || queryLang === 'es') {
    targetLang = queryLang;
  } else if (cookieLang === 'en' || cookieLang === 'es') {
    targetLang = cookieLang;
  } else {
    // Edge / Cloudflare IP country detection
    const cfCountry = (
      request.headers.get('cf-ipcountry') ||
      request.headers.get('x-vercel-ip-country') ||
      request.headers.get('x-country') ||
      request.headers.get('geoip-country-code') ||
      ''
    ).toUpperCase().trim();

    const acceptLang = (request.headers.get('accept-language') || '').toLowerCase();

    if (cfCountry && cfCountry !== 'XX' && cfCountry !== 'T1') {
      targetLang = SPANISH_COUNTRIES.has(cfCountry) ? 'es' : 'en';
    } else if (acceptLang.startsWith('es') || acceptLang.includes(',es') || acceptLang.includes(';es')) {
      targetLang = 'es';
    } else {
      targetLang = 'en'; // Global default: English
    }
  }

  // 3. Root path '/' -> internal rewrite to clean HTML without changing browser URL
  let res: NextResponse;
  if (pathname === '/') {
    const targetFile = targetLang === 'es' ? '/findaro-landing.html' : '/findaro-landing-en.html';
    res = NextResponse.rewrite(new URL(targetFile, request.url));
  } else {
    // 4. Other pages (/comprar, /probar, /gracias): pass through
    res = NextResponse.next();
  }

  // Set language cookie
  if (!cookieLang || queryLang) {
    res.cookies.set('findaro_lang', targetLang, { maxAge: 60 * 60 * 24 * 365, path: '/' });
  }

  // 5. First-touch UTM persistence in 30-day cookie
  const utmSource = searchParams.get('utm_source');
  const utmMedium = searchParams.get('utm_medium');
  const utmCampaign = searchParams.get('utm_campaign');
  const utmContent = searchParams.get('utm_content');

  if (utmSource || utmMedium || utmCampaign || utmContent) {
    const utmObj = {
      utm_source: utmSource || '',
      utm_medium: utmMedium || '',
      utm_campaign: utmCampaign || '',
      utm_content: utmContent || '',
    };
    res.cookies.set('findaro_utm', JSON.stringify(utmObj), {
      maxAge: 60 * 60 * 24 * 30,
      path: '/',
      sameSite: 'lax',
    });
  }

  // 6. Referral code persistence (rewrite de / → landing estática no llega a page.tsx)
  const refRaw = (searchParams.get('ref') || '').trim();
  if (/^[A-Za-z0-9-]{3,32}$/.test(refRaw)) {
    res.cookies.set('findaro_ref', refRaw.toUpperCase(), {
      maxAge: 60 * 60 * 24 * 30,
      path: '/',
      sameSite: 'lax',
    });
  }

  return res;
}

export const config = {
  matcher: ['/((?!api|_next/static|_next/image|favicon.ico|downloads|screenshots|findaro-comparador).*)'],
};
