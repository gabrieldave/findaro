import { query } from "./db";

export interface FunnelEvent {
  name:
    | "visit_attributed"
    | "download_click"
    | "trial_started"
    | "first_value_completed"
    | "trial_expired"
    | "purchase_confirmed";
  subjectType?: string;
  subjectId?: string;
  dedupKey: string;
  props?: Record<string, unknown>;
}

export async function recordEvent(event: FunnelEvent): Promise<boolean> {
  try {
    const res = await query(
      `INSERT INTO events (name, subject_type, subject_id, dedup_key, props)
       VALUES ($1, $2, $3, $4, $5)
       ON CONFLICT (dedup_key) DO NOTHING
       RETURNING id`,
      [
        event.name,
        event.subjectType || null,
        event.subjectId || null,
        event.dedupKey,
        JSON.stringify(event.props || {}),
      ],
    );
    return res.rows.length > 0;
  } catch (err) {
    console.error("[events] Error registrando evento:", event.name, err);
    return false;
  }
}
