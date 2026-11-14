/**
 * FINDARO · motor comercial de la landing (WEB_FACTORY).
 * Este es el único archivo que marketing necesita editar: precios, enlaces,
 * metadatos de confianza y todo el copy EN/ES. `es` está tipado como `Copy`
 * (= typeof en), así que las claves de ambos idiomas no se pueden desalinear.
 */
import type { Lang } from "@/lib/lang";

export type TierKey = "solo" | "pro" | "family";
/** Nombre del tier en Stripe/BD (histórico: Pro = "personal"). No renombrar. */
export type CheckoutTier = "solo" | "personal" | "family";

export const funnel = {
  product: "Findaro",
  version: "0.1.166",
  build: 158,
  minMacOS: "15",
  teamId: "YH6W55MP95",
  /** SHA-256 del .dmg publicado. Vacío = no se muestra en la web. */
  sha256: "d7637aadd3443b5d1bd086ad6023657639e00138e748d896f043180bd52fb2e8",
  /** ID del video de YouTube (solo el ID, no la URL). Vacío = se muestra el recorrido con capturas reales. */
  youtubeTutorialId: "",
  /** Sin "+" ni espacios, formato wa.me. Canal solo para dudas rápidas. */
  whatsappSupportNumber: "525645674407",
  supportEmail: { en: "support@findaro.iareal.net", es: "soporte@findaro.iareal.net" },
  siteUrl: "https://findaro.iareal.net",
  /**
   * Atajos que la web enseña. Deben existir en la app (AppHotkey.swift).
   * `dropover` está vacío porque v0.1.165 no trae atajo de teclado por defecto para Dropover
   * (solo el botón). Si se añade "⌥⇧D" en la app, escríbelo aquí y aparece en toda la web.
   */
  shortcuts: {
    cut: "⌘X",
    paste: "⌘V",
    undo: "⌘Z",
    pathBar: "⌘L",
    copyPath: "⌥⌘C",
    dualPane: "⇧⌘D",
    dropover: "⌥⇧D",
  },
  pricing: {
    trialDays: 14,
    guaranteeDays: 14,
    currency: "USD",
    /** Precios fijos de pago único. compareAt = precio regular tachado (Founder Launch Price). */
    tiers: [
      { key: "solo", checkoutTier: "solo", price: 29, compareAt: null, seats: 1, recommended: false },
      { key: "pro", checkoutTier: "personal", price: 39, compareAt: 59, seats: 2, recommended: true },
      { key: "family", checkoutTier: "family", price: 59, compareAt: 79, seats: 5, recommended: false },
    ] as const,
  },
  /** Comparativa a 3 años. Precios públicos de referencia (nov 2026). Sin enlaces a terceros. */
  savings: {
    pathFinderYearMin: 32,
    pathFinderYearMax: 36,
    suiteMonthly: 9.99,
    findaroPro: 39,
  },
  /** Capturas reales de la app (interfaz en español). */
  screenshots: {
    dualPane: { src: "/screenshots/findaro-in-dual-pane-mode.webp", w: 1082, h: 694 },
    search: { src: "/screenshots/extracted-fe98458bfcd190c0.webp", w: 1076, h: 748 },
    merge: { src: "/screenshots/smart-merge-dialog-0-new.webp", w: 583, h: 523 },
    trash: { src: "/screenshots/papelera-restaurar.webp", w: 490, h: 430 },
    ollama: { src: "/screenshots/assistant-settings-optional-ollama-active.webp", w: 556, h: 588 },
    voice: { src: "/screenshots/asistente-microfono.webp", w: 310, h: 567 },
    tray: { src: "/screenshots/clipboard-tray-with-multiple-files.webp", w: 1072, h: 130 },
    headers: { src: "/screenshots/dual-pane-headers-origin-and.webp", w: 1074, h: 90 },
  },
} as const;

export type FunnelTier = (typeof funnel.pricing.tiers)[number];

export function trialHref(lang: Lang): string {
  return `/probar?dl=1&lang=${lang}`;
}

export function buyHref(tier: CheckoutTier, lang: Lang): string {
  return `/comprar?tier=${tier}&lang=${lang}`;
}

export function whatsappHref(message: string): string {
  return `https://wa.me/${funnel.whatsappSupportNumber}?text=${encodeURIComponent(message)}`;
}

export function money(n: number, lang: Lang, decimals = 0): string {
  const s = n.toFixed(decimals);
  return lang === "es" ? `$${s}` : `$${s}`;
}

/* ------------------------------------------------------------------ */
/* Copy                                                                */
/* ------------------------------------------------------------------ */

const en = {
  meta: {
    title: "Findaro — Merge folders on your Mac without losing a file",
    description:
      "Native macOS file manager: two panes, real ⌘X, Smart Merge with SHA-256 checks, 2-phase batch rename with ⌘Z, local voice and AI. 14-day free trial, no card. One payment from $29.",
    ogLocale: "en_US",
    ogImage: "/og-en.png",
  },
  skip: "Skip to content",
  nav: {
    features: "Features",
    tools: "Pro tools",
    compare: "Compare",
    pricing: "Pricing",
    faq: "FAQ",
    download: "Download free",
    langLabel: "Language",
  },
  hero: {
    eyebrow: "Findaro 0.1.166 · macOS 15+ · Apple Silicon",
    title: "Merge two folders without losing a single file.",
    sub: "Findaro is a native Mac file manager with two panes, a ⌘X that really cuts, and a Smart Merge that shows every conflict before it copies, checks each file with SHA-256 and rolls back on its own if anything fails halfway.",
    primary: "Download free for 14 days",
    secondary: "See pricing",
    trust: ["Signed and notarized by Apple", "No card for the trial", "One payment from $29"],
    demoNote: "Live demo with example files. The SHA-256 hashes are computed in your browser.",
  },
  demo: {
    windowTitle: "Findaro — Cliente-2026",
    toolbar: { newFolder: "+ New", dualPane: "2 panes", copyPath: "Path", dropover: "Dropover", rename: "Rename" },
    origin: "Origin",
    destination: "Destination",
    active: "active",
    cols: { name: "Name", size: "Size" },
    rootLeft: "SSD_Externo",
    midLeft: "Deliveries",
    rootRight: "~",
    midRight: "Projects",
    folder: "Cliente-2026",
    folderItems: (n: number) => `${n} items`,
    sampleFolders: { left: ["Cliente-2025", "Templates"], leftRoot: ["RAW-Backups", "Music"], right: ["Archive", "Invoices"], rightRoot: ["Documents", "Downloads"] },
    dragHint: "Drag Cliente-2026 onto the right pane",
    tapHint: "Tap Cliente-2026 to merge it",
    dropHere: "Drop to preview the merge",
    tray: "Tray",
    trayEmpty: "empty",
    trayItems: (n: number) => `${n} cut`,
    cutBtn: "Cut",
    pasteBtn: "Paste into destination",
    sheet: {
      title: "Merge folders",
      sub: "Nothing has been touched yet.",
      newPill: (n: number) => `${n} new`,
      conflictPill: (n: number) => `${n} in conflict`,
      samePill: (n: number) => `${n} identical, skipped`,
      newTag: "new",
      sameTag: "identical",
      keepBoth: "Keep both",
      replace: "Replace and move",
      cancel: "Cancel",
      replaceNote: "With Replace, the old version goes to the Trash.",
      verifying: (n: number, t: number) => `Verified ${n}/${t} · copy SHA-256 = original SHA-256`,
      done: (n: number) => `${n}/${n} copied and verified · 0 files lost`,
      keptNote: "Conflicts were kept as “name 2”.",
      replacedNote: "The old versions are in the Trash.",
      undo: "Undo",
      close: "Close",
    },
    toasts: {
      copied: (p: string) => `Copied: ${p}`,
      dropover: "Selection sent to Dropover (demo).",
      newFolder: "untitled folder",
      sample: "Example folder. Open Cliente-2026 to try the merge.",
      needDual: "Turn on 2 panes to merge.",
      undone: "Undone. The destination is back to how it was.",
      cancelled: "Cancelled. Nothing was copied.",
      closed: "Done. The origin is untouched: Smart Merge copies, it doesn't move.",
      cut: (n: number) => `${n} in the tray. Paste them into the destination.`,
      pasted: (n: number) => `Moved ${n} into the destination.`,
    },
    exampleData: "example data",
    files: {
      fresh: ["Master-4K.mov", "RAW-042.dng", "RAW-043.dng", "RAW-044.dng", "Color-Grade.drp", "Subtitles-EN.srt", "Final-Mix.wav", "Thumbnail.psd", "Delivery-Notes.md"],
      conflict: ["Contrato-Firmado.pdf", "UI-Kit.fig", "Build-Release.zip"],
      same: ["Logo.svg", "Brief.pdf", "Invoice-0412.pdf", "Fonts.zip"],
      destOnly: ["Proposal.key", "Schedule.numbers"],
    },
  },
  facts: [
    { k: "SHA-256", v: "checked on every copied file before it counts as done" },
    { k: "2 phases", v: "for batch renames, so no name ever overwrites another" },
    { k: "0", v: "background daemons installed on your Mac" },
    { k: "0", v: "of your files sent to the cloud by voice or AI" },
  ],
  story: {
    title: "Five things you'll use every day.",
    sub: "Real screenshots of the app. The interface shown is in Spanish; English is built in.",
    items: [
      {
        title: "Two panes in one click. A cut that actually cuts.",
        body: "Origin on the left, destination on the right, ⇧⌘D to toggle. ⌘X puts files in a tray that stays put while you change folders, so you paste them wherever you end up.",
        chip: "⌘X · ⌘V · ⇧⌘D",
        shot: "dualPane",
        alt: "Findaro in dual-pane mode with origin and destination folders",
      },
      {
        title: "Every conflict on screen before anything moves.",
        body: "New, identical and conflicting files, listed. Copies go to temporary files, get checked with SHA-256 and only then take their place. If one fails, the whole batch rolls back. Finder only offers Stop or Replace.",
        chip: "SHA-256 · rollback",
        shot: "merge",
        alt: "Findaro's Merge folders dialog with new, identical and different files",
      },
      {
        title: "Get anywhere without touching the mouse.",
        body: "Click any breadcrumb in either pane, or press ⌘L and type with Tab completion. ⌥⌘C copies the POSIX path for Terminal, and the Dropover button sends your selection in one click.",
        chip: "⌘L · Tab · ⌥⌘C",
        shot: "search",
        alt: "Findaro searching inside subfolders with the path bar visible",
      },
      {
        title: "Rename hundreds of files. Undo with ⌘Z.",
        body: "Regex, sequences, prefixes, suffixes and case, applied in two phases so no name steps on another. One click also clears the .DS_Store and ._* junk macOS leaves on USB drives and SMB/NAS shares.",
        chip: "Regex · ⌘Z · .DS_Store",
        shot: "",
        alt: "",
      },
      {
        title: "Native AppKit. Voice and AI that stay on your Mac.",
        body: "Lists run on virtualized NSTableView, smooth up to 120 Hz on ProMotion displays, and nothing keeps running in the background. Hold ⌃Space and say what you need: local rules answer right away, and Ollama is optional.",
        chip: "NSTableView · ⌃Space · Ollama",
        shot: "voice",
        alt: "Findaro's local assistant listening after holding Control-Space",
      },
    ],
    renameStage: { big: "2 phases", sub: "RAW-042.dng · temp · Cliente-2026-001.dng" },
  },
  tools: {
    title: "Pro tools you can try right here.",
    sub: "The same flow as in the app: type a path, preview every new name, apply it in two phases, undo it.",
    rename: {
      windowTitle: "Batch Rename — Cliente-2026",
      find: "Find (regex)",
      replace: "Replace with · $1, {n:03}",
      chips: [
        { label: "Sequence", f: "RAW-(\\d+)", r: "Cliente-2026-{n:03}" },
        { label: "Short sequence (collides)", f: "RAW-(\\d+)", r: "Cliente-{n:03}" },
        { label: "Date prefix", f: "^RAW-", r: "2026-11-14_RAW-" },
        { label: "Lowercase extension", f: "\\.DNG$", r: ".dng" },
      ],
      before: "Before",
      after: "After",
      stat: (total: number, matched: number, changed: number) => `${total} files · ${matched} match · ${changed} change`,
      collisions: (n: number) => `${n} collisions: not applied until resolved`,
      noCollisions: "0 collisions",
      apply: "Apply",
      undo: "Undo ⌘Z",
      phase1: "Phase 1/2 · temporary names",
      phase2: "Phase 2/2 · final names",
      applied: (n: number) => `Done: ${n} files renamed. ⌘Z to undo.`,
      undone: "Undone: the original names are back.",
      ready: "No collisions. Press Apply.",
      tab: "Tab",
      tree: {
        "~/": ["Desktop", "Documents", "Downloads", "Projects"],
        "~/Projects/": ["Cliente-2026", "Cliente-2025", "Templates"],
        "~/Projects/Cliente-2026/": [],
        "/Volumes/": ["SSD_Externo", "NAS-Studio"],
      } as Record<string, string[]>,
      autotypeA: "~/Proj",
      autotypeB: "Cl",
      pathLabel: "Editable path bar",
      note: "Example data. The two-phase apply is the same logic as the app's BatchRenameExecutor.",
    },
    copyPath: {
      title: "Copy path",
      body: "The full POSIX path of the folder, ready to paste into Terminal.",
      button: "Copy path",
      done: "Copied",
      path: "/Volumes/SSD_Externo/Deliveries/Cliente-2026",
    },
    dropover: {
      title: "Send to Dropover",
      body: "Your selection lands on Dropover's shelf in one click. Needs Dropover installed.",
      button: "Send selection",
      done: "Sent (demo)",
    },
    cleanup: {
      title: "Clean .DS_Store and ._*",
      body: "The junk macOS leaves on USB drives and SMB/NAS shares, gone in one click. Your own files aren't touched.",
      button: "Clean this USB drive",
      done: (n: number) => `${n} junk files removed · 0 of your files touched`,
      files: [".DS_Store", "._Master-4K.mov", "._RAW-042.dng", "Fotos/.DS_Store", "._Contrato-Firmado.pdf", "Audio/._Final-Mix.wav"],
      keep: ["Master-4K.mov", "RAW-042.dng", "Contrato-Firmado.pdf"],
    },
  },
  tour: {
    title: "A quick look at the real app.",
    sub: "Screenshots of Findaro 0.1.x. The interface shown is in Spanish; English is built in.",
    play: "Play the Findaro tutorial",
    slides: [
      { shot: "dualPane", caption: "Two panes with origin and destination" },
      { shot: "search", caption: "Search inside subfolders" },
      { shot: "merge", caption: "Merge folders with a full preview" },
      { shot: "trash", caption: "Restore from the Trash to the original path" },
      { shot: "ollama", caption: "Optional Ollama, running on your Mac" },
      { shot: "voice", caption: "Hold ⌃Space and talk" },
    ],
    tabsLabel: "App screenshots",
  },
  compare: {
    title: "What you pay over three years.",
    sub: "Findaro is a one-time purchase. Here is the same three years with the usual alternatives.",
    cols: { app: "Option", y1: "Year 1", y2: "Year 2", y3: "Year 3", total: "3 years" },
    rows: {
      findaro: { name: "Findaro Pro (2 Macs)", note: "Lifetime license. Keeps working even if you never pay again." },
      pathfinder: { name: "Path Finder (yearly subscription)", note: "1 Mac. Stop paying and you lose access or updates." },
      suite: { name: "Setapp / subscription suite", note: "Rent that never ends." },
      finder: { name: "Finder (included in macOS)", note: "No native dual pane, no ⌘X for files, no SHA-256 merge preview, no regex rename with ⌘Z." },
    },
    perMonth: "/mo",
    footnote: "Public reference prices as of November 2026. Findaro has no affiliation with these products; trademarks belong to their owners.",
    matrixToggle: "See the full technical matrix (52 features)",
    legend: "✓ included · ~ similar or partial · — not documented",
    fullPage: "Open the comparison page",
    feature: "Feature",
  },
  pricing: {
    title: "Pay once. It's yours.",
    sub: "14-day trial without a card. 14-day money-back guarantee, no questions asked.",
    launch: "Founder launch price",
    names: { solo: "Solo", pro: "Pro", family: "Family" },
    seats: { solo: "1 Mac", pro: "2 Macs · desktop + MacBook", family: "5 Macs" },
    once: "USD · one time",
    was: (n: number) => `was $${n}`,
    perMac: (v: string) => `${v} per Mac`,
    recommended: "Recommended",
    includes: ["Lifetime license", "Updates included", "Smart Merge, Batch Rename, voice and local AI"],
    familyExtra: "Priority support",
    cta: { solo: "Buy Solo", pro: "Buy Pro", family: "Buy Family" },
    trialCta: "Or try it free for 14 days",
  },
  faq: {
    title: "Questions people ask before buying.",
    items: [
      { q: "Does Findaro replace Finder?", a: "No. It runs alongside it. Finder stays where it is, and you open Findaro when you want two panes, Smart Merge or batch rename." },
      { q: "What do I need?", a: "A Mac with Apple Silicon (M1 or newer) and macOS 15 or later." },
      { q: "What happens when the 14 days are over?", a: "Findaro switches to read-only: you can keep browsing, but copying, moving and renaming need a license. Nobody ever asked for your card." },
      { q: "Does anything leave my Mac?", a: "Your files don't. Voice uses Apple's on-device speech recognition and the rules run locally; Ollama is optional and also runs on your Mac. Only the license check and update check talk to our server, and they never include your files." },
      { q: "Can I move my license to another Mac?", a: "Yes. Free the seat from the License sheet in Findaro, then activate it on the other Mac." },
      { q: "How does the refund work?", a: "Write to us within 14 days of your purchase and we refund you. No questions." },
      { q: "Is it safe to install?", a: "The .dmg is signed with Apple Developer ID (Team ID YH6W55MP95) and notarized by Apple, so macOS opens it without Gatekeeper warnings." },
    ],
  },
  final: {
    title: "Try it on your messiest folder.",
    sub: "14 days, every feature, no card. If it doesn't earn its place on your Dock, you've lost nothing.",
    primary: "Download free for 14 days",
    secondary: "Buy Pro for $39",
  },
  footer: {
    tagline: "A native file manager for macOS, made by an indie studio.",
    links: { compare: "Compare", support: "Support", privacy: "Privacy", terms: "Terms", refund: "Refunds" },
    team: "Apple Developer Team ID",
    version: "Version",
    sha: "DMG SHA-256",
    rights: "Findaro. Mac, macOS, Finder and ProMotion are trademarks of Apple Inc.",
  },
  whatsapp: {
    label: "Questions about Findaro? WhatsApp",
    tooltip: "Questions about Findaro? Direct WhatsApp. Only for quick questions before buying or activating.",
    message: "Hi! I have a quick question about Findaro:",
    close: "Close",
    open: "Open WhatsApp",
  },
};

export type Copy = typeof en;

const es: Copy = {
  meta: {
    title: "Findaro — Junta carpetas en tu Mac sin perder un archivo",
    description:
      "Gestor de archivos nativo para macOS: dos paneles, ⌘X real, Smart Merge con verificación SHA-256, renombrado por lotes en 2 fases con ⌘Z, voz e IA locales. Prueba 14 días sin tarjeta. Pago único desde $29.",
    ogLocale: "es_MX",
    ogImage: "/og-es.png",
  },
  skip: "Saltar al contenido",
  nav: {
    features: "Funciones",
    tools: "Herramientas Pro",
    compare: "Comparar",
    pricing: "Precios",
    faq: "Preguntas",
    download: "Descargar gratis",
    langLabel: "Idioma",
  },
  hero: {
    eyebrow: "Findaro 0.1.166 · macOS 15+ · Apple Silicon",
    title: "Junta dos carpetas sin perder un solo archivo.",
    sub: "Findaro es un gestor de archivos nativo para Mac con dos paneles, un ⌘X que corta de verdad y un Smart Merge que te enseña cada conflicto antes de copiar, verifica cada archivo con SHA-256 y revierte solo si algo falla a medias.",
    primary: "Descargar gratis 14 días",
    secondary: "Ver precios",
    trust: ["Firmado y notarizado por Apple", "Sin tarjeta en la prueba", "Pago único desde $29"],
    demoNote: "Demo en vivo con archivos de ejemplo. Los SHA-256 se calculan en tu navegador.",
  },
  demo: {
    windowTitle: "Findaro — Cliente-2026",
    toolbar: { newFolder: "+ Nueva", dualPane: "2 paneles", copyPath: "Ruta", dropover: "Dropover", rename: "Renombrar" },
    origin: "Origen",
    destination: "Destino",
    active: "activo",
    cols: { name: "Nombre", size: "Tamaño" },
    rootLeft: "SSD_Externo",
    midLeft: "Entregas",
    rootRight: "~",
    midRight: "Proyectos",
    folder: "Cliente-2026",
    folderItems: (n: number) => `${n} elementos`,
    sampleFolders: { left: ["Cliente-2025", "Plantillas"], leftRoot: ["RAW-Respaldos", "Música"], right: ["Archivo", "Facturas"], rightRoot: ["Documentos", "Descargas"] },
    dragHint: "Arrastra Cliente-2026 al panel derecho",
    tapHint: "Toca Cliente-2026 para fusionarla",
    dropHere: "Suelta para ver la vista previa",
    tray: "Bandeja",
    trayEmpty: "vacía",
    trayItems: (n: number) => `${n} cortados`,
    cutBtn: "Cortar",
    pasteBtn: "Pegar en destino",
    sheet: {
      title: "Fusionar carpetas",
      sub: "Todavía no se ha tocado nada.",
      newPill: (n: number) => `${n} nuevos`,
      conflictPill: (n: number) => `${n} en conflicto`,
      samePill: (n: number) => `${n} idénticos omitidos`,
      newTag: "nuevo",
      sameTag: "idéntico",
      keepBoth: "Conservar ambos",
      replace: "Reemplazar y mover",
      cancel: "Cancelar",
      replaceNote: "Con Reemplazar, la versión vieja va a la Papelera.",
      verifying: (n: number, t: number) => `Verificados ${n}/${t} · SHA-256 de la copia = SHA-256 del original`,
      done: (n: number) => `${n}/${n} copiados y verificados · 0 archivos perdidos`,
      keptNote: "Los conflictos se guardaron como «nombre 2».",
      replacedNote: "Las versiones viejas están en la Papelera.",
      undo: "Deshacer",
      close: "Cerrar",
    },
    toasts: {
      copied: (p: string) => `Copiada: ${p}`,
      dropover: "Selección enviada a Dropover (demo).",
      newFolder: "carpeta sin título",
      sample: "Carpeta de ejemplo. Abre Cliente-2026 para probar la fusión.",
      needDual: "Activa 2 paneles para fusionar.",
      undone: "Deshecho. El destino quedó como estaba.",
      cancelled: "Cancelado. No se copió nada.",
      closed: "Listo. El origen sigue intacto: Smart Merge copia, no mueve.",
      cut: (n: number) => `${n} en la bandeja. Pégalos en el destino.`,
      pasted: (n: number) => `Movidos ${n} al destino.`,
    },
    exampleData: "datos de ejemplo",
    files: {
      fresh: ["Master-4K.mov", "RAW-042.dng", "RAW-043.dng", "RAW-044.dng", "Color-Grade.drp", "Subtitulos-ES.srt", "Mezcla-Final.wav", "Miniatura.psd", "Notas-Entrega.md"],
      conflict: ["Contrato-Firmado.pdf", "UI-Kit.fig", "Build-Release.zip"],
      same: ["Logo.svg", "Brief.pdf", "Factura-0412.pdf", "Fuentes.zip"],
      destOnly: ["Propuesta.key", "Calendario.numbers"],
    },
  },
  facts: [
    { k: "SHA-256", v: "en cada archivo copiado antes de darlo por hecho" },
    { k: "2 fases", v: "en el renombrado por lotes: ningún nombre pisa a otro" },
    { k: "0", v: "procesos en segundo plano instalados en tu Mac" },
    { k: "0", v: "archivos tuyos enviados a la nube por la voz o la IA" },
  ],
  story: {
    title: "Cinco cosas que vas a usar todos los días.",
    sub: "Capturas reales de la app.",
    items: [
      {
        title: "Dos paneles en un clic. Un cortar que sí corta.",
        body: "Origen a la izquierda, destino a la derecha, ⇧⌘D para alternar. ⌘X manda los archivos a una bandeja que no se pierde aunque cambies de carpeta, y los pegas donde termines.",
        chip: "⌘X · ⌘V · ⇧⌘D",
        shot: "dualPane",
        alt: "Findaro en modo de dos paneles con carpetas de origen y destino",
      },
      {
        title: "Cada conflicto a la vista antes de mover nada.",
        body: "Nuevos, idénticos y en conflicto, en una lista. Las copias van a temporales, se verifican con SHA-256 y solo entonces ocupan su lugar. Si una falla, se revierte todo el lote. Finder solo te ofrece Detener o Reemplazar.",
        chip: "SHA-256 · rollback",
        shot: "merge",
        alt: "Diálogo Fusionar carpetas de Findaro con archivos nuevos, iguales y distintos",
      },
      {
        title: "Llega a cualquier carpeta sin tocar el ratón.",
        body: "Haz clic en cualquier tramo de la ruta en cualquiera de los dos paneles, o pulsa ⌘L y escribe con autocompletado por Tab. ⌥⌘C copia la ruta POSIX para la Terminal, y el botón Dropover envía tu selección en un clic.",
        chip: "⌘L · Tab · ⌥⌘C",
        shot: "search",
        alt: "Findaro buscando dentro de subcarpetas con la barra de ruta visible",
      },
      {
        title: "Renombra cientos de archivos. Deshaz con ⌘Z.",
        body: "Regex, secuencias, prefijos, sufijos y mayúsculas, aplicados en dos fases para que ningún nombre pise a otro. Con un clic también borras los .DS_Store y ._* que macOS deja en memorias USB y en carpetas SMB/NAS.",
        chip: "Regex · ⌘Z · .DS_Store",
        shot: "",
        alt: "",
      },
      {
        title: "AppKit nativo. Voz e IA que no salen de tu Mac.",
        body: "Las listas usan NSTableView virtualizado, fluidas hasta 120 Hz en pantallas ProMotion, y no queda nada corriendo en segundo plano. Mantén ⌃Espacio y di lo que necesitas: las reglas locales responden al instante y Ollama es opcional.",
        chip: "NSTableView · ⌃Espacio · Ollama",
        shot: "voice",
        alt: "El asistente local de Findaro escuchando tras mantener Control-Espacio",
      },
    ],
    renameStage: { big: "2 fases", sub: "RAW-042.dng · temporal · Cliente-2026-001.dng" },
  },
  tools: {
    title: "Herramientas Pro que puedes probar aquí mismo.",
    sub: "El mismo flujo que en la app: escribe una ruta, revisa cada nombre nuevo, aplícalo en dos fases y deshazlo.",
    rename: {
      windowTitle: "Renombrar en lote — Cliente-2026",
      find: "Buscar (regex)",
      replace: "Reemplazar por · $1, {n:03}",
      chips: [
        { label: "Secuencia", f: "RAW-(\\d+)", r: "Cliente-2026-{n:03}" },
        { label: "Secuencia corta (choca)", f: "RAW-(\\d+)", r: "Cliente-{n:03}" },
        { label: "Prefijo con fecha", f: "^RAW-", r: "2026-11-14_RAW-" },
        { label: "Extensión en minúsculas", f: "\\.DNG$", r: ".dng" },
      ],
      before: "Antes",
      after: "Después",
      stat: (total: number, matched: number, changed: number) => `${total} archivos · ${matched} coinciden · ${changed} cambian`,
      collisions: (n: number) => `${n} colisiones: no se aplica hasta resolverlas`,
      noCollisions: "0 colisiones",
      apply: "Aplicar",
      undo: "Deshacer ⌘Z",
      phase1: "Fase 1/2 · nombres temporales",
      phase2: "Fase 2/2 · nombres finales",
      applied: (n: number) => `Listo: ${n} archivos renombrados. ⌘Z para deshacer.`,
      undone: "Deshecho: los nombres originales están de vuelta.",
      ready: "Sin colisiones. Pulsa Aplicar.",
      tab: "Tab",
      tree: {
        "~/": ["Descargas", "Documentos", "Escritorio", "Proyectos"],
        "~/Proyectos/": ["Cliente-2026", "Cliente-2025", "Plantillas"],
        "~/Proyectos/Cliente-2026/": [],
        "/Volumes/": ["SSD_Externo", "NAS-Estudio"],
      } as Record<string, string[]>,
      autotypeA: "~/Proy",
      autotypeB: "Cl",
      pathLabel: "Barra de ruta editable",
      note: "Datos de ejemplo. La aplicación en dos fases es la misma lógica de BatchRenameExecutor en la app.",
    },
    copyPath: {
      title: "Copiar ruta",
      body: "La ruta POSIX completa de la carpeta, lista para pegar en la Terminal.",
      button: "Copiar ruta",
      done: "Copiada",
      path: "/Volumes/SSD_Externo/Entregas/Cliente-2026",
    },
    dropover: {
      title: "Enviar a Dropover",
      body: "Tu selección cae en la bandeja de Dropover en un clic. Requiere tener Dropover instalado.",
      button: "Enviar selección",
      done: "Enviada (demo)",
    },
    cleanup: {
      title: "Limpiar .DS_Store y ._*",
      body: "La basura que macOS deja en memorias USB y en carpetas SMB/NAS, fuera en un clic. Tus archivos no se tocan.",
      button: "Limpiar esta memoria USB",
      done: (n: number) => `${n} archivos basura eliminados · 0 archivos tuyos tocados`,
      files: [".DS_Store", "._Master-4K.mov", "._RAW-042.dng", "Fotos/.DS_Store", "._Contrato-Firmado.pdf", "Audio/._Mezcla-Final.wav"],
      keep: ["Master-4K.mov", "RAW-042.dng", "Contrato-Firmado.pdf"],
    },
  },
  tour: {
    title: "Un vistazo a la app real.",
    sub: "Capturas de Findaro 0.1.x.",
    play: "Reproducir el tutorial de Findaro",
    slides: [
      { shot: "dualPane", caption: "Dos paneles con origen y destino" },
      { shot: "search", caption: "Búsqueda dentro de subcarpetas" },
      { shot: "merge", caption: "Fusionar carpetas con vista previa completa" },
      { shot: "trash", caption: "Restaurar de la Papelera a su ruta original" },
      { shot: "ollama", caption: "Ollama opcional, corriendo en tu Mac" },
      { shot: "voice", caption: "Mantén ⌃Espacio y habla" },
    ],
    tabsLabel: "Capturas de la app",
  },
  compare: {
    title: "Lo que pagas en tres años.",
    sub: "Findaro se paga una vez. Estos son los mismos tres años con las alternativas de siempre.",
    cols: { app: "Opción", y1: "Año 1", y2: "Año 2", y3: "Año 3", total: "3 años" },
    rows: {
      findaro: { name: "Findaro Pro (2 Macs)", note: "Licencia de por vida. Sigue funcionando aunque no vuelvas a pagar." },
      pathfinder: { name: "Path Finder (suscripción anual)", note: "1 Mac. Si dejas de pagar, pierdes acceso o actualizaciones." },
      suite: { name: "Setapp / suite por suscripción", note: "Una renta que no se acaba." },
      finder: { name: "Finder (incluido en macOS)", note: "Sin doble panel nativo, sin ⌘X para archivos, sin vista previa SHA-256 al fusionar y sin renombrado regex con ⌘Z." },
    },
    perMonth: "/mes",
    footnote: "Precios públicos de referencia a noviembre de 2026. Findaro no tiene relación con estos productos; las marcas son de sus dueños.",
    matrixToggle: "Ver la matriz técnica completa (52 funciones)",
    legend: "✓ incluido · ~ similar o parcial · — no documentado",
    fullPage: "Abrir la página de comparación",
    feature: "Función",
  },
  pricing: {
    title: "Pagas una vez. Es tuyo.",
    sub: "Prueba de 14 días sin tarjeta. Garantía de reembolso de 14 días, sin preguntas.",
    launch: "Precio de fundador",
    names: { solo: "Solo", pro: "Pro", family: "Family" },
    seats: { solo: "1 Mac", pro: "2 Macs · escritorio + MacBook", family: "5 Macs" },
    once: "USD · una vez",
    was: (n: number) => `antes $${n}`,
    perMac: (v: string) => `${v} por Mac`,
    recommended: "Recomendado",
    includes: ["Licencia de por vida", "Actualizaciones incluidas", "Smart Merge, Batch Rename, voz e IA local"],
    familyExtra: "Soporte prioritario",
    cta: { solo: "Comprar Solo", pro: "Comprar Pro", family: "Comprar Family" },
    trialCta: "O pruébalo gratis 14 días",
  },
  faq: {
    title: "Lo que la gente pregunta antes de comprar.",
    items: [
      { q: "¿Findaro reemplaza a Finder?", a: "No. Trabaja a su lado. Finder sigue donde está y abres Findaro cuando quieres dos paneles, Smart Merge o renombrar en lote." },
      { q: "¿Qué necesito?", a: "Un Mac con Apple Silicon (M1 o posterior) y macOS 15 o superior." },
      { q: "¿Qué pasa cuando terminan los 14 días?", a: "Findaro pasa a solo lectura: puedes seguir navegando, pero copiar, mover y renombrar necesitan licencia. Nunca te pedimos la tarjeta." },
      { q: "¿Sale algo de mi Mac?", a: "Tus archivos no. La voz usa el reconocimiento de Apple en el propio Mac y las reglas corren en local; Ollama es opcional y también corre en tu equipo. Solo la verificación de licencia y la búsqueda de actualizaciones hablan con nuestro servidor, y nunca incluyen tus archivos." },
      { q: "¿Puedo pasar mi licencia a otro Mac?", a: "Sí. Libera el puesto desde la hoja de Licencia en Findaro y actívala en el otro Mac." },
      { q: "¿Cómo funciona el reembolso?", a: "Escríbenos dentro de los 14 días siguientes a tu compra y te devolvemos el dinero. Sin preguntas." },
      { q: "¿Es seguro instalarlo?", a: "El .dmg está firmado con Apple Developer ID (Team ID YH6W55MP95) y notarizado por Apple, así que macOS lo abre sin alertas de Gatekeeper." },
    ],
  },
  final: {
    title: "Pruébalo con tu carpeta más desordenada.",
    sub: "14 días, todas las funciones, sin tarjeta. Si no se gana su lugar en tu Dock, no pierdes nada.",
    primary: "Descargar gratis 14 días",
    secondary: "Comprar Pro por $39",
  },
  footer: {
    tagline: "Un gestor de archivos nativo para macOS, hecho por un estudio independiente.",
    links: { compare: "Comparar", support: "Soporte", privacy: "Privacidad", terms: "Términos", refund: "Reembolsos" },
    team: "Apple Developer Team ID",
    version: "Versión",
    sha: "SHA-256 del DMG",
    rights: "Findaro. Mac, macOS, Finder y ProMotion son marcas de Apple Inc.",
  },
  whatsapp: {
    label: "¿Dudas sobre Findaro? WhatsApp",
    tooltip: "¿Dudas sobre Findaro? WhatsApp directo. Solo para dudas rápidas antes de comprar o activar.",
    message: "¡Hola! Tengo una duda rápida sobre Findaro:",
    close: "Cerrar",
    open: "Abrir WhatsApp",
  },
};

export const COPY: Record<Lang, Copy> = { en, es };

export type ShotKey = keyof typeof funnel.screenshots;
