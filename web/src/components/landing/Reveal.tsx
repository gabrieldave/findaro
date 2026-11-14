"use client";

import { useEffect } from "react";

declare global {
  interface Window {
    __fxReveal?: boolean;
  }
}

function countUp(scope: HTMLElement, reduce: boolean) {
  const targets = scope.matches("[data-count]")
    ? [scope]
    : Array.from(scope.querySelectorAll<HTMLElement>("[data-count]"));
  for (const el of targets) {
    if (el.dataset.counted) continue;
    el.dataset.counted = "1";
    const to = Number(el.dataset.count);
    const decimals = Number(el.dataset.decimals || 0);
    if (!Number.isFinite(to) || reduce) continue;
    const t0 = performance.now();
    const dur = 1100;
    const tick = (t: number) => {
      const k = Math.min(1, (t - t0) / dur);
      const e = 1 - Math.pow(1 - k, 3);
      el.textContent = (to * e).toFixed(decimals);
      if (k < 1) requestAnimationFrame(tick);
      else el.textContent = to.toFixed(decimals);
    };
    el.textContent = (0).toFixed(decimals);
    requestAnimationFrame(tick);
  }
}

/** Revelado escalonado con blur (Chasis Físico): marca [data-rv] con data-in al entrar en pantalla. */
export default function Reveal({ rootId }: { rootId: string }) {
  useEffect(() => {
    window.__fxReveal = true;
    const root = document.getElementById(rootId);
    if (!root) return;
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    const els = Array.from(root.querySelectorAll<HTMLElement>("[data-rv]"));
    const show = (el: HTMLElement) => {
      el.setAttribute("data-in", "");
      countUp(el, reduce);
    };
    if (reduce || !("IntersectionObserver" in window)) {
      els.forEach(show);
      return;
    }
    const io = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (!entry.isIntersecting) continue;
          show(entry.target as HTMLElement);
          io.unobserve(entry.target);
        }
      },
      { threshold: 0.12, rootMargin: "0px 0px -6% 0px" },
    );
    els.forEach((el) => io.observe(el));
    return () => io.disconnect();
  }, [rootId]);
  return null;
}
