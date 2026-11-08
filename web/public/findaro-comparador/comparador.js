(() => {
  "use strict";

  const root =
    document.getElementById("comparar") ||
    document.querySelector(".findaro-compare-embed");
  if (!root) return;

  const names = {
    forklift: "ForkLift 4",
    bloom: "Bloom",
    qspace: "QSpace Pro",
    pathfinder: "Path Finder",
    commander: "Commander One",
    finder: "Finder",
  };
  const selections = {
    esencial: [13, 11, 12, 15, 17, 18, 8, 3, 22, 34],
    seguridad: [11, 12, 13, 14, 15, 16, 42],
    ia: [15, 16, 17, 18, 19, 20, 21],
    transferencias: [3, 4, 5, 6, 7, 8, 9, 10, 13],
    productividad: [
      22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40,
      41, 42, 43, 44, 45,
    ],
    rival: [46, 47, 48, 49, 50],
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
    34: "Perfil de teclado tipo Windows",
    46: "Conexiones FTP / SFTP / servicios remotos",
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
    34: "Adaptación para quien viene de Windows.",
    46: "Una fortaleza de varios rivales que no figura en el inventario de FINDARO.",
  };

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
    const key = raw === "Sí" ? "yes" : raw === "Similar" ? "similar" : "nd";
    const lbl =
      raw === "Sí"
        ? "Incluido"
        : raw === "Similar"
          ? "Similar"
          : primary && undocumented
            ? "No documentado"
            : "Sin confirmar";
    return el(
      "span",
      "status " + key + (primary && key === "yes" ? " findaro" : ""),
      lbl,
    );
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
        "feature-row" + (f.grupo === "Competencia fuerte" ? " caution" : ""),
      );
      const block = el("div");
      block.appendChild(el("div", "feature-name", newNames[f.id] || f.funcion));
      if (!expanded && descriptions[f.id]) {
        block.appendChild(el("div", "feature-note", descriptions[f.id]));
      }
      item.append(
        block,
        status(f.findaro, true, f.grupo === "Competencia fuerte"),
        status(f[key], false),
      );
      rows.appendChild(item);
    }
    count.textContent =
      subset.length + " de 50 características de la matriz documental";
    fullButton.textContent = expanded
      ? "Volver a la comparación resumida"
      : "Ver las 50 características";
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
        "No se pudo cargar la matriz de comparación. Recarga la página.";
    });
})();
