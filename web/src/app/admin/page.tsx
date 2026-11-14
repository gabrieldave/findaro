"use client";

import { FormEvent, useCallback, useEffect, useMemo, useState } from "react";
import styles from "../marketing.module.css";

type LicenseTier = "solo" | "personal" | "family";

type CustomerRow = {
  id: string;
  email: string;
  name: string;
  referral_code: string | null;
  created_at: string;
  order_id: string | null;
  amount_usd: string | null;
  status: string | null;
  paid_at: string | null;
  promo_slot: boolean | null;
  license_id: string | null;
  license_key: string | null;
  license_plan: string | null;
  license_tier: string | null;
  license_seats: number | null;
  license_revoked: boolean | null;
  active_macs: number;
  referred_count: number;
};

type AdminStats = {
  revenueUsd: number;
  paidOrders: number;
  paidOrdersByTier: Record<string, number>;
  proLicenses: number;
  totalCustomers: number;
  activeTrials: number;
  trafficBySource: Array<{
    utm_source: string;
    visits: number;
    customers: number;
    paid: number;
  }>;
  pendingReferrals: { count: number; amountUsd: number };
};

type FilterTab = "all" | "paid" | "trials" | "revoked";

const OAUTH_ERROR_MESSAGES: Record<string, string> = {
  unauthorized_email:
    "Tu cuenta de Google no está autorizada para acceder a /admin.",
  oauth_state: "La sesión de Google OAuth expiró o es inválida. Inténtalo de nuevo.",
  oauth_not_configured:
    "Falta GOOGLE_CLIENT_SECRET en el entorno del servidor.",
  oauth_token: "Google rechazó el intercambio de token OAuth. Inténtalo de nuevo.",
  oauth_userinfo: "No se pudo consultar el perfil verificado en Google.",
};

export default function AdminPage() {
  const [adminEmail, setAdminEmail] = useState<string>("");
  const [rows, setRows] = useState<CustomerRow[]>([]);
  const [stats, setStats] = useState<AdminStats | null>(null);
  const [offer, setOffer] = useState<string>("");
  const [error, setError] = useState<string | null>(null);
  const [authed, setAuthed] = useState(false);
  const [checkingSession, setCheckingSession] = useState(true);
  const [actionMsg, setActionMsg] = useState<string | null>(null);
  const [filter, setFilter] = useState<FilterTab>("all");

  // Manual Pro issuance state
  const [manualEmail, setManualEmail] = useState("");
  const [manualName, setManualName] = useState("");
  const [manualTier, setManualTier] = useState<LicenseTier>("personal");
  const [manualLang, setManualLang] = useState<"es" | "en">("es");
  const [manualSendEmail, setManualSendEmail] = useState(true);
  const [submittingManual, setSubmittingManual] = useState(false);

  const loadCustomers = useCallback(async () => {
    try {
      const res = await fetch("/api/admin/customers", { cache: "no-store" });
      const json = (await res.json()) as {
        ok?: boolean;
        error?: string;
        data?: {
          admin?: string;
          customers?: CustomerRow[];
          stats?: AdminStats;
          offer?: { label?: string; soldCount?: number };
        };
      };
      if (!json.ok || !json.data) {
        setAuthed(false);
        setRows([]);
        setStats(null);
        return;
      }
      setError(null);
      setAuthed(true);
      setAdminEmail(json.data.admin || "");
      setRows(json.data.customers || []);
      setStats(json.data.stats || null);
      const o = json.data.offer;
      setOffer(o ? `${o.label || ""}` : "");
    } catch {
      setAuthed(false);
    } finally {
      setCheckingSession(false);
    }
  }, []);

  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    const errCode = params.get("error");
    if (errCode) {
      setError(
        OAUTH_ERROR_MESSAGES[errCode] || "Error al iniciar sesión con Google.",
      );
    }
    void loadCustomers();
  }, [loadCustomers]);

  async function onLogout() {
    await fetch("/api/admin/logout", { method: "POST" });
    setAuthed(false);
    setAdminEmail("");
    setRows([]);
    setStats(null);
    setActionMsg(null);
  }

  async function toggleLicense(licenseKey: string, revoke: boolean) {
    setActionMsg(null);
    try {
      const res = await fetch("/api/admin/license", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          licenseKey,
          action: revoke ? "revoke" : "restore",
        }),
      });
      const json = (await res.json()) as {
        ok?: boolean;
        error?: string;
        data?: { message?: string };
      };
      if (!json.ok) throw new Error(json.error || "Error al modificar licencia");
      setActionMsg(json.data?.message || "Actualizado");
      await loadCustomers();
    } catch (err) {
      setActionMsg(
        err instanceof Error ? err.message : "Error al modificar licencia",
      );
    }
  }

  async function resetActivations(licenseKey: string) {
    if (
      !confirm(
        `¿Liberar todas las Macs registradas para la clave ${licenseKey}?`,
      )
    )
      return;
    setActionMsg(null);
    try {
      const res = await fetch("/api/admin/license", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ licenseKey, action: "reset_activations" }),
      });
      const json = (await res.json()) as {
        ok?: boolean;
        error?: string;
        data?: { message?: string };
      };
      if (!json.ok) throw new Error(json.error || "Error");
      setActionMsg(json.data?.message || "Activaciones liberadas");
      await loadCustomers();
    } catch (err) {
      setActionMsg(err instanceof Error ? err.message : "Error");
    }
  }

  async function resendEmail(licenseKey: string, email: string) {
    setActionMsg(null);
    try {
      const res = await fetch("/api/admin/license", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          licenseKey,
          action: "resend_email",
          lang: manualLang,
        }),
      });
      const json = (await res.json()) as {
        ok?: boolean;
        error?: string;
        data?: { message?: string };
      };
      if (!json.ok) {
        throw new Error(
          json.error || `No se pudo reenviar el correo a ${email}`,
        );
      }
      setActionMsg(json.data?.message || `Correo reenviado a ${email}`);
    } catch (err) {
      setActionMsg(
        err instanceof Error ? err.message : "Error al reenviar correo",
      );
    }
  }

  async function onIssueManual(e: FormEvent) {
    e.preventDefault();
    setActionMsg(null);
    setSubmittingManual(true);
    try {
      const res = await fetch("/api/admin/license", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          action: "issue_manual",
          email: manualEmail,
          name: manualName,
          tier: manualTier,
          lang: manualLang,
          sendEmail: manualSendEmail,
        }),
      });
      const json = (await res.json()) as {
        ok?: boolean;
        error?: string;
        data?: { message?: string };
      };
      if (!json.ok) throw new Error(json.error || "Error al emitir licencia");
      setActionMsg(json.data?.message || "Licencia Pro emitida");
      setManualEmail("");
      setManualName("");
      await loadCustomers();
    } catch (err) {
      setActionMsg(
        err instanceof Error ? err.message : "Error al emitir licencia",
      );
    } finally {
      setSubmittingManual(false);
    }
  }

  const filtered = useMemo(() => {
    switch (filter) {
      case "paid":
        return rows.filter((r) => r.status === "paid");
      case "trials":
        return rows.filter((r) => r.license_plan === "trial");
      case "revoked":
        return rows.filter((r) => r.license_revoked);
      default:
        return rows;
    }
  }, [rows, filter]);

  const sourceLabel = (src: string) => {
    const s = src.toLowerCase();
    if (s === "x" || s === "twitter") return "X";
    if (s === "facebook" || s === "fb") return "Facebook";
    if (s === "direct") return "Directo";
    return src;
  };

  const topSources = (stats?.trafficBySource || []).slice(0, 3);
  const sourceSummary =
    topSources.length === 0
      ? "—"
      : topSources
          .map((s) => `${sourceLabel(s.utm_source)} ${s.paid}/${s.visits}`)
          .join(" · ");

  const kpiCard = (title: string, value: string, sub?: string) => (
    <div
      style={{
        background: "rgba(15,23,42,0.7)",
        border: "1px solid #1e293b",
        borderRadius: 12,
        padding: "14px 16px",
        minWidth: 0,
        fontVariantNumeric: "tabular-nums",
      }}
    >
      <div style={{ fontSize: 12, color: "#94a3b8", marginBottom: 6 }}>
        {title}
      </div>
      <div
        style={{
          fontSize: 22,
          fontWeight: 800,
          color: "#fff",
          fontVariantNumeric: "tabular-nums",
        }}
      >
        {value}
      </div>
      {sub ? (
        <div
          style={{
            fontSize: 11,
            color: "#64748b",
            marginTop: 4,
            fontVariantNumeric: "tabular-nums",
          }}
        >
          {sub}
        </div>
      ) : null}
    </div>
  );

  return (
    <main
      className={styles.page}
      style={{ fontVariantNumeric: "tabular-nums" }}
    >
      <div className={styles.cardWide} style={{ maxWidth: 1180 }}>
        <p className={styles.brand}>FINDARO · Panel de Administración</p>
        <h1>Control de Clientes, Licencias y Referidos</h1>

        {checkingSession ? (
          <p className={styles.sub}>Verificando sesión de administrador…</p>
        ) : !authed ? (
          <div
            style={{
              maxWidth: 420,
              margin: "24px auto 8px",
              padding: 24,
              borderRadius: 14,
              background: "rgba(15,23,42,0.7)",
              border: "1px solid #1e293b",
              textAlign: "center",
            }}
          >
            <p className={styles.sub} style={{ marginTop: 0 }}>
              Acceso restringido mediante Google OAuth 2.0 oficial para cuentas
              autorizadas de BLACK EYE.
            </p>
            {error && <p className={styles.error}>{error}</p>}
            <a
              href="/api/auth/google"
              className={styles.cta}
              style={{ width: "100%", marginTop: 12 }}
            >
              Continuar con Google
            </a>
          </div>
        ) : (
          <>
            <div
              style={{
                display: "flex",
                justifyContent: "space-between",
                alignItems: "center",
                marginBottom: 16,
                gap: 12,
                flexWrap: "wrap",
              }}
            >
              <p className={styles.sub} style={{ margin: 0 }}>
                Sesión: <strong>{adminEmail}</strong>
                {offer ? ` · ${offer}` : ""}
              </p>
              <div style={{ display: "flex", gap: 8 }}>
                <button
                  className={styles.secondary}
                  type="button"
                  onClick={() => void loadCustomers()}
                >
                  Actualizar
                </button>
                <button
                  className={styles.secondary}
                  type="button"
                  onClick={() => void onLogout()}
                >
                  Cerrar sesión
                </button>
              </div>
            </div>

            {stats && (
              <div
                style={{
                  display: "grid",
                  gridTemplateColumns: "repeat(auto-fit, minmax(175px, 1fr))",
                  gap: 10,
                  marginBottom: 18,
                }}
              >
                {kpiCard("Ingresos USD", `$${stats.revenueUsd.toFixed(2)}`)}
                {kpiCard(
                  "Órdenes / Clientes",
                  `${stats.paidOrders} / ${stats.totalCustomers}`,
                  `solo ${stats.paidOrdersByTier.solo || 0} · personal ${stats.paidOrdersByTier.personal || 0} · family ${stats.paidOrdersByTier.family || 0}`,
                )}
                {kpiCard(
                  "Licencias Emitidas",
                  `${stats.proLicenses} Pro`,
                  `${stats.activeTrials} pruebas activas 14d`,
                )}
                {kpiCard("Origen UTM: X / Facebook / Directo", sourceSummary)}
                {kpiCard(
                  "Referidos Pendientes",
                  String(stats.pendingReferrals.count),
                  `$${stats.pendingReferrals.amountUsd.toFixed(2)} USD`,
                )}
              </div>
            )}

            <form
              onSubmit={(e) => void onIssueManual(e)}
              style={{
                background: "rgba(15,23,42,0.7)",
                border: "1px solid #1e293b",
                borderRadius: 12,
                padding: 16,
                marginBottom: 18,
                display: "grid",
                gridTemplateColumns: "repeat(auto-fit, minmax(160px, 1fr))",
                gap: 10,
                alignItems: "end",
              }}
            >
              <div>
                <div
                  style={{
                    fontSize: 12,
                    color: "#94a3b8",
                    marginBottom: 4,
                    fontWeight: 600,
                  }}
                >
                  Emitir licencia Pro manual · Email
                </div>
                <input
                  type="email"
                  required
                  placeholder="cliente@ejemplo.com"
                  value={manualEmail}
                  onChange={(e) => setManualEmail(e.target.value)}
                  style={{
                    width: "100%",
                    borderRadius: 8,
                    border: "1px solid #334155",
                    background: "#0b1220",
                    color: "#fff",
                    padding: "8px 10px",
                    fontSize: 13,
                  }}
                />
              </div>
              <div>
                <div style={{ fontSize: 12, color: "#94a3b8", marginBottom: 4 }}>
                  Nombre (opcional)
                </div>
                <input
                  type="text"
                  placeholder="Nombre del cliente"
                  value={manualName}
                  onChange={(e) => setManualName(e.target.value)}
                  style={{
                    width: "100%",
                    borderRadius: 8,
                    border: "1px solid #334155",
                    background: "#0b1220",
                    color: "#fff",
                    padding: "8px 10px",
                    fontSize: 13,
                  }}
                />
              </div>
              <div>
                <div style={{ fontSize: 12, color: "#94a3b8", marginBottom: 4 }}>
                  Tier Pro
                </div>
                <select
                  value={manualTier}
                  onChange={(e) => setManualTier(e.target.value as LicenseTier)}
                  style={{
                    width: "100%",
                    borderRadius: 8,
                    border: "1px solid #334155",
                    background: "#0b1220",
                    color: "#fff",
                    padding: "8px 10px",
                    fontSize: 13,
                  }}
                >
                  <option value="solo">solo (1 Mac · $29)</option>
                  <option value="personal">personal / Pro (2 Macs · $39)</option>
                  <option value="family">family (5 Macs · $59)</option>
                </select>
              </div>
              <div>
                <div style={{ fontSize: 12, color: "#94a3b8", marginBottom: 4 }}>
                  Idioma correo
                </div>
                <select
                  value={manualLang}
                  onChange={(e) =>
                    setManualLang(e.target.value === "en" ? "en" : "es")
                  }
                  style={{
                    width: "100%",
                    borderRadius: 8,
                    border: "1px solid #334155",
                    background: "#0b1220",
                    color: "#fff",
                    padding: "8px 10px",
                    fontSize: 13,
                  }}
                >
                  <option value="es">Español (es)</option>
                  <option value="en">English (en)</option>
                </select>
              </div>
              <label
                style={{
                  display: "flex",
                  alignItems: "center",
                  gap: 8,
                  fontSize: 12,
                  color: "#cbd5e1",
                  paddingBottom: 8,
                  cursor: "pointer",
                }}
              >
                <input
                  type="checkbox"
                  checked={manualSendEmail}
                  onChange={(e) => setManualSendEmail(e.target.checked)}
                />
                Enviar correo
              </label>
              <button
                type="submit"
                disabled={submittingManual}
                className={styles.cta}
                style={{ marginTop: 0, padding: "9px 14px", fontSize: 13 }}
              >
                {submittingManual ? "Emitiendo…" : "Emitir Pro"}
              </button>
            </form>

            <div
              style={{
                display: "flex",
                gap: 8,
                marginBottom: 14,
                flexWrap: "wrap",
              }}
            >
              {(
                [
                  ["all", "Todos"],
                  ["paid", "Pagados"],
                  ["trials", "Pruebas"],
                  ["revoked", "Revocados"],
                ] as Array<[FilterTab, string]>
              ).map(([key, label]) => (
                <button
                  key={key}
                  type="button"
                  onClick={() => setFilter(key)}
                  style={{
                    border:
                      filter === key
                        ? "1px solid #38bdf8"
                        : "1px solid #334155",
                    background:
                      filter === key ? "rgba(56,189,248,0.15)" : "transparent",
                    color: filter === key ? "#38bdf8" : "#94a3b8",
                    borderRadius: 999,
                    padding: "6px 12px",
                    fontSize: 12,
                    cursor: "pointer",
                  }}
                >
                  {label}
                </button>
              ))}
            </div>

            {actionMsg && (
              <div
                style={{
                  background: "rgba(56, 189, 248, 0.1)",
                  border: "1px solid #38bdf8",
                  padding: "8px 14px",
                  borderRadius: 6,
                  marginBottom: 16,
                  color: "#38bdf8",
                }}
              >
                {actionMsg}
              </div>
            )}

            <div className={styles.tableWrap}>
              <table
                className={styles.table}
                style={{ fontVariantNumeric: "tabular-nums" }}
              >
                <thead>
                  <tr>
                    <th>Cliente</th>
                    <th>Estado</th>
                    <th>Pago</th>
                    <th>Licencia</th>
                    <th>Macs Activas</th>
                    <th>Referidos</th>
                    <th>Acciones</th>
                  </tr>
                </thead>
                <tbody>
                  {filtered.map((r) => (
                    <tr key={r.id}>
                      <td>
                        <strong>{r.name || "Sin nombre"}</strong>
                        <br />
                        <span style={{ fontSize: 12, color: "#94a3b8" }}>
                          {r.email}
                        </span>
                      </td>
                      <td>
                        <span
                          style={{
                            padding: "2px 8px",
                            borderRadius: 4,
                            fontSize: 12,
                            background:
                              r.status === "paid"
                                ? "rgba(34, 197, 94, 0.2)"
                                : "rgba(234, 179, 8, 0.2)",
                            color: r.status === "paid" ? "#4ade80" : "#facc15",
                          }}
                        >
                          {r.status || "registrado"}
                        </span>
                      </td>
                      <td>{r.amount_usd != null ? `$${r.amount_usd} USD` : "—"}</td>
                      <td>
                        {r.license_key ? (
                          <div>
                            <span
                              style={{ fontFamily: "monospace", fontSize: 12 }}
                            >
                              {r.license_key}
                            </span>
                            <br />
                            <span
                              style={{
                                fontSize: 11,
                                color: r.license_revoked
                                  ? "#ef4444"
                                  : "#94a3b8",
                              }}
                            >
                              {r.license_revoked
                                ? "REVOCADA"
                                : `${r.license_plan} · ${r.license_tier || r.license_plan} (${r.license_seats} asientos)`}
                            </span>
                          </div>
                        ) : (
                          "—"
                        )}
                      </td>
                      <td>
                        {r.license_key ? (
                          <span style={{ fontSize: 13, fontWeight: "bold" }}>
                            {r.active_macs} / {r.license_seats || 2}
                          </span>
                        ) : (
                          "—"
                        )}
                      </td>
                      <td>
                        <span style={{ fontSize: 12 }}>
                          {r.referred_count}{" "}
                          {r.referred_count === 1 ? "amigo" : "amigos"}
                          {r.referral_code && (
                            <span style={{ color: "#64748b" }}>
                              {" "}
                              ({r.referral_code})
                            </span>
                          )}
                        </span>
                      </td>
                      <td>
                        {r.license_key && (
                          <div
                            style={{
                              display: "flex",
                              gap: 6,
                              flexWrap: "wrap",
                            }}
                          >
                            {!r.license_revoked && (
                              <button
                                type="button"
                                onClick={() =>
                                  void resendEmail(r.license_key!, r.email)
                                }
                                style={{
                                  background: "#0284c7",
                                  color: "#fff",
                                  border: "none",
                                  padding: "4px 8px",
                                  borderRadius: 4,
                                  fontSize: 11,
                                  cursor: "pointer",
                                }}
                              >
                                Reenviar correo
                              </button>
                            )}

                            {r.license_revoked ? (
                              <button
                                type="button"
                                onClick={() =>
                                  void toggleLicense(r.license_key!, false)
                                }
                                style={{
                                  background: "#16a34a",
                                  color: "#fff",
                                  border: "none",
                                  padding: "4px 8px",
                                  borderRadius: 4,
                                  fontSize: 11,
                                  cursor: "pointer",
                                }}
                              >
                                Reactivar
                              </button>
                            ) : (
                              <button
                                type="button"
                                onClick={() =>
                                  void toggleLicense(r.license_key!, true)
                                }
                                style={{
                                  background: "#dc2626",
                                  color: "#fff",
                                  border: "none",
                                  padding: "4px 8px",
                                  borderRadius: 4,
                                  fontSize: 11,
                                  cursor: "pointer",
                                }}
                                title="Kill-switch: bloquea el uso de esta licencia"
                              >
                                Revocar
                              </button>
                            )}

                            <button
                              type="button"
                              onClick={() =>
                                void resetActivations(r.license_key!)
                              }
                              style={{
                                background: "#334155",
                                color: "#fff",
                                border: "none",
                                padding: "4px 8px",
                                borderRadius: 4,
                                fontSize: 11,
                                cursor: "pointer",
                              }}
                              title="Libera las Macs activas para que el usuario pueda reinstalar"
                            >
                              Liberar Macs
                            </button>
                          </div>
                        )}
                      </td>
                    </tr>
                  ))}
                  {filtered.length === 0 && (
                    <tr>
                      <td
                        colSpan={7}
                        style={{
                          textAlign: "center",
                          padding: 24,
                          color: "#64748b",
                        }}
                      >
                        No hay clientes en este filtro.
                      </td>
                    </tr>
                  )}
                </tbody>
              </table>
            </div>
          </>
        )}
      </div>
    </main>
  );
}
