"use client";

import { useEffect, useState } from "react";
import { COPY, whatsappHref } from "@/config/funnel";
import type { Lang } from "@/lib/lang";
import s from "./landing.module.css";

/** Burbuja flotante de WhatsApp: canal exclusivo para dudas rápidas antes de comprar o activar. */
export default function WhatsAppSupportBubble({ lang }: { lang: Lang }) {
  const t = COPY[lang].whatsapp;
  const [tip, setTip] = useState(false);

  useEffect(() => {
    let seen = false;
    try {
      seen = sessionStorage.getItem("findaro-wa-tip") === "1";
    } catch {
      seen = false;
    }
    if (seen) return;
    const show = window.setTimeout(() => {
      setTip(true);
      try {
        sessionStorage.setItem("findaro-wa-tip", "1");
      } catch {
        /* almacenamiento no disponible */
      }
    }, 14000);
    const hide = window.setTimeout(() => setTip(false), 22000);
    return () => {
      window.clearTimeout(show);
      window.clearTimeout(hide);
    };
  }, []);

  return (
    <div className={s.wa} onMouseEnter={() => setTip(true)} onMouseLeave={() => setTip(false)}>
      {tip ? (
        <div className={s.waTip} role="status">
          {t.tooltip}
        </div>
      ) : null}
      <a
        className={s.waBtn}
        href={whatsappHref(t.message)}
        target="_blank"
        rel="noopener noreferrer"
        aria-label={t.tooltip}
        title={t.tooltip}
        onFocus={() => setTip(true)}
        onBlur={() => setTip(false)}
      >
        <span className={s.waIc} aria-hidden="true">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="#fff">
            <path d="M12 2a10 10 0 0 0-8.6 15.1L2 22l5-1.3A10 10 0 1 0 12 2Zm0 18.2c-1.5 0-3-.4-4.3-1.2l-.3-.2-3 .8.8-2.9-.2-.3A8.2 8.2 0 1 1 12 20.2Zm4.5-6.1c-.2-.1-1.5-.7-1.7-.8-.2-.1-.4-.1-.6.1l-.8 1c-.1.2-.3.2-.5.1a6.7 6.7 0 0 1-3.3-2.9c-.2-.4.2-.4.7-1.2.1-.1 0-.3 0-.4l-.8-1.8c-.2-.5-.4-.4-.6-.4h-.5a1 1 0 0 0-.7.3 3 3 0 0 0-.9 2.2c0 1.3.9 2.5 1 2.7.1.2 1.8 2.8 4.4 3.9 1.6.7 2.3.8 3.1.6.5-.1 1.5-.6 1.7-1.2.2-.6.2-1.1.2-1.2-.1-.1-.3-.2-.5-.3Z" />
          </svg>
        </span>
        <span className={s.waLabel}>{t.label}</span>
      </a>
    </div>
  );
}
