"use client";

import { useEffect, useRef, useState } from "react";
import { COPY, funnel, type ShotKey } from "@/config/funnel";
import type { Lang } from "@/lib/lang";
import s from "./landing.module.css";

/** Narrativa sticky: en escritorio el escenario de la derecha cambia con el paso activo. */
export default function StickyStory({ lang }: { lang: Lang }) {
  const t = COPY[lang].story;
  const [active, setActive] = useState(0);
  const stepRefs = useRef<(HTMLElement | null)[]>([]);

  useEffect(() => {
    const io = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) setActive(Number((entry.target as HTMLElement).dataset.step));
        }
      },
      { rootMargin: "-45% 0px -45% 0px" },
    );
    stepRefs.current.forEach((el) => el && io.observe(el));
    return () => io.disconnect();
  }, []);

  return (
    <div className={s.story}>
      <div className={s.steps}>
        {t.items.map((item, i) => {
          const shot = item.shot ? funnel.screenshots[item.shot as ShotKey] : null;
          return (
            <article
              key={item.title}
              ref={(el) => {
                stepRefs.current[i] = el;
              }}
              data-step={i}
              data-rv=""
              className={`${s.step} ${i === active ? s.stepOn : ""}`}
            >
              <span className={s.stepChip}>{item.chip}</span>
              <h3>{item.title}</h3>
              <p>{item.body}</p>
              {shot ? (
                <div className={s.stepShot}>
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  <img src={shot.src} width={shot.w} height={shot.h} alt={item.alt} loading="lazy" decoding="async" />
                </div>
              ) : null}
            </article>
          );
        })}
      </div>
      <div className={s.stageCol} aria-hidden="true">
        <div className={s.stage}>
          {t.items.map((item, i) => {
            const shot = item.shot ? funnel.screenshots[item.shot as ShotKey] : null;
            return (
              <div key={item.title} className={`${s.stageCard} ${i === active ? s.stageOn : ""}`}>
                <div className={s.stageMeta}>
                  <span className={s.tnum}>
                    {String(i + 1).padStart(2, "0")} / {String(t.items.length).padStart(2, "0")}
                  </span>
                  <span>{item.chip}</span>
                </div>
                {shot ? (
                  <div className={s.stageImg}>
                    {/* eslint-disable-next-line @next/next/no-img-element */}
                    <img src={shot.src} width={shot.w} height={shot.h} alt="" loading="lazy" decoding="async" />
                  </div>
                ) : (
                  <div className={s.stageType}>
                    <div className={s.stageBig}>{t.renameStage.big}</div>
                    <div className={s.stageBar} />
                    <div className={s.stageSub}>{t.renameStage.sub}</div>
                  </div>
                )}
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
}
