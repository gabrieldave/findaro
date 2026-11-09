import { query } from "./db";

export type FunnelEventName =
  | "visit"
  | "download_requested"
  | "trial_started"
  | "first_value_completed"
  | "trial_expired"
  | "purchase_confirmed";

export interface FunnelEvent {
  name: FunnelEventName;
  subjectType: string;
  subjectId: string;
  occurrenceKey?: string;
  props?: Record<string, unknown>;
}

export async function recordEvent(event: FunnelEvent): Promise<boolean> {
  try {
    const occurrenceKey = event.occurrenceKey || "once";
    const res = await query(
      `INSERT INTO events (name, subject_type, subject_id, occurrence_key, props)
       VALUES ($1, $2, $3, $4, $5)
       ON CONFLICT (name, subject_type, subject_id, occurrence_key) DO NOTHING
       RETURNING id`,
      [
        event.name,
        event.subjectType,
        event.subjectId,
        occurrenceKey,
        JSON.stringify(event.props || {}),
      ],
    );
    return res.rows.length > 0;
  } catch (err) {
    console.error("[events] Error registrando evento:", event.name, err);
    return false;
  }
}
