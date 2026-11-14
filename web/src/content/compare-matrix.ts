// Generado desde public/findaro-comparador/matriz-publicable.json (valores) y la matriz EN publicada.
// y = incluido · s = similar / parcial · n = no documentado
export type MatrixValue = "y" | "s" | "n";
export type MatrixApp = "findaro" | "finder" | "forklift" | "bloom" | "qspace" | "pathfinder";
export type MatrixRow = {
  id: number;
  groupEs: string;
  groupEn: string;
  es: string;
  en: string;
  v: Record<MatrixApp, MatrixValue>;
};

export const MATRIX_APPS: { key: MatrixApp; label: string }[] = [
  { key: "findaro", label: "Findaro" },
  { key: "finder", label: "Finder" },
  { key: "forklift", label: "ForkLift 4" },
  { key: "bloom", label: "Bloom" },
  { key: "qspace", label: "QSpace Pro" },
  { key: "pathfinder", label: "Path Finder" },
];

export const MATRIX: MatrixRow[] = [
  {
    "id": 1,
    "groupEs": "Producto",
    "groupEn": "Product",
    "es": "Aplicación nativa para macOS",
    "en": "Native macOS application (Swift)",
    "v": {
      "findaro": "y",
      "finder": "y",
      "forklift": "y",
      "bloom": "y",
      "qspace": "y",
      "pathfinder": "y"
    }
  },
  {
    "id": 2,
    "groupEs": "Producto",
    "groupEn": "Product",
    "es": "Compatibilidad Apple Silicon",
    "en": "Apple Silicon native (M1/M2/M3/M4)",
    "v": {
      "findaro": "y",
      "finder": "y",
      "forklift": "y",
      "bloom": "y",
      "qspace": "y",
      "pathfinder": "y"
    }
  },
  {
    "id": 3,
    "groupEs": "Transferencias",
    "groupEn": "Transfers",
    "es": "Doble panel origen/destino",
    "en": "Dual synchronized panes (source/destination)",
    "v": {
      "findaro": "y",
      "finder": "n",
      "forklift": "y",
      "bloom": "y",
      "qspace": "y",
      "pathfinder": "y"
    }
  },
  {
    "id": 4,
    "groupEs": "Transferencias",
    "groupEn": "Transfers",
    "es": "Acciones mover/copiar en ambos sentidos desde el panel",
    "en": "Dedicated move/copy actions between panes",
    "v": {
      "findaro": "y",
      "finder": "n",
      "forklift": "y",
      "bloom": "s",
      "qspace": "s",
      "pathfinder": "y"
    }
  },
  {
    "id": 5,
    "groupEs": "Transferencias",
    "groupEn": "Transfers",
    "es": "Paneles 50/50 con foco visible",
    "en": "50/50 split panes with visible focus",
    "v": {
      "findaro": "y",
      "finder": "n",
      "forklift": "s",
      "bloom": "s",
      "qspace": "s",
      "pathfinder": "s"
    }
  },
  {
    "id": 6,
    "groupEs": "Transferencias",
    "groupEn": "Transfers",
    "es": "Intercambiar rutas entre paneles (swap)",
    "en": "Instant directory swap between panes",
    "v": {
      "findaro": "y",
      "finder": "n",
      "forklift": "n",
      "bloom": "n",
      "qspace": "n",
      "pathfinder": "n"
    }
  },
  {
    "id": 7,
    "groupEs": "Transferencias",
    "groupEn": "Transfers",
    "es": "Drop desde Finder o entre paneles",
    "en": "Drag & drop from Finder or between panes",
    "v": {
      "findaro": "y",
      "finder": "s",
      "forklift": "y",
      "bloom": "y",
      "qspace": "y",
      "pathfinder": "y"
    }
  },
  {
    "id": 8,
    "groupEs": "Transferencias",
    "groupEn": "Transfers",
    "es": "Cortar ⌘X y pegar ⌘V con bandeja entre pestañas y paneles",
    "en": "True ⌘X cut & paste with clipboard tray",
    "v": {
      "findaro": "y",
      "finder": "n",
      "forklift": "n",
      "bloom": "s",
      "qspace": "s",
      "pathfinder": "n"
    }
  },
  {
    "id": 9,
    "groupEs": "Transferencias",
    "groupEn": "Transfers",
    "es": "Bandeja temporal de archivos",
    "en": "Visual clipboard tray before committing changes",
    "v": {
      "findaro": "y",
      "finder": "n",
      "forklift": "n",
      "bloom": "y",
      "qspace": "y",
      "pathfinder": "y"
    }
  },
  {
    "id": 10,
    "groupEs": "Transferencias",
    "groupEn": "Transfers",
    "es": "Cola y progreso de transferencias",
    "en": "Transfer queue with real-time speed & progress",
    "v": {
      "findaro": "y",
      "finder": "s",
      "forklift": "y",
      "bloom": "y",
      "qspace": "n",
      "pathfinder": "y"
    }
  },
  {
    "id": 11,
    "groupEs": "Seguridad",
    "groupEn": "Security",
    "es": "SHA-256 antes y después de copiar o mover",
    "en": "SHA-256 cryptographic verification before & after copy/move",
    "v": {
      "findaro": "y",
      "finder": "n",
      "forklift": "n",
      "bloom": "n",
      "qspace": "s",
      "pathfinder": "n"
    }
  },
  {
    "id": 12,
    "groupEs": "Seguridad",
    "groupEn": "Security",
    "es": "Rollback de lote al fallar operación",
    "en": "Automatic batch rollback on transfer failure",
    "v": {
      "findaro": "y",
      "finder": "n",
      "forklift": "n",
      "bloom": "s",
      "qspace": "n",
      "pathfinder": "n"
    }
  },
  {
    "id": 13,
    "groupEs": "Seguridad",
    "groupEn": "Security",
    "es": "Smart Merge con vista previa de nuevo, igual y conflicto",
    "en": "Smart Merge with visual diff of new, identical, & conflicting files",
    "v": {
      "findaro": "y",
      "finder": "s",
      "forklift": "s",
      "bloom": "s",
      "qspace": "n",
      "pathfinder": "y"
    }
  },
  {
    "id": 14,
    "groupEs": "Seguridad",
    "groupEn": "Security",
    "es": "Verificación postfusión y deshacer merge",
    "en": "Post-merge verification and undo",
    "v": {
      "findaro": "y",
      "finder": "n",
      "forklift": "n",
      "bloom": "s",
      "qspace": "n",
      "pathfinder": "n"
    }
  },
  {
    "id": 15,
    "groupEs": "Seguridad",
    "groupEn": "Security",
    "es": "Aprobación del usuario antes de acciones de IA que escriben",
    "en": "User confirmation before destructive or write operations",
    "v": {
      "findaro": "y",
      "finder": "n",
      "forklift": "n",
      "bloom": "n",
      "qspace": "n",
      "pathfinder": "n"
    }
  },
  {
    "id": 16,
    "groupEs": "Seguridad",
    "groupEn": "Security",
    "es": "Política de rutas permitidas para el agente",
    "en": "Strict path policy boundary for agent operations",
    "v": {
      "findaro": "y",
      "finder": "n",
      "forklift": "n",
      "bloom": "n",
      "qspace": "n",
      "pathfinder": "n"
    }
  },
  {
    "id": 17,
    "groupEs": "IA local",
    "groupEn": "Local AI",
    "es": "Chat local opcional con Ollama",
    "en": "Optional private on-device chat with Ollama",
    "v": {
      "findaro": "y",
      "finder": "n",
      "forklift": "n",
      "bloom": "n",
      "qspace": "n",
      "pathfinder": "n"
    }
  },
  {
    "id": 18,
    "groupEs": "IA local",
    "groupEn": "Local AI",
    "es": "Voz con el reconocimiento de Apple, en tu Mac (⌃Espacio y botón de micrófono)",
    "en": "Voice with Apple's speech recognition on your Mac (⌃Space and mic button)",
    "v": {
      "findaro": "y",
      "finder": "n",
      "forklift": "n",
      "bloom": "n",
      "qspace": "n",
      "pathfinder": "n"
    }
  },
  {
    "id": 19,
    "groupEs": "IA local",
    "groupEn": "Local AI",
    "es": "Búsqueda por contenido mediante agente local",
    "en": "Content search via local agent",
    "v": {
      "findaro": "y",
      "finder": "s",
      "forklift": "s",
      "bloom": "s",
      "qspace": "s",
      "pathfinder": "s"
    }
  },
  {
    "id": 20,
    "groupEs": "IA local",
    "groupEn": "Local AI",
    "es": "Acciones IA: organizar, crear, copiar, mover y renombrar",
    "en": "AI actions: organize, create, copy, move and rename",
    "v": {
      "findaro": "y",
      "finder": "n",
      "forklift": "n",
      "bloom": "n",
      "qspace": "n",
      "pathfinder": "n"
    }
  },
  {
    "id": 21,
    "groupEs": "IA local",
    "groupEn": "Local AI",
    "es": "Funciona sin instalar Ollama",
    "en": "Works without installing Ollama",
    "v": {
      "findaro": "y",
      "finder": "y",
      "forklift": "y",
      "bloom": "y",
      "qspace": "y",
      "pathfinder": "y"
    }
  },
  {
    "id": 22,
    "groupEs": "Búsqueda",
    "groupEn": "Search",
    "es": "Búsqueda recursiva por nombre en subcarpetas",
    "en": "Recursive search by name across subfolders",
    "v": {
      "findaro": "y",
      "finder": "y",
      "forklift": "y",
      "bloom": "y",
      "qspace": "y",
      "pathfinder": "y"
    }
  },
  {
    "id": 23,
    "groupEs": "Búsqueda",
    "groupEn": "Search",
    "es": "Filtro por categoría/tipo",
    "en": "Filter by category and file type",
    "v": {
      "findaro": "y",
      "finder": "y",
      "forklift": "y",
      "bloom": "y",
      "qspace": "y",
      "pathfinder": "y"
    }
  },
  {
    "id": 24,
    "groupEs": "Búsqueda",
    "groupEn": "Search",
    "es": "Filtro de descargados/agregados hoy",
    "en": "Filter downloaded or added today",
    "v": {
      "findaro": "y",
      "finder": "s",
      "forklift": "n",
      "bloom": "s",
      "qspace": "n",
      "pathfinder": "n"
    }
  },
  {
    "id": 25,
    "groupEs": "Búsqueda",
    "groupEn": "Search",
    "es": "Más pesados primero",
    "en": "Largest files first",
    "v": {
      "findaro": "y",
      "finder": "s",
      "forklift": "y",
      "bloom": "y",
      "qspace": "s",
      "pathfinder": "y"
    }
  },
  {
    "id": 26,
    "groupEs": "Búsqueda",
    "groupEn": "Search",
    "es": "Atajos propios de búsqueda por tipo y fecha",
    "en": "Dedicated search shortcuts by type and date",
    "v": {
      "findaro": "y",
      "finder": "s",
      "forklift": "n",
      "bloom": "n",
      "qspace": "n",
      "pathfinder": "n"
    }
  },
  {
    "id": 27,
    "groupEs": "Orden",
    "groupEn": "Sorting",
    "es": "Orden y preferencias por carpeta",
    "en": "Per-folder sort and preferences",
    "v": {
      "findaro": "y",
      "finder": "y",
      "forklift": "y",
      "bloom": "y",
      "qspace": "s",
      "pathfinder": "y"
    }
  },
  {
    "id": 28,
    "groupEs": "Orden",
    "groupEn": "Sorting",
    "es": "Plantillas de vista: orden + vista + filtro",
    "en": "View templates: sort + view + filter",
    "v": {
      "findaro": "y",
      "finder": "s",
      "forklift": "y",
      "bloom": "y",
      "qspace": "y",
      "pathfinder": "y"
    }
  },
  {
    "id": 29,
    "groupEs": "Visualización",
    "groupEn": "Display",
    "es": "Cuatro vistas lista/iconos/columnas/galería",
    "en": "Four views: list, icons, columns, and gallery",
    "v": {
      "findaro": "y",
      "finder": "y",
      "forklift": "s",
      "bloom": "s",
      "qspace": "s",
      "pathfinder": "s"
    }
  },
  {
    "id": 30,
    "groupEs": "Archivos",
    "groupEn": "Files",
    "es": "Restaurar archivos desde Papelera a su ruta original con 1 clic",
    "en": "One-click Trash restore to original path",
    "v": {
      "findaro": "y",
      "finder": "y",
      "forklift": "y",
      "bloom": "y",
      "qspace": "y",
      "pathfinder": "y"
    }
  },
  {
    "id": 31,
    "groupEs": "Visualización",
    "groupEn": "Display",
    "es": "Selección múltiple nativa (⌘, ⇧, marquesina) y arrastre directo",
    "en": "Native multi-selection (⌘, ⇧, marquee) and direct drag & drop",
    "v": {
      "findaro": "y",
      "finder": "n",
      "forklift": "n",
      "bloom": "n",
      "qspace": "n",
      "pathfinder": "n"
    }
  },
  {
    "id": 32,
    "groupEs": "Navegación",
    "groupEn": "Navigation",
    "es": "Barra de ruta editable (⌘L + Tab autocompletado) y breadcrumbs",
    "en": "Command Path Bar (⌘L + Tab autocomplete) & breadcrumbs",
    "v": {
      "findaro": "y",
      "finder": "s",
      "forklift": "y",
      "bloom": "y",
      "qspace": "y",
      "pathfinder": "y"
    }
  },
  {
    "id": 33,
    "groupEs": "Navegación",
    "groupEn": "Navigation",
    "es": "Atajos de teclado editables",
    "en": "Customizable keyboard shortcuts",
    "v": {
      "findaro": "y",
      "finder": "s",
      "forklift": "y",
      "bloom": "y",
      "qspace": "y",
      "pathfinder": "y"
    }
  },
  {
    "id": 34,
    "groupEs": "Navegación",
    "groupEn": "Navigation",
    "es": "Perfil teclado tipo Windows Explorer",
    "en": "Windows Explorer keyboard profile",
    "v": {
      "findaro": "y",
      "finder": "n",
      "forklift": "n",
      "bloom": "n",
      "qspace": "y",
      "pathfinder": "n"
    }
  },
  {
    "id": 35,
    "groupEs": "Navegación",
    "groupEn": "Navigation",
    "es": "Atajo global para abrir FINDARO",
    "en": "Global hotkey to toggle FINDARO",
    "v": {
      "findaro": "y",
      "finder": "n",
      "forklift": "n",
      "bloom": "n",
      "qspace": "n",
      "pathfinder": "n"
    }
  },
  {
    "id": 36,
    "groupEs": "Navegación",
    "groupEn": "Navigation",
    "es": "Favoritos persistentes con sidebar fijo",
    "en": "Persistent favorites with fixed sidebar",
    "v": {
      "findaro": "y",
      "finder": "y",
      "forklift": "y",
      "bloom": "y",
      "qspace": "y",
      "pathfinder": "y"
    }
  },
  {
    "id": 37,
    "groupEs": "Navegación",
    "groupEn": "Navigation",
    "es": "FSEvents: actualización al cambiar archivos",
    "en": "FSEvents: live updates when files change",
    "v": {
      "findaro": "y",
      "finder": "y",
      "forklift": "n",
      "bloom": "n",
      "qspace": "n",
      "pathfinder": "n"
    }
  },
  {
    "id": 38,
    "groupEs": "Archivos",
    "groupEn": "Files",
    "es": "Quick Look y previsualización",
    "en": "Quick Look and instant preview",
    "v": {
      "findaro": "y",
      "finder": "y",
      "forklift": "y",
      "bloom": "y",
      "qspace": "y",
      "pathfinder": "y"
    }
  },
  {
    "id": 39,
    "groupEs": "Archivos",
    "groupEn": "Files",
    "es": "ZIP: comprimir y extraer",
    "en": "ZIP: compress and extract",
    "v": {
      "findaro": "y",
      "finder": "y",
      "forklift": "y",
      "bloom": "y",
      "qspace": "y",
      "pathfinder": "y"
    }
  },
  {
    "id": 40,
    "groupEs": "Archivos",
    "groupEn": "Files",
    "es": "Descomprimir TAR",
    "en": "TAR extraction",
    "v": {
      "findaro": "y",
      "finder": "s",
      "forklift": "y",
      "bloom": "y",
      "qspace": "y",
      "pathfinder": "y"
    }
  },
  {
    "id": 41,
    "groupEs": "Archivos",
    "groupEn": "Files",
    "es": "Crear archivo/carpeta, renombrar, duplicar",
    "en": "Create file/folder, rename, duplicate",
    "v": {
      "findaro": "y",
      "finder": "s",
      "forklift": "y",
      "bloom": "y",
      "qspace": "y",
      "pathfinder": "y"
    }
  },
  {
    "id": 42,
    "groupEs": "Archivos",
    "groupEn": "Files",
    "es": "Deshacer movimiento, copia y Smart Merge",
    "en": "Undo move, copy, and Smart Merge via ⌘Z",
    "v": {
      "findaro": "y",
      "finder": "s",
      "forklift": "s",
      "bloom": "y",
      "qspace": "n",
      "pathfinder": "n"
    }
  },
  {
    "id": 43,
    "groupEs": "Archivos",
    "groupEn": "Files",
    "es": "Enviar selección a Dropover",
    "en": "Send selection to Dropover",
    "v": {
      "findaro": "y",
      "finder": "n",
      "forklift": "n",
      "bloom": "n",
      "qspace": "n",
      "pathfinder": "n"
    }
  },
  {
    "id": 44,
    "groupEs": "Archivos",
    "groupEn": "Files",
    "es": "Ver archivos ocultos",
    "en": "Toggle hidden files visibility",
    "v": {
      "findaro": "y",
      "finder": "y",
      "forklift": "y",
      "bloom": "y",
      "qspace": "y",
      "pathfinder": "y"
    }
  },
  {
    "id": 45,
    "groupEs": "Distribución",
    "groupEn": "Distribution",
    "es": "App con canal propio de actualizaciones",
    "en": "App with native auto-update channel",
    "v": {
      "findaro": "y",
      "finder": "y",
      "forklift": "y",
      "bloom": "y",
      "qspace": "y",
      "pathfinder": "y"
    }
  },
  {
    "id": 46,
    "groupEs": "Competencia fuerte",
    "groupEn": "Where rivals excel",
    "es": "Conexión FTP/SFTP/WebDAV/S3 integrada",
    "en": "Built-in FTP/SFTP/WebDAV/S3 remote connections",
    "v": {
      "findaro": "n",
      "finder": "n",
      "forklift": "y",
      "bloom": "n",
      "qspace": "y",
      "pathfinder": "y"
    }
  },
  {
    "id": 47,
    "groupEs": "Competencia fuerte",
    "groupEn": "Where rivals excel",
    "es": "Sincronización de carpetas bidireccional",
    "en": "Two-way bidirectional folder sync",
    "v": {
      "findaro": "n",
      "finder": "n",
      "forklift": "y",
      "bloom": "s",
      "qspace": "y",
      "pathfinder": "y"
    }
  },
  {
    "id": 48,
    "groupEs": "Archivos",
    "groupEn": "Files",
    "es": "Renombrado masivo Pro (transaccional en 2 fases, Regex y ⌘Z)",
    "en": "Batch Rename Pro (2-phase transactional, Regex & ⌘Z)",
    "v": {
      "findaro": "y",
      "finder": "n",
      "forklift": "y",
      "bloom": "y",
      "qspace": "y",
      "pathfinder": "y"
    }
  },
  {
    "id": 49,
    "groupEs": "Competencia fuerte",
    "groupEn": "Where rivals excel",
    "es": "Navegar archivos comprimidos como carpetas",
    "en": "Browse archive files as virtual folders",
    "v": {
      "findaro": "n",
      "finder": "n",
      "forklift": "y",
      "bloom": "y",
      "qspace": "y",
      "pathfinder": "s"
    }
  },
  {
    "id": 50,
    "groupEs": "Competencia fuerte",
    "groupEn": "Where rivals excel",
    "es": "Terminal integrado y operaciones remotas",
    "en": "Embedded terminal and remote operations",
    "v": {
      "findaro": "n",
      "finder": "n",
      "forklift": "y",
      "bloom": "y",
      "qspace": "y",
      "pathfinder": "y"
    }
  },
  {
    "id": 51,
    "groupEs": "Visualización",
    "groupEn": "Display",
    "es": "Motor de lista AppKit ultrarrápido (120 fps)",
    "en": "Ultra-Fast AppKit List Engine (120 fps)",
    "v": {
      "findaro": "y",
      "finder": "y",
      "forklift": "y",
      "bloom": "y",
      "qspace": "y",
      "pathfinder": "s"
    }
  },
  {
    "id": 52,
    "groupEs": "Archivos",
    "groupEn": "Files",
    "es": "Higiene en unidades externas y SMB/NAS (limpieza 1 clic de .DS_Store y ._*)",
    "en": "External & SMB Drive Hygiene (.DS_Store & ._* 1-click purge)",
    "v": {
      "findaro": "y",
      "finder": "n",
      "forklift": "n",
      "bloom": "n",
      "qspace": "n",
      "pathfinder": "n"
    }
  }
];
