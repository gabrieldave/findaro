"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { COPY, funnel } from "@/config/funnel";
import type { Lang } from "@/lib/lang";
import s from "./landing.module.css";

type PlanRow = { from: string; to: string; matched: boolean; changed: boolean; coll: boolean };

const sleep = (ms: number) => new Promise<void>((r) => window.setTimeout(r, ms));

function makeFiles(): string[] {
  const files: string[] = [];
  for (let i = 0; i < 120; i++) files.push(`RAW-${String(40 + i).padStart(4, "0")}.DNG`);
  // Archivos que ya existen en la carpeta: provocan colisiones con el patrón corto.
  files.splice(12, 0, "Cliente-007.DNG");
  files.splice(60, 0, "Cliente-042.DNG");
  return files;
}

function buildPlan(files: string[], find: string, rep: string): { plan: PlanRow[]; invalid: boolean } {
  const unchanged = () => files.map((f) => ({ from: f, to: f, matched: false, changed: false, coll: false }));
  if (!find || !rep) return { plan: unchanged(), invalid: false };
  let re: RegExp;
  try {
    re = new RegExp(find);
  } catch {
    return { plan: unchanged(), invalid: true };
  }
  let seq = 0;
  const plan = files.map((f) => {
    if (!re.test(f)) return { from: f, to: f, matched: false, changed: false, coll: false };
    seq++;
    const n = seq;
    const to = f.replace(re, (...args: unknown[]) => {
      const groups = args.slice(1, -2) as (string | undefined)[];
      return rep
        .replace(/\$(\d)/g, (_m, k: string) => groups[Number(k) - 1] ?? "")
        .replace(/\{n(?::(\d+))?\}/g, (_m, w?: string) => String(n).padStart(Number(w) || 0, "0"));
    });
    return { from: f, to, matched: true, changed: to !== f, coll: false };
  });
  const count = new Map<string, number>();
  plan.forEach((p) => count.set(p.to, (count.get(p.to) || 0) + 1));
  plan.forEach((p) => {
    p.coll = (count.get(p.to) || 0) > 1;
  });
  return { plan, invalid: false };
}

/** Simulador de barra de ruta ⌘L + Tab y renombrado por lotes en 2 fases con ⌘Z (lógica de BatchRenameExecutor). */
export default function RenameDemo({ lang }: { lang: Lang }) {
  const t = COPY[lang].tools.rename;
  const [path, setPath] = useState("");
  const [showSugg, setShowSugg] = useState(false);
  const [find, setFind] = useState("RAW-(\\d+)");
  const [rep, setRep] = useState("");
  const [files, setFiles] = useState<string[]>(makeFiles);
  const [history, setHistory] = useState<string[][]>([]);
  const [tempMode, setTempMode] = useState(false);
  const [busy, setBusy] = useState(false);
  const [phase, setPhase] = useState("");
  const [tabFlash, setTabFlash] = useState(0);

  const autoRef = useRef(true);
  const rootRef = useRef<HTMLDivElement>(null);
  const tblRef = useRef<HTMLDivElement>(null);
  const pathRef = useRef<HTMLInputElement>(null);
  const inView = useRef(false);
  const reduce = useRef(false);

  const { plan, invalid } = useMemo(() => buildPlan(files, find, rep), [files, find, rep]);
  const matched = plan.filter((p) => p.matched).length;
  const changed = plan.filter((p) => p.changed).length;
  const collisions = plan.filter((p) => p.coll && p.changed).length;

  const suggestions = useMemo(() => {
    const ix = path.lastIndexOf("/") + 1;
    const dir = path.slice(0, ix);
    const part = path.slice(ix).toLowerCase();
    return (t.tree[dir] || []).filter((n) => n.toLowerCase().startsWith(part)).map((n) => `${dir}${n}/`);
  }, [path, t.tree]);

  const complete = useCallback(() => {
    if (suggestions.length) setPath(suggestions[0]);
    setTabFlash((n) => n + 1);
  }, [suggestions]);

  const stopAuto = () => {
    autoRef.current = false;
  };

  const apply = async () => {
    if (busy || !changed || collisions) return;
    stopAuto();
    setBusy(true);
    setHistory((h) => [...h, files]);
    const next = plan.map((p) => p.to);
    setTempMode(true);
    setPhase(t.phase1);
    await sleep(reduce.current ? 0 : 650);
    setTempMode(false);
    setFiles(next);
    setPhase(t.phase2);
    await sleep(reduce.current ? 0 : 450);
    setPhase(t.applied(changed));
    setBusy(false);
  };

  const undo = useCallback(async () => {
    if (busy || !history.length) return;
    autoRef.current = false;
    setBusy(true);
    const prev = history[history.length - 1];
    setTempMode(true);
    setPhase(t.phase1);
    await sleep(reduce.current ? 0 : 550);
    setTempMode(false);
    setFiles(prev);
    setHistory((h) => h.slice(0, -1));
    setPhase(t.undone);
    setBusy(false);
  }, [busy, history, t]);

  useEffect(() => {
    reduce.current = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    const el = rootRef.current;
    if (!el) return;
    let started = false;
    const typeInto = async (setter: (fn: (v: string) => string) => void, text: string, ms: number, at?: number) => {
      let pos = at;
      for (const ch of text) {
        if (!autoRef.current) return false;
        const at = pos;
        setter((v) => (at == null ? v + ch : v.slice(0, at) + ch + v.slice(at)));
        if (pos != null) pos++;
        await sleep(ms);
      }
      return true;
    };
    const run = async () => {
      if (reduce.current) {
        setPath(Object.keys(t.tree).find((k) => k.endsWith("/Cliente-2026/")) || "~/");
        setRep("Cliente-2026-{n:03}");
        setPhase(t.ready);
        autoRef.current = false;
        return;
      }
      await sleep(300);
      setShowSugg(true);
      if (!(await typeInto(setPath, t.autotypeA, 55))) return;
      await sleep(380);
      if (!autoRef.current) return;
      setPath((v) => {
        const ix = v.lastIndexOf("/") + 1;
        const dir = v.slice(0, ix);
        const part = v.slice(ix).toLowerCase();
        const hit = (t.tree[dir] || []).find((n) => n.toLowerCase().startsWith(part));
        return hit ? `${dir}${hit}/` : v;
      });
      setTabFlash((n) => n + 1);
      await sleep(320);
      if (!(await typeInto(setPath, t.autotypeB, 70))) return;
      await sleep(320);
      if (!autoRef.current) return;
      setPath((v) => {
        const ix = v.lastIndexOf("/") + 1;
        const dir = v.slice(0, ix);
        const part = v.slice(ix).toLowerCase();
        const hit = (t.tree[dir] || []).find((n) => n.toLowerCase().startsWith(part));
        return hit ? `${dir}${hit}/` : v;
      });
      setTabFlash((n) => n + 1);
      await sleep(300);
      setShowSugg(false);
      if (!(await typeInto(setRep, "Cliente-{n:03}", 45))) return;
      await sleep(900);
      if (!(await typeInto(setRep, "2026-", 80, "Cliente-".length))) return;
      autoRef.current = false;
      setPhase(t.ready);
      if (tblRef.current) tblRef.current.scrollTop = 0;
    };
    const io = new IntersectionObserver(
      ([e]) => {
        inView.current = e.isIntersecting;
        if (e.isIntersecting && !started && e.intersectionRatio > 0.3) {
          started = true;
          void run();
        }
      },
      { threshold: [0, 0.35] },
    );
    io.observe(el);
    return () => {
      io.disconnect();
      autoRef.current = false;
    };
  }, [t]);

  // Lleva la tabla a la primera colisión mientras corre la demo automática.
  useEffect(() => {
    if (!autoRef.current || !collisions || !tblRef.current) return;
    const first = tblRef.current.querySelector<HTMLElement>(`.${s.coll}`);
    if (first) tblRef.current.scrollTop = first.offsetTop - 60;
  }, [collisions]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (!inView.current || !(e.metaKey || e.ctrlKey)) return;
      const k = e.key.toLowerCase();
      if (k === "l") {
        e.preventDefault();
        stopAuto();
        pathRef.current?.focus();
        pathRef.current?.select();
        setShowSugg(true);
      } else if (k === "z") {
        const tag = (document.activeElement?.tagName || "").toUpperCase();
        if (tag === "INPUT" || tag === "TEXTAREA") return;
        e.preventDefault();
        void undo();
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [undo]);

  return (
    <div ref={rootRef} data-rv="lift">
      <div className={s.win} onPointerDownCapture={stopAuto}>
        <div className={s.titlebar}>
          <div className={s.lights} aria-hidden="true">
            <i />
            <i />
            <i />
          </div>
          <span className={s.wtitle}>{t.windowTitle}</span>
        </div>
        <div className={s.pathRow}>
          <div className={s.pathWrap}>
            <span className={s.pathKey}>{funnel.shortcuts.pathBar}</span>
            <input
              ref={pathRef}
              className={s.path}
              value={path}
              spellCheck={false}
              autoComplete="off"
              aria-label={t.pathLabel}
              onChange={(e) => {
                stopAuto();
                setPath(e.target.value);
                setShowSugg(true);
              }}
              onFocus={() => setShowSugg(true)}
              onBlur={() => window.setTimeout(() => setShowSugg(false), 120)}
              onKeyDown={(e) => {
                if (e.key === "Tab" && suggestions.length) {
                  e.preventDefault();
                  complete();
                } else if (e.key === "Enter") {
                  setShowSugg(false);
                  pathRef.current?.blur();
                }
              }}
            />
            {showSugg && suggestions.length ? (
              <div className={s.sugg} role="listbox">
                {suggestions.map((p) => (
                  <button
                    key={p}
                    type="button"
                    role="option"
                    aria-selected={p === suggestions[0]}
                    onMouseDown={(e) => {
                      e.preventDefault();
                      setPath(p);
                    }}
                  >
                    {p.split("/").slice(-2, -1)[0]}/ <span>{t.tab}</span>
                  </button>
                ))}
              </div>
            ) : null}
          </div>
          <span key={tabFlash} className={`${s.tabKey} ${tabFlash ? s.tabFlash : ""}`} aria-hidden="true">
            {t.tab}
          </span>
        </div>

        <div className={s.rn}>
          <div className={s.rnIn}>
            <div>
              <label htmlFor="rn-find">{t.find}</label>
              <input
                id="rn-find"
                value={find}
                spellCheck={false}
                autoComplete="off"
                aria-invalid={invalid}
                onChange={(e) => {
                  stopAuto();
                  setFind(e.target.value);
                }}
              />
            </div>
            <div>
              <label htmlFor="rn-rep">{t.replace}</label>
              <input
                id="rn-rep"
                value={rep}
                spellCheck={false}
                autoComplete="off"
                onChange={(e) => {
                  stopAuto();
                  setRep(e.target.value);
                }}
              />
            </div>
          </div>
          <div className={s.chips}>
            {t.chips.map((c) => (
              <button
                key={c.label}
                type="button"
                className={s.chip}
                onClick={() => {
                  stopAuto();
                  setFind(c.f);
                  setRep(c.r);
                  setPhase("");
                  if (tblRef.current) tblRef.current.scrollTop = 0;
                }}
              >
                {c.label}
              </button>
            ))}
          </div>
          <div className={s.tbl} ref={tblRef} role="table" aria-label={t.windowTitle}>
            <div className={`${s.tr} ${s.th}`} role="row">
              <div role="columnheader">{t.before}</div>
              <div role="columnheader">{t.after}</div>
            </div>
            {plan.map((p, i) => {
              const cls = [s.tr, p.coll && p.changed ? s.coll : "", !p.changed ? s.same : ""].join(" ");
              return (
                <div key={`${p.from}-${i}`} className={cls} role="row">
                  <div className={s.from} role="cell">
                    {tempMode && p.changed ? <span className={s.tmp}>.findaro-tmp-{String(i).padStart(3, "0")}</span> : p.from}
                  </div>
                  <div className={s.to} role="cell">
                    {p.to}
                  </div>
                </div>
              );
            })}
          </div>
          <div className={s.rnFoot}>
            <div className={`${s.stat} ${s.tnum}`}>
              {t.stat(files.length, matched, changed)} ·{" "}
              {collisions ? <span className={s.statBad}>{t.collisions(collisions)}</span> : t.noCollisions}
            </div>
            <div style={{ display: "flex", gap: 8 }}>
              <button type="button" className={s.sb} onClick={() => void undo()} disabled={busy || !history.length}>
                {t.undo}
              </button>
              <button type="button" className={`${s.sb} ${s.sbBlue}`} onClick={() => void apply()} disabled={busy || !changed || collisions > 0}>
                {t.apply}
              </button>
            </div>
          </div>
          <p className={s.phase} aria-live="polite">
            {phase}
          </p>
        </div>
      </div>
      <p className={s.demoNote}>{t.note}</p>
    </div>
  );
}
