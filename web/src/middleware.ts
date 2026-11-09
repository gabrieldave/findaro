import { NextResponse } from 'next/server';
import type { NextRequest } from 'next/server';
import { SPANISH_COUNTRIES } from './lib/geo';

export function middleware(request: NextRequest) {
  const { pathname, searchParams } = request.nextUrl;

  // 1. Explicit query param (e.g. ?lang=en or ?lang=es)
  const queryLang = searchParams.get('lang');
  if (queryLang === 'en' || queryLang === 'es') {
    const res = NextResponse.next();
    res.cookies.set('findaro_lang', queryLang, { maxAge: 60 * 60 * 24 * 365, path: '/' });
    return res;
  }

  // 2. Saved user preference in cookie
  const cookieLang = request.cookies.get('findaro_lang')?.value;
  if (cookieLang === 'en' || cookieLang === 'es') {
    if (pathname === '/') {
      return NextResponse.redirect(new URL(cookieLang === 'en' ? '/findaro-landing-en.html' : '/findaro-landing.html', request.url));
    }
    return NextResponse.next();
  }

  // 3. Country Detection via Cloudflare / Edge IP header
  const cfCountry = (
    request.headers.get('cf-ipcountry') ||
    request.headers.get('x-vercel-ip-country') ||
    request.headers.get('x-country') ||
    request.headers.get('geoip-country-code') ||
    ''
  ).toUpperCase().trim();

  const acceptLang = (request.headers.get('accept-language') || '').toLowerCase();

  let detectedLang: 'en' | 'es' = 'en'; // Default globally to English
  if (cfCountry && cfCountry !== 'XX' && cfCountry !== 'T1') {
    detectedLang = SPANISH_COUNTRIES.has(cfCountry) ? 'es' : 'en';
  } else if (acceptLang.startsWith('es') || acceptLang.includes(',es') || acceptLang.includes(';es')) {
    detectedLang = 'es';
  }

  // Root redirect
  if (pathname === '/') {
    const target = detectedLang === 'en' ? '/findaro-landing-en.html' : '/findaro-landing.html';
    const res = NextResponse.redirect(new URL(target, request.url));
    res.cookies.set('findaro_lang', detectedLang, { maxAge: 60 * 60 * 24 * 365, path: '/' });
    return res;
  }

  // If hitting static pages directly without explicit cookie preference:
  if (pathname === '/findaro-landing.html' && detectedLang === 'en') {
    const res = NextResponse.redirect(new URL('/findaro-landing-en.html', request.url));
    res.cookies.set('findaro_lang', 'en', { maxAge: 60 * 60 * 24 * 365, path: '/' });
    return res;
  }

  if (pathname === '/findaro-landing-en.html' && detectedLang === 'es') {
    const res = NextResponse.redirect(new URL('/findaro-landing.html', request.url));
    res.cookies.set('findaro_lang', 'es', { maxAge: 60 * 60 * 24 * 365, path: '/' });
    return res;
  }

  return NextResponse.next();
}

export const config = {
  matcher: ['/', '/findaro-landing.html', '/findaro-landing-en.html'],
};
