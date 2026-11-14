"use client";

import { useState } from "react";
import { COPY, funnel } from "@/config/funnel";
import type { Lang } from "@/lib/lang";
import s from "./landing.module.css";

/** Tarjetas pequeñas e interactivas: Copiar ruta, Dropover y limpieza de .DS_Store / ._* */
export default function MiniTools({ lang }: { lang: Lang }) {
  const t = COPY[lang].tools;
  const [copied, setCopied] = useState(false);
  const [sent, setSent] = useState(false);
  const [cleaned, setCleaned] = useState(false);

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(t.copyPath.path);
    } catch {
      /* el portapapeles puede no estar disponible; la demo sigue */
    }
    setCopied(true);
    window.setTimeout(() => setCopied(false), 2400);
  };

  return (
    <div className={s.cards}>
      <div className={s.card} data-rv="">
        <h3>
          {t.copyPath.title} <span className={s.kbd}>{funnel.shortcuts.copyPath}</span>
        </h3>
        <p>{t.copyPath.body}</p>
        <button type="button" className={s.btnLine} onClick={copy}>
          {copied ? t.copyPath.done : t.copyPath.button}
        </button>
        <div className={s.codeLine}>cd &apos;{t.copyPath.path}&apos;</div>
      </div>

      <div className={s.card} data-rv="">
        <h3>
          {t.dropover.title}
          {funnel.shortcuts.dropover ? <span className={s.kbd}>{funnel.shortcuts.dropover}</span> : null}
        </h3>
        <p>{t.dropover.body}</p>
        <button type="button" className={s.btnLine} onClick={() => setSent(true)} disabled={sent}>
          {sent ? t.dropover.done : t.dropover.button}
        </button>
      </div>

      <div className={s.card} data-rv="">
        <h3>{t.cleanup.title}</h3>
        <p>{t.cleanup.body}</p>
        <ul className={s.junk} aria-live="polite">
          {t.cleanup.files.map((f) => (
            <li key={f} className={cleaned ? s.junkGone : undefined}>
              {f}
            </li>
          ))}
          {t.cleanup.keep.map((f) => (
            <li key={f} className={s.junkKeep}>
              {f}
            </li>
          ))}
        </ul>
        <button type="button" className={s.btnLine} onClick={() => setCleaned(true)} disabled={cleaned}>
          {t.cleanup.button}
        </button>
        <p className={s.result}>{cleaned ? t.cleanup.done(t.cleanup.files.length) : ""}</p>
      </div>
    </div>
  );
}
