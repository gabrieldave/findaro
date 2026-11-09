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

  // 2. Only handle root path '/'
  if (pathname === '/') {
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

    const targetFile = targetLang === 'es' ? '/findaro-landing.html' : '/findaro-landing-en.html';

    // Rewrite internally so browser URL bar STAYS clean as https://findaro.iareal.net
    const res = NextResponse.rewrite(new URL(targetFile, request.url));
    res.cookies.set('findaro_lang', targetLang, { maxAge: 60 * 60 * 24 * 365, path: '/' });
    return res;
  }

  return NextResponse.next();
}

export const config = {
  matcher: ['/', '/findaro-landing.html', '/findaro-landing-en.html'],
};
