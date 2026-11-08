import Foundation

/// Lógica pura para selección por rango, aditiva (toggle) y navegación por teclado.
public enum SelectionRangeLogic {
    /// Rango continuo desde anchor hasta target dentro de una lista ordenada de IDs.
    public static func computeRange(ids: [String], anchor: String?, target: String) -> (rangeIDs: Set<String>, resolvedAnchor: String) {
        guard !ids.isEmpty else { return ([], target) }
        let effectiveAnchor = anchor ?? target
        guard let a = ids.firstIndex(of: effectiveAnchor),
              let b = ids.firstIndex(of: target) else {
            return ([target], target)
        }
        let indices = a <= b ? a...b : b...a
        return (Set(ids[indices]), effectiveAnchor)
    }

    /// Alterna un elemento individual (estilo ⌘+clic nativo de macOS).
    public static func toggle(selectedIDs: Set<String>, id: String) -> Set<String> {
        var updated = selectedIDs
        if updated.contains(id) {
            updated.remove(id)
        } else {
            updated.insert(id)
        }
        return updated
    }

    /// Movimiento por teclado (flechas ↑↓). Con `extending: true` extiende el rango desde el ancla.
    public static func nextKeyboardSelection(
        ids: [String],
        currentFocus: String?,
        currentAnchor: String?,
        selectedIDs: Set<String>,
        delta: Int,
        extending: Bool
    ) -> (newSelected: Set<String>, newAnchor: String, newFocus: String)? {
        guard !ids.isEmpty else { return nil }

        if selectedIDs.isEmpty && currentFocus == nil {
            let initialID = delta >= 0 ? ids[0] : ids[ids.count - 1]
            return ([initialID], initialID, initialID)
        }

        let cursor = currentFocus
            ?? currentAnchor
            ?? selectedIDs.first
            ?? ids[0]
        let idx = ids.firstIndex(of: cursor) ?? 0
        let nextIdx = min(max(0, idx + delta), ids.count - 1)
        let nextID = ids[nextIdx]

        if extending {
            let anchor = currentAnchor ?? cursor
            let (rangeSet, resolvedAnchor) = computeRange(ids: ids, anchor: anchor, target: nextID)
            return (rangeSet, resolvedAnchor, nextID)
        } else {
            return ([nextID], nextID, nextID)
        }
    }
}
