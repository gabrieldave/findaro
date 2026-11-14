"use client";

import { useCallback, useEffect, useLayoutEffect, useRef, useState, type PointerEvent as RPointerEvent } from "react";
import { COPY, funnel } from "@/config/funnel";
import type { Lang } from "@/lib/lang";
import { sha256Hex } from "./sha256";
import s from "./landing.module.css";

type Item = { name: string; size: string; seed: string; folder?: boolean; fresh?: boolean };
type Level = 0 | 1 | 2;
type Side = "left" | "right";
type Phase = "idle" | "preview" | "merging" | "done";
type MergeKind = "new" | "conflict" | "same";
type MergeItem = { name: string; kind: MergeKind; size: string; destSize?: string; seed: string; hash?: string };

const SIZE: Record<string, string> = {
  mov: "18.4 GB",
  dng: "61.2 MB",
  pdf: "248 KB",
  fig: "36.1 MB",
  zip: "412 MB",
  svg: "12 KB",
  srt: "48 KB",
  wav: "1.1 GB",
  psd: "88.3 MB",
  md: "6 KB",
  drp: "2.4 MB",
  key: "14.9 MB",
  numbers: "320 KB",
};
const NEWER: Record<string, string> = { pdf: "251 KB", fig: "38.4 MB", zip: "418 MB" };
const EXT_COLOR: Record<string, string> = {
  mov: "#7c3aed",
  dng: "#059669",
  pdf: "#dc2626",
  fig: "#a21caf",
  zip: "#475569",
  svg: "#d97706",
  srt: "#0284c7",
  wav: "#db2777",
  psd: "#2563eb",
  md: "#64748b",
  drp: "#ea580c",
  key: "#2563eb",
  numbers: "#16a34a",
};

const ext = (name: string) => (name.split(".").pop() || "").toLowerCase();
const byName = (a: Item, b: Item) => Number(!!b.folder) - Number(!!a.folder) || a.name.localeCompare(b.name);
const sleep = (ms: number) => new Promise<void>((r) => window.setTimeout(r, ms));
const withSuffix = (name: string, n = 2) => {
  const i = name.lastIndexOf(".");
  return i > 0 ? `${name.slice(0, i)} ${n}${name.slice(i)}` : `${name} ${n}`;
};

function FileIcon({ item }: { item: Item }) {
  if (item.folder) {
    return (
      <svg width="16" height="14" viewBox="0 0 16 14" aria-hidden="true">
        <path d="M1 2.5A1.5 1.5 0 0 1 2.5 1h3.4l1.4 1.5h6.2A1.5 1.5 0 0 1 15 4v7.5A1.5 1.5 0 0 1 13.5 13h-11A1.5 1.5 0 0 1 1 11.5z" fill="#4f8ff7" />
      </svg>
    );
  }
  const e = ext(item.name);
  return (
    <span className={s.fileIc} style={{ background: EXT_COLOR[e] || "#475569" }} aria-hidden="true">
      {e.slice(0, 1).toUpperCase()}
    </span>
  );
}

export default function HeroMerge({ lang }: { lang: Lang }) {
  const t = COPY[lang].demo;
  const fmt = useCallback((size: string) => (lang === "es" ? size.replace(".", ",") : size), [lang]);

  const initialLeft = useCallback(
    (): Item[] =>
      [
        ...t.files.fresh.map((n) => ({ name: n, size: SIZE[ext(n)] || "1 MB", seed: "n" })),
        ...t.files.conflict.map((n) => ({ name: n, size: NEWER[ext(n)] || SIZE[ext(n)] || "1 MB", seed: "v2" })),
        ...t.files.same.map((n) => ({ name: n, size: SIZE[ext(n)] || "1 MB", seed: "s" })),
      ].sort(byName),
    [t],
  );
  const initialRight = useCallback(
    (): Item[] =>
      [
        ...t.files.conflict.map((n) => ({ name: n, size: SIZE[ext(n)] || "1 MB", seed: "v1" })),
        ...t.files.same.map((n) => ({ name: n, size: SIZE[ext(n)] || "1 MB", seed: "s" })),
        ...t.files.destOnly.map((n) => ({ name: n, size: SIZE[ext(n)] || "1 MB", seed: "d" })),
      ].sort(byName),
    [t],
  );

  const [left, setLeft] = useState<Item[]>(initialLeft);
  const [right, setRight] = useState<Item[]>(initialRight);
  const [levels, setLevels] = useState<Record<Side, Level>>({ left: 2, right: 2 });
  const [activeSide, setActiveSide] = useState<Side>("left");
  const [dual, setDual] = useState(true);
  const [selected, setSelected] = useState<string[]>([]);
  const [tray, setTray] = useState<string[]>([]);
  const [phase, setPhase] = useState<Phase>("idle");
  const [items, setItems] = useState<MergeItem[]>([]);
  const [verified, setVerified] = useState(0);
  const [outcome, setOutcome] = useState<"kept" | "replaced" | null>(null);
  const [snapshot, setSnapshot] = useState<{ left: Item[]; right: Item[] } | null>(null);
  const [hot, setHot] = useState(false);
  const [ghostOn, setGhostOn] = useState(false);
  const [fly, setFly] = useState(false);
  const [hintOn, setHintOn] = useState(true);
  const [hintPos, setHintPos] = useState<{ x: number; y: number } | null>(null);
  const [toast, setToast] = useState<{ msg: string; id: number } | null>(null);
  const [coarse, setCoarse] = useState(false);

  const winRef = useRef<HTMLDivElement>(null);
  const rightRef = useRef<HTMLDivElement>(null);
  const leftRef = useRef<HTMLDivElement>(null);
  const srcRef = useRef<HTMLElement | null>(null);
  const ghostRef = useRef<HTMLDivElement>(null);
  const ghostPos = useRef({ x: 0, y: 0 });
  const drag = useRef<{ sx: number; sy: number; ox: number; oy: number; moved: number } | null>(null);
  const inView = useRef(false);
  const primaryRef = useRef<HTMLButtonElement>(null);
  const reduce = useRef(false);

  useEffect(() => {
    reduce.current = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    setCoarse(window.matchMedia("(pointer: coarse)").matches);
    const el = winRef.current;
    if (!el) return;
    const io = new IntersectionObserver(([e]) => {
      inView.current = e.isIntersecting;
    });
    io.observe(el);
    return () => io.disconnect();
  }, []);

  const say = useCallback((msg: string) => setToast({ msg, id: Date.now() }), []);
  useEffect(() => {
    if (!toast) return;
    const id = window.setTimeout(() => setToast(null), 2800);
    return () => window.clearTimeout(id);
  }, [toast]);

  // Posición de la burbuja de ayuda bajo el elemento que se arrastra.
  useLayoutEffect(() => {
    const place = () => {
      const src = srcRef.current;
      const win = winRef.current;
      if (!src || !win) return setHintPos(null);
      const a = src.getBoundingClientRect();
      const b = win.getBoundingClientRect();
      setHintPos({ x: Math.max(8, Math.min(a.left - b.left, b.width - 230)), y: a.bottom - b.top + 10 });
    };
    place();
    window.addEventListener("resize", place);
    return () => window.removeEventListener("resize", place);
  }, [levels, dual, hintOn]);

  /* ----------------------------- Navegación ----------------------------- */
  const crumbs = (side: Side) =>
    side === "left" ? [t.rootLeft, t.midLeft, t.folder] : [t.rootRight, t.midRight, t.folder];
  const posixPath = (side: Side) => {
    const lv = levels[side];
    if (side === "left") return ["/Volumes", t.rootLeft, t.midLeft, t.folder].slice(0, lv + 2).join("/");
    return ["~", t.midRight, t.folder].slice(0, lv + 1).join("/");
  };
  const folderRows = (side: Side): Item[] => {
    const lv = levels[side];
    const count = side === "left" ? left.length : right.length;
    if (lv === 1) {
      const extra = side === "left" ? t.sampleFolders.left : t.sampleFolders.right;
      return [{ name: t.folder, size: t.folderItems(count), seed: "f", folder: true }, ...extra.map((n) => ({ name: n, size: "—", seed: "x", folder: true }))];
    }
    const mid = side === "left" ? t.midLeft : t.midRight;
    const extra = side === "left" ? t.sampleFolders.leftRoot : t.sampleFolders.rightRoot;
    return [{ name: mid, size: "—", seed: "m", folder: true }, ...extra.map((n) => ({ name: n, size: "—", seed: "x", folder: true }))];
  };
  const go = (side: Side, lv: Level) => {
    setLevels((prev) => ({ ...prev, [side]: lv }));
    setActiveSide(side);
    if (side === "left") setSelected([]);
  };
  const openFolder = (side: Side, item: Item) => {
    const lv = levels[side];
    if (lv === 0 && item.seed === "m") go(side, 1);
    else if (lv === 1 && item.seed === "f") go(side, 2);
    else say(t.toasts.sample);
  };

  /* -------------------------------- Merge -------------------------------- */
  const openPreview = useCallback(() => {
    const rightByName = new Map(right.map((r) => [r.name, r]));
    const list: MergeItem[] = left.map((l) => {
      const r = rightByName.get(l.name);
      if (!r) return { name: l.name, kind: "new", size: l.size, seed: l.seed };
      if (r.seed === l.seed) return { name: l.name, kind: "same", size: l.size, seed: l.seed };
      return { name: l.name, kind: "conflict", size: l.size, destSize: r.size, seed: l.seed };
    });
    const order: Record<MergeKind, number> = { conflict: 0, new: 1, same: 2 };
    list.sort((a, b) => order[a.kind] - order[b.kind] || a.name.localeCompare(b.name));
    setItems(list);
    setVerified(0);
    setOutcome(null);
    setPhase("preview");
    setHintOn(false);
    setLevels((prev) => ({ ...prev, right: 2 }));
    setActiveSide("right");
  }, [left, right]);

  useEffect(() => {
    if (phase === "preview" || phase === "done") primaryRef.current?.focus({ preventScroll: true });
  }, [phase]);

  const runMerge = async (keep: boolean) => {
    setPhase("merging");
    setSnapshot({ left, right });
    const toCopy = items.filter((i) => i.kind !== "same");
    for (let i = 0; i < toCopy.length; i++) {
      const it = toCopy[i];
      const bytes = `findaro-demo:${it.name}:${it.seed}`;
      const [original, copy] = await Promise.all([sha256Hex(bytes), sha256Hex(bytes)]);
      const ok = original === copy;
      setItems((prev) => prev.map((p) => (p.name === it.name ? { ...p, hash: ok ? original : "" } : p)));
      setVerified(i + 1);
      if (!reduce.current) await sleep(70);
    }
    setRight((prev) => {
      const next = prev.map((p) => ({ ...p, fresh: false }));
      for (const it of toCopy) {
        if (it.kind === "new") next.push({ name: it.name, size: it.size, seed: it.seed, fresh: true });
        else if (keep) next.push({ name: withSuffix(it.name), size: it.size, seed: it.seed, fresh: true });
        else {
          const idx = next.findIndex((p) => p.name === it.name);
          if (idx >= 0) next[idx] = { name: it.name, size: it.size, seed: it.seed, fresh: true };
        }
      }
      return next.sort(byName);
    });
    setOutcome(keep ? "kept" : "replaced");
    setPhase("done");
  };

  const undo = useCallback(() => {
    if (!snapshot) return;
    setLeft(snapshot.left);
    setRight(snapshot.right);
    setSnapshot(null);
    setTray([]);
    setSelected([]);
    setPhase("idle");
    say(t.toasts.undone);
  }, [snapshot, say, t]);

  /* ----------------------------- Arrastre ----------------------------- */
  const overRight = (x: number, y: number) => {
    const r = rightRef.current?.getBoundingClientRect();
    return !!r && x >= r.left && x <= r.right && y >= r.top && y <= r.bottom;
  };
  const setGhost = (x: number, y: number) => {
    ghostPos.current = { x, y };
    if (ghostRef.current) ghostRef.current.style.transform = `translate(${x}px, ${y}px)`;
  };

  const autoDrop = () => {
    if (!dual) {
      say(t.toasts.needDual);
      setGhostOn(false);
      return;
    }
    const win = winRef.current?.getBoundingClientRect();
    const src = srcRef.current?.getBoundingClientRect();
    const dst = rightRef.current?.getBoundingClientRect();
    if (!win || !src || !dst) return;
    setFly(false);
    setGhost(src.left - win.left, src.top - win.top);
    setGhostOn(true);
    window.requestAnimationFrame(() =>
      window.requestAnimationFrame(() => {
        setFly(true);
        setGhost(dst.left - win.left + dst.width / 2 - 70, dst.top - win.top + Math.min(dst.height / 2, 120));
      }),
    );
    window.setTimeout(
      () => {
        setGhostOn(false);
        setFly(false);
        openPreview();
      },
      reduce.current ? 0 : 560,
    );
  };

  const onDown = (e: RPointerEvent<HTMLElement>) => {
    if (phase !== "idle") return;
    e.preventDefault();
    setHintOn(false);
    setActiveSide("left");
    const win = winRef.current?.getBoundingClientRect();
    const src = e.currentTarget.getBoundingClientRect();
    if (!win) return;
    drag.current = { sx: e.clientX, sy: e.clientY, ox: src.left - win.left, oy: src.top - win.top, moved: 0 };
    try {
      e.currentTarget.setPointerCapture(e.pointerId);
    } catch {
      /* algunos navegadores no permiten captura */
    }
  };
  const onMove = (e: RPointerEvent<HTMLElement>) => {
    const d = drag.current;
    if (!d) return;
    const dx = e.clientX - d.sx;
    const dy = e.clientY - d.sy;
    d.moved = Math.max(d.moved, Math.hypot(dx, dy));
    if (d.moved < 6) return;
    if (!ghostOn) setGhostOn(true);
    setFly(false);
    setGhost(d.ox + dx, d.oy + dy);
    const isHot = dual && overRight(e.clientX, e.clientY);
    if (isHot !== hot) setHot(isHot);
  };
  const onUp = (e: RPointerEvent<HTMLElement>) => {
    const d = drag.current;
    drag.current = null;
    setHot(false);
    if (!d) return;
    if (d.moved < 6) {
      autoDrop();
      return;
    }
    setGhostOn(false);
    if (dual && overRight(e.clientX, e.clientY)) openPreview();
  };
  const onCancel = () => {
    drag.current = null;
    setHot(false);
    setGhostOn(false);
  };

  /* ---------------------------- Cortar / Pegar ---------------------------- */
  const toggleSelect = (name: string) => {
    setActiveSide("left");
    setSelected((prev) => (prev.includes(name) ? prev.filter((n) => n !== name) : [...prev, name]));
  };
  const cut = useCallback(() => {
    if (!selected.length) return;
    setTray(selected);
    say(t.toasts.cut(selected.length));
  }, [selected, say, t]);
  const paste = useCallback(() => {
    if (!tray.length) return;
    setSnapshot({ left, right });
    const moving = left.filter((l) => tray.includes(l.name));
    setLeft((prev) => prev.filter((l) => !tray.includes(l.name)));
    setRight((prev) => {
      const names = new Set(prev.map((p) => p.name));
      const next = prev.map((p) => ({ ...p, fresh: false }));
      for (const m of moving) next.push({ ...m, name: names.has(m.name) ? withSuffix(m.name) : m.name, fresh: true });
      return next.sort(byName);
    });
    setLevels((prev) => ({ ...prev, right: 2 }));
    setTray([]);
    setSelected([]);
    say(t.toasts.pasted(moving.length));
  }, [tray, left, right, say, t]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (!inView.current || !(e.metaKey || e.ctrlKey)) return;
      const tag = (document.activeElement?.tagName || "").toUpperCase();
      if (tag === "INPUT" || tag === "TEXTAREA") return;
      const k = e.key.toLowerCase();
      if (k === "x" && selected.length && phase === "idle") {
        e.preventDefault();
        cut();
      } else if (k === "v" && tray.length && phase === "idle") {
        e.preventDefault();
        paste();
      } else if (k === "z" && snapshot && (phase === "idle" || phase === "done")) {
        e.preventDefault();
        undo();
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [selected, tray, snapshot, phase, cut, paste, undo]);

  /* ------------------------------- Toolbar ------------------------------- */
  const newFolder = () => {
    const side = activeSide === "right" && dual ? "right" : "left";
    if (levels[side] !== 2) {
      say(t.toasts.sample);
      return;
    }
    const set = side === "left" ? setLeft : setRight;
    set((prev) => {
      let name = t.toasts.newFolder;
      let n = 2;
      while (prev.some((p) => p.name === name)) name = `${t.toasts.newFolder} ${n++}`;
      return [{ name, size: "—", seed: "new", folder: true, fresh: true }, ...prev.map((p) => ({ ...p, fresh: false }))];
    });
  };
  const copyPath = async () => {
    const side = activeSide === "right" && dual ? "right" : "left";
    const p = posixPath(side);
    try {
      await navigator.clipboard.writeText(p);
    } catch {
      /* sin portapapeles: la demo sigue */
    }
    say(t.toasts.copied(p));
  };

  /* -------------------------------- Render -------------------------------- */
  const pane = (side: Side) => {
    const lv = levels[side];
    const list = lv === 2 ? (side === "left" ? left : right) : folderRows(side);
    const cr = crumbs(side).slice(0, lv + 1);
    const isActive = activeSide === side;
    return (
      <div
        ref={side === "left" ? leftRef : rightRef}
        className={`${s.pane} ${isActive ? s.paneActive : ""} ${side === "right" && hot ? s.paneHot : ""}`}
        onPointerDown={() => setActiveSide(side)}
      >
        <div className={s.paneHead}>
          <span>{side === "left" ? t.origin : t.destination}</span>
          {isActive ? <span className={s.badge}>{t.active}</span> : null}
        </div>
        <nav className={s.crumbs} aria-label={side === "left" ? t.origin : t.destination}>
          {cr.map((c, i) => {
            const isLast = i === cr.length - 1;
            const isSource = side === "left" && isLast && lv === 2;
            return (
              <span key={`${c}-${i}`} style={{ display: "contents" }}>
                {i > 0 ? <span className={s.crumbSep}>▸</span> : null}
                {isSource ? (
                  <button
                    type="button"
                    ref={(el) => {
                      srcRef.current = el;
                    }}
                    className={`${s.crumb} ${s.crumbCur} ${s.dragSrc}`}
                    onPointerDown={onDown}
                    onPointerMove={onMove}
                    onPointerUp={onUp}
                    onPointerCancel={onCancel}
                    onKeyDown={(e) => {
                      if (e.key === "Enter" || e.key === " ") {
                        e.preventDefault();
                        setHintOn(false);
                        autoDrop();
                      }
                    }}
                    aria-label={coarse ? t.tapHint : t.dragHint}
                  >
                    <span className={s.grip} aria-hidden="true" />
                    {c}
                  </button>
                ) : (
                  <button type="button" className={`${s.crumb} ${isLast ? s.crumbCur : ""}`} onClick={() => go(side, i as Level)} aria-current={isLast ? "location" : undefined}>
                    {c}
                  </button>
                )}
              </span>
            );
          })}
        </nav>
        <div className={s.cols}>
          <span>{t.cols.name}</span>
          <span style={{ textAlign: "right" }}>{t.cols.size}</span>
        </div>
        <div className={s.list} role="list">
          {list.map((item) => {
            const isFolderNav = lv < 2;
            const isDragRow = side === "left" && lv === 1 && item.seed === "f";
            const sel = side === "left" && lv === 2 && selected.includes(item.name);
            const isCut = side === "left" && lv === 2 && tray.includes(item.name);
            const cls = [s.row, isFolderNav ? s.folderRow : "", sel ? s.rowSel : "", isCut ? s.rowCut : "", item.fresh ? s.rowNew : ""].join(" ");
            return (
              <button
                key={item.name}
                type="button"
                role="listitem"
                className={cls}
                ref={
                  isDragRow
                    ? (el) => {
                        srcRef.current = el;
                      }
                    : undefined
                }
                onPointerDown={isDragRow ? onDown : undefined}
                onPointerMove={isDragRow ? onMove : undefined}
                onPointerUp={isDragRow ? onUp : undefined}
                onPointerCancel={isDragRow ? onCancel : undefined}
                style={isDragRow ? { touchAction: "none", cursor: "grab" } : undefined}
                onDoubleClick={isFolderNav && !isDragRow ? () => openFolder(side, item) : undefined}
                onClick={() => {
                  if (isDragRow) return;
                  if (isFolderNav) openFolder(side, item);
                  else if (side === "left") toggleSelect(item.name);
                  else setActiveSide("right");
                }}
                aria-pressed={side === "left" && lv === 2 ? sel : undefined}
              >
                <FileIcon item={item} />
                <span className={s.rowName}>{item.name}</span>
                <span className={`${s.rowSize} ${s.tnum}`}>{item.folder ? item.size : fmt(item.size)}</span>
              </button>
            );
          })}
        </div>
      </div>
    );
  };

  const counts = {
    fresh: items.filter((i) => i.kind === "new").length,
    conflict: items.filter((i) => i.kind === "conflict").length,
    same: items.filter((i) => i.kind === "same").length,
  };
  const toCopyCount = counts.fresh + counts.conflict;

  return (
    <div className={s.win} ref={winRef}>
      <div className={s.titlebar}>
        <div className={s.lights} aria-hidden="true">
          <i />
          <i />
          <i />
        </div>
        <span className={s.wtitle}>{t.windowTitle}</span>
      </div>

      <div className={s.toolbar} role="toolbar" aria-label="Findaro">
        <button type="button" className={s.tb} onClick={newFolder}>
          {t.toolbar.newFolder}
        </button>
        <button type="button" className={`${s.tb} ${dual ? s.tbOn : ""}`} aria-pressed={dual} onClick={() => setDual((d) => !d)}>
          {t.toolbar.dualPane} <kbd>{funnel.shortcuts.dualPane}</kbd>
        </button>
        <button type="button" className={s.tb} onClick={copyPath}>
          {t.toolbar.copyPath} <kbd>{funnel.shortcuts.copyPath}</kbd>
        </button>
        <button type="button" className={s.tb} onClick={() => say(t.toasts.dropover)}>
          {t.toolbar.dropover}
          {funnel.shortcuts.dropover ? <kbd>{funnel.shortcuts.dropover}</kbd> : null}
        </button>
        <button
          type="button"
          className={s.tb}
          onClick={() => document.getElementById("tools")?.scrollIntoView({ behavior: reduce.current ? "auto" : "smooth" })}
        >
          {t.toolbar.rename}
        </button>
      </div>

      <div className={`${s.panes} ${dual ? "" : s.panesSingle}`}>
        {pane("left")}
        {dual ? pane("right") : null}

        {phase !== "idle" ? (
          <div className={s.sheetBack}>
            <div className={s.sheet} role="dialog" aria-modal="false" aria-labelledby="merge-title">
              <h3 className={s.sheetT} id="merge-title">
                {t.sheet.title}
              </h3>
              <p className={s.sheetSub}>{t.sheet.sub}</p>
              <p className={s.sheetPath}>
                {posixPath("left").replace(/^\/Volumes\//, "")} → {["~", t.midRight, t.folder].join("/")}
              </p>
              <div className={`${s.pills} ${s.tnum}`}>
                <span className={`${s.pill} ${s.pillNew}`}>{t.sheet.newPill(counts.fresh)}</span>
                <span className={`${s.pill} ${s.pillBad}`}>{t.sheet.conflictPill(counts.conflict)}</span>
                <span className={`${s.pill} ${s.pillSame}`}>{t.sheet.samePill(counts.same)}</span>
              </div>
              <div className={s.flist}>
                {items.map((it) => (
                  <div key={it.name} className={s.frow}>
                    <span className={`${s.ck} ${it.hash ? s.ckOk : ""}`} aria-hidden="true" />
                    <span className={`${s.fname} ${it.kind === "conflict" && !it.hash ? s.fconf : ""} ${it.kind === "same" ? s.fsame : ""}`}>
                      {it.kind === "conflict" && it.hash && outcome !== "replaced" && phase === "done" ? withSuffix(it.name) : it.name}
                    </span>
                    <span className={`${s.fmeta} ${s.tnum}`}>
                      {it.hash
                        ? `${it.hash.slice(0, 12)}…`
                        : it.kind === "conflict"
                          ? `${fmt(it.size)} / ${fmt(it.destSize || "")}`
                          : it.kind === "new"
                            ? t.sheet.newTag
                            : t.sheet.sameTag}
                    </span>
                  </div>
                ))}
              </div>
              <p className={`${s.verif} ${s.tnum}`} aria-live="polite">
                {phase === "merging" ? t.sheet.verifying(verified, toCopyCount) : phase === "done" ? t.sheet.done(toCopyCount) : ""}
              </p>
              <div className={s.sheetActs}>
                {phase === "preview" ? (
                  <>
                    <span className={s.note}>{t.sheet.replaceNote}</span>
                    <button
                      type="button"
                      className={s.sb}
                      onClick={() => {
                        setPhase("idle");
                        say(t.toasts.cancelled);
                      }}
                    >
                      {t.sheet.cancel}
                    </button>
                    <button type="button" className={`${s.sb} ${s.sbOrange}`} onClick={() => runMerge(false)}>
                      {t.sheet.replace}
                    </button>
                    <button type="button" ref={primaryRef} className={`${s.sb} ${s.sbBlue}`} onClick={() => runMerge(true)}>
                      {t.sheet.keepBoth}
                    </button>
                  </>
                ) : null}
                {phase === "done" ? (
                  <>
                    <span className={s.note}>{outcome === "kept" ? t.sheet.keptNote : t.sheet.replacedNote}</span>
                    <button
                      type="button"
                      className={s.sb}
                      onClick={() => {
                        setPhase("idle");
                        say(t.toasts.closed);
                      }}
                    >
                      {t.sheet.close}
                    </button>
                    <button type="button" ref={primaryRef} className={`${s.sb} ${s.sbBlue}`} onClick={undo}>
                      {t.sheet.undo} {funnel.shortcuts.undo}
                    </button>
                  </>
                ) : null}
              </div>
            </div>
          </div>
        ) : null}
      </div>

      <div className={s.status}>
        <div className={s.statusL}>
          <span className={s.trayPill}>
            {t.tray} {funnel.shortcuts.cut}: <b className={s.tnum}>{tray.length ? t.trayItems(tray.length) : t.trayEmpty}</b>
          </span>
          <button type="button" className={s.mini} onClick={cut} disabled={!selected.length || phase !== "idle"}>
            {t.cutBtn} {funnel.shortcuts.cut}
          </button>
          <button type="button" className={`${s.mini} ${tray.length ? s.miniBlue : ""}`} onClick={paste} disabled={!tray.length || !dual || phase !== "idle"}>
            {t.pasteBtn} {funnel.shortcuts.paste}
          </button>
          {snapshot && phase === "idle" ? (
            <button type="button" className={s.mini} onClick={undo}>
              {t.sheet.undo} {funnel.shortcuts.undo}
            </button>
          ) : null}
        </div>
        {outcome && phase !== "merging" ? <span className={s.verifiedTag}>✓ SHA-256</span> : <span>{t.exampleData}</span>}
      </div>

      {hintOn && hintPos && phase === "idle" ? (
        <div className={s.hint} style={{ left: hintPos.x, top: hintPos.y }} aria-hidden="true">
          {coarse ? t.tapHint : t.dragHint}
        </div>
      ) : null}

      {ghostOn ? (
        <div
          ref={ghostRef}
          className={`${s.ghost} ${fly ? s.ghostFly : ""}`}
          style={{ transform: `translate(${ghostPos.current.x}px, ${ghostPos.current.y}px)` }}
          aria-hidden="true"
        >
          <FileIcon item={{ name: t.folder, size: "", seed: "", folder: true }} />
          {t.folder}
          <span className={s.tnum} style={{ opacity: 0.7, fontWeight: 500 }}>
            {t.folderItems(left.length)}
          </span>
        </div>
      ) : null}

      {toast ? (
        <div key={toast.id} className={s.toast} role="status">
          {toast.msg}
        </div>
      ) : null}
    </div>
  );
}
