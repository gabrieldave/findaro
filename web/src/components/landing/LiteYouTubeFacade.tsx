"use client";

import { useRef, useState, type KeyboardEvent } from "react";
import { COPY, funnel, type ShotKey } from "@/config/funnel";
import type { Lang } from "@/lib/lang";
import s from "./landing.module.css";

/**
 * Lite-YouTube Facade. Con `youtubeTutorialId` muestra solo la miniatura y monta el
 * iframe de youtube-nocookie.com al hacer clic. Sin ID, muestra el recorrido con
 * capturas reales de la app (sin iframes rotos ni carteles de "próximamente").
 */
export default function LiteYouTubeFacade({ lang, videoId }: { lang: Lang; videoId?: string }) {
  const id = (videoId ?? funnel.youtubeTutorialId).trim();
  if (id && /^[A-Za-z0-9_-]{6,20}$/.test(id)) return <Video id={id} lang={lang} />;
  return <ScreenshotTour lang={lang} />;
}

function Video({ id, lang }: { id: string; lang: Lang }) {
  const t = COPY[lang].tour;
  const [playing, setPlaying] = useState(false);
  if (playing) {
    return (
      <div className={s.yt}>
        <iframe
          src={`https://www.youtube-nocookie.com/embed/${id}?autoplay=1&rel=0&modestbranding=1`}
          title={t.play}
          allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
          allowFullScreen
        />
      </div>
    );
  }
  return (
    <button type="button" className={s.yt} onClick={() => setPlaying(true)} aria-label={t.play}>
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img src={`https://i.ytimg.com/vi/${id}/hqdefault.jpg`} alt="" loading="lazy" decoding="async" />
      <span className={s.ytPlay} aria-hidden="true">
        <svg width="26" height="26" viewBox="0 0 24 24">
          <path d="M8 5.5v13l11-6.5z" fill="#1a1d24" />
        </svg>
      </span>
    </button>
  );
}

function ScreenshotTour({ lang }: { lang: Lang }) {
  const t = COPY[lang].tour;
  const [active, setActive] = useState(0);
  const tabRefs = useRef<(HTMLButtonElement | null)[]>([]);
  const slides = t.slides;

  const onKey = (e: KeyboardEvent<HTMLDivElement>) => {
    const last = slides.length - 1;
    let next = active;
    if (e.key === "ArrowRight" || e.key === "ArrowDown") next = active === last ? 0 : active + 1;
    else if (e.key === "ArrowLeft" || e.key === "ArrowUp") next = active === 0 ? last : active - 1;
    else if (e.key === "Home") next = 0;
    else if (e.key === "End") next = last;
    else return;
    e.preventDefault();
    setActive(next);
    tabRefs.current[next]?.focus();
  };

  return (
    <div className={s.tour}>
      <div className={s.tabs} role="tablist" aria-label={t.tabsLabel} onKeyDown={onKey}>
        {slides.map((slide, i) => (
          <button
            key={slide.shot}
            ref={(el) => {
              tabRefs.current[i] = el;
            }}
            type="button"
            role="tab"
            id={`tour-tab-${i}`}
            aria-selected={i === active}
            aria-controls="tour-panel"
            tabIndex={i === active ? 0 : -1}
            className={s.tab}
            onClick={() => setActive(i)}
          >
            <span className={`${s.tabN} ${s.tnum}`}>{String(i + 1).padStart(2, "0")}</span>
            {slide.caption}
          </button>
        ))}
      </div>
      <div>
        <div className={s.screen} role="tabpanel" id="tour-panel" aria-labelledby={`tour-tab-${active}`}>
          {slides.map((slide, i) => {
            const shot = funnel.screenshots[slide.shot as ShotKey];
            return (
              // eslint-disable-next-line @next/next/no-img-element
              <img
                key={slide.shot}
                src={shot.src}
                width={shot.w}
                height={shot.h}
                alt={slide.caption}
                loading="lazy"
                decoding="async"
                data-on={i === active ? "true" : "false"}
                aria-hidden={i === active ? undefined : true}
              />
            );
          })}
        </div>
        <p className={s.screenCap}>{t.sub}</p>
      </div>
    </div>
  );
}
