/* global window, document */
(function () {
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

  const state = {
    i18n: null,
    theme: "midnight",
    view: "list",
    activePane: "origin",
  };

  function $(id) {
    return document.getElementById(id);
  }

  function setTheme(name) {
    state.theme = name;
    document.body.classList.remove("theme-midnight", "theme-graphite", "theme-emerald", "theme-nordic");
    document.body.classList.add(`theme-${name}`);
  }

  function setView(view) {
    state.view = view;
    const main = $("mainPanes");
    main.classList.remove("view-icons", "view-gallery", "view-columns");
    if (view === "icons") main.classList.add("view-icons");
    if (view === "gallery") main.classList.add("view-gallery");
    if (view === "columns") main.classList.add("view-columns");
    document.querySelectorAll("#viewSeg button").forEach((b) => {
      b.classList.toggle("active", b.dataset.view === view);
    });
  }

  function setActivePane(which) {
    state.activePane = which;
    $("tabOrigin").classList.toggle("active", which === "origin");
    $("tabDest").classList.toggle("active", which === "dest");
  }

  function fileIcon(kind) {
    if (kind === "folder") return '<i class="icon folder">F</i>';
    if (kind === "pdf") return '<i class="icon pdf">P</i>';
    return '<i class="icon image">I</i>';
  }

  function renderFiles() {
    const i18n = state.i18n;
    const origin = $("originRows");
    const dest = $("destRows");
    origin.innerHTML = i18n.files
      .map(
        (f, idx) => `
      <div class="row" data-idx="${idx}" data-name="${f.name}">
        <div class="namecell">${fileIcon(f.kind)}<span>${f.name}</span></div>
        <div class="meta">${f.date}</div>
        <div class="meta">${f.size}</div>
      </div>`
      )
      .join("");
    dest.innerHTML = i18n.destFiles
      .map(
        (f) => `
      <div class="row">
        <div class="namecell">${fileIcon(f.kind)}<span>${f.name}</span></div>
        <div class="meta">${f.date}</div>
        <div class="meta">${f.size}</div>
      </div>`
      )
      .join("");
  }

  function renderMerge() {
    const i18n = state.i18n;
    $("mergeRows").innerHTML = i18n.mergeRows
      .map(
        (r) => `
      <div class="merge-row ${r.status}">
        <span>${r.name}</span>
        <span class="tag">${r.status === "new" ? i18n.badgeNew : r.status === "same" ? i18n.badgeSame : i18n.badgeConflict}</span>
      </div>`
      )
      .join("");
  }

  function renderSearch(query) {
    const i18n = state.i18n;
    $("searchInput").value = query || "";
    const hits = i18n.searchHits;
    $("searchHits").innerHTML = hits.map((h, i) => `<div class="${i === 0 ? "active" : ""}">${h}</div>`).join("");
  }

  function renderTrash() {
    const i18n = state.i18n;
    $("originRows").innerHTML = i18n.trashFiles
      .map(
        (f) => `
      <div class="row">
        <div class="namecell"><i class="icon pdf">T</i><span>${f.name}</span></div>
        <div class="meta">—</div>
        <div class="meta">${f.size}</div>
      </div>`
      )
      .join("");
  }

  function applyI18n(i18n) {
    state.i18n = i18n;
    document.documentElement.lang = i18n.lang;
    $("windowTitle").textContent = `Findaro — ${i18n.studio}`;
    $("btnList").textContent = i18n.viewList;
    $("btnIcons").textContent = i18n.viewIcons;
    $("btnColumns").textContent = i18n.viewColumns;
    $("btnGallery").textContent = i18n.viewGallery;
    $("crumbStudio").textContent = i18n.studio;
    $("tabOrigin").textContent = i18n.origin;
    $("tabDest").textContent = i18n.destination;
    $("btnNew").textContent = i18n.new;
    $("labFav").textContent = i18n.favorites;
    $("labSmart").textContent = i18n.smart;
    $("labLoc").textContent = i18n.locations;
    $("itmDownloads").textContent = i18n.downloads;
    $("itmDesktop").textContent = i18n.desktop;
    $("itmDocuments").textContent = i18n.documents;
    $("itmStudio").textContent = i18n.studio;
    $("itmIcloud").textContent = i18n.icloud;
    $("itmGdrive").textContent = i18n.googleDrive;
    $("itmHd").textContent = i18n.macintoshHD;
    $("itmTrash").textContent = i18n.trash;
    $("originLabel").textContent = i18n.origin;
    $("destLabel").textContent = i18n.destination;
    $("destBadge").textContent = i18n.activeBadge;
    $("colName").textContent = i18n.name;
    $("colName2").textContent = i18n.name;
    $("colMod").textContent = i18n.modified;
    $("colMod2").textContent = i18n.modified;
    $("colSize").textContent = i18n.size;
    $("colSize2").textContent = i18n.size;
    $("trayText").textContent = i18n.trayReady;
    $("aiTitle").textContent = i18n.aiTitle;
    $("aiPlan").textContent = i18n.aiPlanBody;
    $("aiApprove").textContent = i18n.approve;
    $("aiReject").textContent = i18n.reject;
    $("mergeTitle").textContent = i18n.smartMergeTitle;
    $("mergeSum").textContent = i18n.smartMergeSummary;
    $("pillNew").textContent = i18n.badgeNew;
    $("pillSame").textContent = i18n.badgeSame;
    $("pillConflict").textContent = i18n.badgeConflict;
    $("btnKeepBoth").textContent = i18n.keepBoth;
    $("btnReplace").textContent = i18n.replace;
    $("btnSkip").textContent = i18n.skip;
    $("shaLabel").textContent = i18n.shaBadge;
    $("btnRestore").textContent = i18n.restore;
    $("trashTitle").textContent = i18n.trash;
    $("trashHint").textContent = i18n.trashEmptyHint;
    $("searchInput").placeholder = i18n.searchPlaceholder;
    $("ogHeadline").textContent = i18n.ogHeadline;
    $("socialTitle").textContent = i18n.socialTitle;
    $("socialSub").textContent = i18n.socialSub;
    $("aiWave").innerHTML = Array.from({ length: 18 }, () => "<i></i>").join("");
    renderFiles();
    renderMerge();
    renderSearch("");
  }

  async function moveCursor(x, y, ms = 700) {
    const c = $("cursor");
    c.style.transitionDuration = `${ms}ms`;
    c.style.left = `${x}px`;
    c.style.top = `${y}px`;
    await sleep(ms);
  }

  async function clickAt(x, y) {
    await moveCursor(x, y, 550);
    const c = $("cursor");
    const r = $("ripple");
    r.style.left = `${x}px`;
    r.style.top = `${y}px`;
    r.classList.remove("go");
    void r.offsetWidth;
    r.classList.add("go");
    c.classList.add("clicking");
    await sleep(160);
    c.classList.remove("clicking");
  }

  function showHud(keys) {
    const hud = $("hud");
    hud.innerHTML = keys
      .split("+")
      .map((k) => k.trim())
      .map((k) => `<kbd>${k}</kbd>`)
      .join(" + ");
    hud.classList.add("show");
  }

  function hideHud() {
    $("hud").classList.remove("show");
  }

  function zoomTo(scale, xPct, yPct) {
    const z = $("stageZoom");
    z.style.setProperty("--stage-scale", String(scale));
    z.style.setProperty("--stage-x", xPct);
    z.style.setProperty("--stage-y", yPct);
  }

  function resetZoom() {
    zoomTo(1, "0%", "0%");
  }

  function selectRows(indices) {
    document.querySelectorAll("#originRows .row").forEach((row) => {
      const idx = Number(row.dataset.idx);
      row.classList.toggle("selected", indices.includes(idx));
    });
  }

  function dimSelected() {
    document.querySelectorAll("#originRows .row.selected").forEach((r) => r.classList.add("dimmed"));
  }

  function fillTray(names) {
    const tray = $("tray");
    tray.classList.add("has-items");
    $("trayText").textContent = state.i18n.trayItems;
    $("trayChips").innerHTML = names.map((n) => `<span class="chip">${n}</span>`).join("");
  }

  function clearTray() {
    $("tray").classList.remove("has-items");
    $("trayChips").innerHTML = "";
    $("trayText").textContent = state.i18n.trayReady;
    document.querySelectorAll("#originRows .row").forEach((r) => r.classList.remove("selected", "dimmed"));
  }

  function showMode(mode) {
    // dual | ai | merge | search | trash | og | themes
    $("aiPanel").classList.remove("show", "listening");
    $("mergeOverlay").classList.remove("show");
    $("searchBar").classList.remove("show");
    $("trashBanner").classList.remove("show");
    $("ogRoot").classList.remove("show");
    $("stage").classList.remove("hidden");
    $("socialCaption").classList.remove("show");
    document.querySelectorAll("#sidebar .side-item").forEach((el) => el.classList.remove("active"));
    document.querySelector('#sidebar .side-item[data-id="studio"]')?.classList.add("active");
    resetZoom();
    hideHud();
    setView("list");
    setActivePane("origin");
    renderFiles();

    if (mode === "og") {
      $("stage").classList.add("hidden");
      $("ogRoot").classList.add("show");
      // clone window look into og slot visually by keeping stage hidden
      return;
    }
    if (mode === "ai") {
      $("aiPanel").classList.add("show");
      $("aiDictation").textContent = "";
      $("aiPlan").classList.remove("show");
    }
    if (mode === "merge") {
      $("mergeOverlay").classList.add("show");
      renderMerge();
    }
    if (mode === "search") {
      $("searchBar").classList.add("show");
      renderSearch("");
    }
    if (mode === "trash") {
      document.querySelectorAll("#sidebar .side-item").forEach((el) => el.classList.remove("active"));
      document.querySelector('#sidebar .side-item[data-id="trash"]')?.classList.add("active");
      $("trashBanner").classList.add("show");
      $("paneDest").classList.add("hidden");
      $("mainPanes").classList.add("single");
      renderTrash();
    } else {
      $("paneDest").classList.remove("hidden");
      $("mainPanes").classList.remove("single");
    }
  }

  async function typeText(el, text, perChar = 45) {
    el.textContent = "";
    for (const ch of text) {
      el.textContent += ch;
      await sleep(perChar);
    }
  }

  // —— Scenes ——
  async function sceneHero() {
    showMode("dual");
    selectRows([0, 1]);
    const chips = state.i18n.files.slice(0, 2).map((f) => f.name.split(".")[0].slice(0, 12) + "…");
    fillTray(chips);
    setActivePane("dest");
    await sleep(200);
  }

  async function sceneAssistant() {
    showMode("ai");
    $("aiPanel").classList.add("listening");
    $("aiDictation").textContent = state.i18n.aiListening;
    await sleep(200);
  }

  async function sceneMerge() {
    showMode("merge");
    await sleep(200);
  }

  async function sceneTrash() {
    showMode("trash");
    await sleep(200);
  }

  async function sceneV1(durationMs) {
    showMode("ai");
    await moveCursor(980, 220, 600);
    zoomTo(1.28, "8%", "6%");
    await sleep(400);
    showHud(state.i18n.lang === "en" ? "⌃ + Space" : "⌃ + Espacio");
    $("aiPanel").classList.add("listening");
    $("aiDictation").textContent = state.i18n.aiListening;
    await sleep(900);
    hideHud();
    await typeText($("aiDictation"), state.i18n.aiDictation, 38);
    await sleep(400);
    $("aiPanel").classList.remove("listening");
    $("aiPlan").classList.add("show");
    await sleep(700);
    await clickAt(1040, 430);
    $("aiApprove").style.filter = "brightness(1.25)";
    await sleep(600);
    resetZoom();
    await sleep(Math.max(200, durationMs - 7500));
  }

  async function sceneV2(durationMs) {
    showMode("dual");
    clearTray();
    await moveCursor(420, 260, 500);
    const m = $("marquee");
    m.classList.add("show");
    m.style.left = "250px";
    m.style.top = "210px";
    m.style.width = "10px";
    m.style.height = "10px";
    await sleep(200);
    m.style.transition = "all .55s cubic-bezier(0.22,1,0.36,1)";
    m.style.width = "340px";
    m.style.height = "150px";
    await sleep(600);
    selectRows([0, 1, 2]);
    m.classList.remove("show");
    zoomTo(1.28, "6%", "4%");
    showHud("⌘ + X");
    await sleep(700);
    dimSelected();
    fillTray(state.i18n.files.slice(0, 3).map((f) => f.name.split(".")[0]));
    hideHud();
    await sleep(500);
    showHud("Tab");
    setActivePane("dest");
    await sleep(700);
    hideHud();
    showHud("⌘ + V");
    zoomTo(1.22, "-8%", "4%");
    await sleep(600);
    clearTray();
    $("tray").classList.add("has-items");
    $("trayOk").style.display = "inline";
    $("trayText").textContent = "✓ SHA-256";
    hideHud();
    await sleep(700);
    resetZoom();
    await sleep(Math.max(200, durationMs - 8200));
  }

  async function sceneV3(durationMs) {
    showMode("dual");
    await moveCursor(200, 180, 500);
    // drag Documents into dest
    await moveCursor(820, 300, 900);
    zoomTo(1.28, "0%", "2%");
    $("mergeOverlay").classList.add("show");
    renderMerge();
    await sleep(1200);
    await clickAt(860, 520);
    $("btnKeepBoth").style.filter = "brightness(1.25)";
    await sleep(900);
    resetZoom();
    await sleep(Math.max(200, durationMs - 7500));
  }

  async function sceneV4(durationMs) {
    // Dual pane con archivos visibles → HUD ⌘4 → buscar → 8 resultados → abrir
    showMode("dual");
    renderFiles();
    $("searchBar").classList.remove("show");
    await sleep(500);
    showHud("⌘ + 4");
    await moveCursor(640, 120, 450);
    await sleep(650);
    hideHud();
    $("searchBar").classList.add("show");
    renderSearch("");
    zoomTo(1.3, "0%", "8%");
    await sleep(350);
    await typeText($("searchInput"), state.i18n.searchQuery, 85);
    renderSearch(state.i18n.searchQuery);
    await sleep(900);
    await clickAt(640, 250);
    document.querySelectorAll("#searchHits div").forEach((el, i) => {
      el.classList.toggle("active", i === 0);
    });
    await sleep(1100);
    resetZoom();
    await sleep(Math.max(300, durationMs - 7500));
  }

  async function sceneV5(durationMs) {
    showMode("dual");
    const views = ["list", "icons", "columns", "gallery"];
    for (const v of views) {
      setView(v);
      await clickAt(180 + views.indexOf(v) * 55, 70);
      await sleep(700);
    }
    showMode("trash");
    zoomTo(1.22, "4%", "8%");
    await clickAt(920, 170);
    $("btnRestore").style.filter = "brightness(1.2)";
    await sleep(900);
    resetZoom();
    await sleep(Math.max(200, durationMs - 7000));
  }

  async function sceneV6(durationMs) {
    showMode("dual");
    const themes = [
      ["midnight", state.i18n.themeMidnight],
      ["graphite", state.i18n.themeGraphite],
      ["emerald", state.i18n.themeEmerald],
      ["nordic", state.i18n.themeNordic],
      ["midnight", state.i18n.themeMidnight],
    ];
    for (const [t, label] of themes) {
      setTheme(t);
      showHud(label);
      await sleep(1100);
      hideHud();
      await sleep(200);
    }
    await sleep(Math.max(100, durationMs - 7000));
  }

  window.FindaroStudio = {
    applyI18n,
    setTheme,
    setView,
    showMode,
    showHud,
    hideHud,
    zoomTo,
    resetZoom,
    moveCursor,
    clickAt,
    selectRows,
    scenes: {
      hero: sceneHero,
      assistant: sceneAssistant,
      merge: sceneMerge,
      trash: sceneTrash,
      v1: sceneV1,
      v2: sceneV2,
      v3: sceneV3,
      v4: sceneV4,
      v5: sceneV5,
      v6: sceneV6,
    },
    ready: true,
  };
})();
