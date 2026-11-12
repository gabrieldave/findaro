(() => {
  "use strict";

  const root =
    document.getElementById("comparar") ||
    document.querySelector(".findaro-compare-embed");
  if (!root) return;
  const isEn = document.documentElement.lang.toLowerCase().startsWith("en");

  const names = {
    forklift: "ForkLift 4",
    bloom: "Bloom",
    qspace: "QSpace Pro",
    pathfinder: "Path Finder",
    commander: "Commander One",
    finder: isEn ? "Apple Finder" : "Finder de Apple",
  };
  const selections = {
    esencial: [51, 48, 32, 52, 13, 11, 12, 8, 3, 22],
    seguridad: [11, 12, 13, 14, 15, 16, 42, 48],
    ia: [15, 16, 17, 18, 19, 20, 21],
    transferencias: [3, 4, 5, 6, 7, 8, 9, 10, 13],
    productividad: [
      51, 48, 32, 52, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 33, 34, 35, 36, 37, 38, 39, 40,
      41, 42, 43, 44, 45,
    ],
    rival: [46, 47, 49, 50],
  };
  const newNames = {
    11: "Integridad SHA-256 de las transferencias",
    12: "Recuperación de lote ante fallos",
    13: "Smart Merge con vista previa",
    15: "Aprobación antes de cambios realizados por la IA",
    17: "Asistente local con Ollama (opcional)",
    18: "Voz local: mantén y habla",
    8: "Cortar ⌘X y pegar ⌘V",
    3: "Doble panel Origen y Destino",
    22: "Búsqueda en subcarpetas",
    32: "Barra de ruta editable (⌘L + Tab)",
    34: "Perfil de teclado tipo Windows",
    46: "Conexiones FTP / SFTP / servicios remotos",
    48: "Renombrado masivo Pro (⌘Z transaccional)",
    51: "Motor de lista AppKit ultrarrápido (120 fps)",
    52: "Higiene en unidades externas y SMB/NAS",
  };
  const descriptions = {
    11: "Comprueba que los archivos transferidos conservan su contenido.",
    12: "Si falla un elemento, intenta revertir las operaciones del lote.",
    13: "Distingue contenido nuevo, igual y en conflicto antes de fusionar.",
    15: "El agente presenta el plan y solicita aprobación para modificar archivos.",
    17: "IA local optativa. El explorador funciona también sin modelos.",
    18: "Dictado y órdenes sin exigir un servidor de voz externo.",
    8: "El flujo familiar de Explorer aplicado a la bandeja de FINDARO.",
    3: "Mantén a la vista la carpeta de origen y la de destino.",
    22: "El buscador integrado recorre nombres de archivos en subcarpetas.",
    32: "Navega por teclado a cualquier ruta con autocompletado instantáneo por Tab.",
    34: "Adaptación para quien viene de Windows.",
    46: "Una fortaleza de varios rivales que no figura en el inventario de FINDARO.",
    48: "Renombrado en 2 fases con Buscar/Reemplazar, Secuencia, Mayúsculas, Regex y ⌘Z.",
    51: "Renderizado nativo NSTableView para carpetas con decenas de miles de archivos.",
    52: "Limpieza en 1 clic de basura .DS_Store y archivos fantasma ._* en USB y NAS.",
  };

  if (isEn) {
    Object.assign(newNames, {"1": "Native macOS application (Swift)", "2": "Apple Silicon native (M1/M2/M3/M4)", "3": "Dual synchronized panes (source/destination)", "4": "Dedicated move/copy actions between panes", "5": "50/50 split panes with visible focus", "6": "Instant directory swap between panes", "7": "Drag & drop from Finder or between panes", "8": "True ⌘X cut & paste with clipboard tray", "9": "Visual clipboard tray before committing changes", "10": "Transfer queue with real-time speed & progress", "11": "SHA-256 cryptographic verification before & after copy/move", "12": "Automatic batch rollback on transfer failure", "13": "Smart Merge with visual diff of new, identical, & conflicting files", "14": "Post-merge verification and undo", "15": "User confirmation before destructive or write operations", "16": "Strict path policy boundary for agent operations", "17": "Optional private on-device chat with Ollama", "18": "Voice with Apple's speech recognition on your Mac (⌃Space and mic button)", "19": "Content search via local agent", "20": "AI actions: organize, create, copy, move and rename", "21": "Works without installing Ollama", "22": "Recursive search by name across subfolders", "23": "Filter by category and file type", "24": "Filter downloaded or added today", "25": "Largest files first", "26": "Dedicated search shortcuts by type and date", "27": "Instant filter in active folder", "28": "Persistent search history", "29": "Four views: list, icons, columns, and gallery", "30": "One-click Trash restore to original path", "31": "Native multi-selection (⌘, ⇧, marquee) and direct drag & drop", "32": "Command Path Bar (⌘L + Tab autocomplete) & breadcrumbs", "33": "Customizable keyboard shortcuts", "34": "Windows Explorer keyboard profile", "35": "Global hotkey to toggle FINDARO", "36": "Persistent favorites with fixed sidebar", "37": "FSEvents: live updates when files change", "38": "Quick Look and instant preview", "39": "ZIP: compress and extract", "40": "TAR extraction", "41": "Create file/folder, rename, duplicate", "42": "Undo move, copy, and Smart Merge via ⌘Z", "43": "Send selection to Dropover", "44": "Toggle hidden files visibility", "45": "App with native auto-update channel", "46": "Built-in FTP/SFTP/WebDAV/S3 remote connections", "47": "Two-way bidirectional folder sync", "48": "Batch Rename Pro (2-phase transactional, Regex & ⌘Z)", "49": "Browse archive files as virtual folders", "50": "Embedded terminal and remote operations", "51": "Ultra-Fast AppKit List Engine (120 fps)", "52": "External & SMB Drive Hygiene (.DS_Store & ._* 1-click purge)"}, {"3":"Source / Destination dual panes","8":"Cut ⌘X and paste ⌘V","11":"SHA-256 transfer integrity","12":"Batch recovery after transfer failure","13":"Smart Merge with conflict preview","15":"Approval before AI changes files","17":"Optional local AI with Ollama","18":"Local push-to-talk voice","22":"Search inside subfolders","32":"Command Path Bar (⌘L + Tab)","34":"Windows-style keyboard shortcuts","46":"FTP / SFTP / remote connections","48":"Batch Rename Pro (⌘Z Transactional)","51":"Ultra-Fast AppKit List Engine (120 fps)","52":"External & SMB Drive Hygiene"});
    Object.assign(descriptions, {"3":"Keep source and destination folders visible together.","8":"A visible tray for familiar Windows-style file cutting.","11":"Checks that transferred files retain their contents.","12":"Attempts to roll back the transfer batch after an error.","13":"Previews new, identical and conflicting items before merging.","15":"The assistant requests approval before writing changes.","17":"Optional local AI. All file management works without it.","18":"Dictation and commands without a remote voice server.","22":"Recursive filename search across nested folders.","32":"Jump anywhere via keyboard with instant Tab directory autocomplete.","34":"Helpful controls for people coming from Windows.","46":"An advantage of several alternatives not offered by FINDARO.","48":"2-phase batch renaming with Find/Replace, Sequence, Case, Regex & ⌘Z undo.","51":"Native NSTableView rendering handles tens of thousands of files smoothly.","52":"1-click purge of .DS_Store and ._* phantom files on USB and SMB/NAS drives."});
  }

  const rival = root.querySelector("#rival");
  const rivalLabel = root.querySelector("#rival-label");
  const rows = root.querySelector("#comparison-rows");
  const count = root.querySelector("#row-count");
  const fullButton = root.querySelector("#full-toggle");
  let features = [];
  let category = "esencial";
  let expanded = false;

  function el(name, css, text) {
    const n = document.createElement(name);
    if (css) n.className = css;
    if (text !== undefined) n.textContent = text;
    return n;
  }

  function status(raw, primary, undocumented) {
    const key = raw === "Sí" || raw === "Yes" ? "yes" : raw === "Similar" ? "similar" : "nd";
    const label = key === "yes"
      ? (isEn ? "Included" : "Incluido")
      : key === "similar"
        ? "Similar"
        : primary && undocumented
          ? (isEn ? "Not documented" : "No documentado")
          : (isEn ? "Not included" : "No incluye");
    return el("span", "status " + key + (primary && key === "yes" ? " findaro" : ""), label);
  }

  function render() {
    if (!features.length) return;
    const key = rival.value;
    rivalLabel.textContent = names[key];
    const subset = expanded
      ? features
      : selections[category]
          .map((id) => features.find((f) => f.id === id))
          .filter(Boolean);
    rows.replaceChildren();
    for (const f of subset) {
      const item = el(
        "div",
        "feature-row" + ((f.grupo === "Competencia fuerte" || f.grupo === "Where rivals excel") ? " caution" : ""),
      );
      const block = el("div");
      block.appendChild(el("div", "feature-name", newNames[f.id] || f.funcion));
      if (!expanded && descriptions[f.id]) {
        block.appendChild(el("div", "feature-note", descriptions[f.id]));
      }
      item.append(
        block,
        status(f.findaro, true, (f.grupo === "Competencia fuerte" || f.grupo === "Where rivals excel")),
        status(f[key], false),
      );
      rows.appendChild(item);
    }
    count.textContent =
      subset.length + (isEn ? " of " + features.length + " documented features" : " de " + features.length + " características de la matriz documental");
    fullButton.textContent = expanded
      ? (isEn ? "Back to summary" : "Volver a la comparación resumida")
      : (isEn ? "View all " + features.length + " features" : "Ver las " + features.length + " características");
    fullButton.setAttribute("aria-pressed", String(expanded));
    fullButton.setAttribute("aria-expanded", String(expanded));
    root.querySelectorAll("[data-cat]").forEach((btn) => {
      btn.setAttribute(
        "aria-pressed",
        String(!expanded && btn.dataset.cat === category),
      );
      btn.disabled = false;
      btn.style.opacity = "";
    });
  }

  rival.addEventListener("change", render);
  fullButton.addEventListener("click", () => {
    expanded = !expanded;
    render();
  });
  root.querySelectorAll("[data-cat]").forEach((btn) =>
    btn.addEventListener("click", () => {
      category = btn.dataset.cat;
      expanded = false;
      render();
    }),
  );

  const embedded = document.getElementById("findaro-feature-data");
  const boot = (data) => {
    features = Array.isArray(data) ? data : data.features || [];
    render();
  };

  if (embedded && embedded.textContent.trim()) {
    try {
      boot(JSON.parse(embedded.textContent));
      return;
    } catch (_) {
      /* fall through to fetch */
    }
  }

  fetch("/findaro-comparador/matriz-publicable.json")
    .then((r) => r.json())
    .then(boot)
    .catch(() => {
      rows.textContent =
        isEn ? "The comparison could not be loaded. Reload the page." : "No se pudo cargar la matriz de comparación. Recarga la página.";
    });
})();
