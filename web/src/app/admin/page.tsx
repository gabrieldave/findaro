"use client";

import { FormEvent, useState } from "react";
import styles from "../marketing.module.css";

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
  license_key: string | null;
  license_plan: string | null;
  license_seats: number | null;
  license_revoked: boolean | null;
  active_macs: number;
  referred_count: number;
};

export default function AdminPage() {
  const [email, setEmail] = useState("");
  const [secret, setSecret] = useState("");
  const [rows, setRows] = useState<CustomerRow[]>([]);
  const [offer, setOffer] = useState<string>("");
  const [error, setError] = useState<string | null>(null);
  const [authed, setAuthed] = useState(false);
  const [actionMsg, setActionMsg] = useState<string | null>(null);

  async function loadCustomers() {
    const res = await fetch("/api/admin/customers");
    const json = await res.json();
    if (!json.ok) {
      setAuthed(false);
      setError(json.error || "No autorizado");
      return;
    }
    setAuthed(true);
    setRows(json.data.customers || []);
    const o = json.data.offer;
    setOffer(
      o ? `${o.label} · vendidos ${o.soldCount}/${o.promoLimit}` : "",
    );
  }

  async function onLogin(e: FormEvent) {
    e.preventDefault();
    setError(null);
    const res = await fetch("/api/admin/login", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email, secret }),
    });
    const json = await res.json();
    if (!json.ok) {
      setError(json.error || "Login fallido");
      return;
    }
    await loadCustomers();
  }

  async function toggleLicense(licenseKey: string, revoke: boolean) {
    setActionMsg(null);
    try {
      const res = await fetch("/api/admin/license", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ licenseKey, action: revoke ? "revoke" : "restore" }),
      });
      const json = await res.json();
      if (!json.ok) throw new Error(json.error);
      setActionMsg(json.data.message);
      await loadCustomers();
    } catch (err) {
      setActionMsg(err instanceof Error ? err.message : "Error al modificar licencia");
    }
  }

  async function resetActivations(licenseKey: string) {
    if (!confirm(`¿Liberar todas las Macs registradas para la clave ${licenseKey}?`)) return;
    setActionMsg(null);
    try {
      const res = await fetch("/api/admin/license", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ licenseKey, action: "reset_activations" }),
      });
      const json = await res.json();
      if (!json.ok) throw new Error(json.error);
      setActionMsg(json.data.message);
      await loadCustomers();
    } catch (err) {
      setActionMsg(err instanceof Error ? err.message : "Error");
    }
  }

  return (
    <main className={styles.page}>
      <div className={styles.cardWide} style={{ maxWidth: 1100 }}>
        <p className={styles.brand}>FINDARO · Panel de Administración</p>
        <h1>Control de Clientes, Licencias y Referidos</h1>

        {!authed ? (
          <form className={styles.form} onSubmit={onLogin} style={{ maxWidth: 400, margin: "0 auto" }}>
            <label>
              Email admin
              <input value={email} onChange={(e) => setEmail(e.target.value)} required />
            </label>
            <label>
              Setup secret
              <input
                type="password"
                value={secret}
                onChange={(e) => setSecret(e.target.value)}
                required
              />
            </label>
            {error && <p className={styles.error}>{error}</p>}
            <button className={styles.cta} type="submit">
              Entrar
            </button>
          </form>
        ) : (
          <>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 16 }}>
              <p className={styles.sub} style={{ margin: 0 }}>{offer}</p>
              <button className={styles.secondary} type="button" onClick={() => void loadCustomers()}>
                🔄 Actualizar lista
              </button>
            </div>

            {actionMsg && (
              <div style={{ background: "rgba(56, 189, 248, 0.1)", border: "1px solid #38bdf8", padding: "8px 14px", borderRadius: 6, marginBottom: 16, color: "#38bdf8" }}>
                {actionMsg}
              </div>
            )}

            <div className={styles.tableWrap}>
              <table className={styles.table}>
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
                  {rows.map((r) => (
                    <tr key={r.id}>
                      <td>
                        <strong>{r.name || "Sin nombre"}</strong>
                        <br />
                        <span style={{ fontSize: 12, color: "#94a3b8" }}>{r.email}</span>
                      </td>
                      <td>
                        <span style={{
                          padding: "2px 8px",
                          borderRadius: 4,
                          fontSize: 12,
                          background: r.status === "paid" ? "rgba(34, 197, 94, 0.2)" : "rgba(234, 179, 8, 0.2)",
                          color: r.status === "paid" ? "#4ade80" : "#facc15"
                        }}>
                          {r.status || "registrado"}
                        </span>
                      </td>
                      <td>{r.amount_usd ? `$${r.amount_usd} USD` : "—"}</td>
                      <td>
                        {r.license_key ? (
                          <div>
                            <span style={{ fontFamily: "monospace", fontSize: 12 }}>{r.license_key}</span>
                            <br />
                            <span style={{ fontSize: 11, color: r.license_revoked ? "#ef4444" : "#94a3b8" }}>
                              {r.license_revoked ? "🚨 REVOCADA" : `${r.license_plan} (${r.license_seats} asientos)`}
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
                        ) : "—"}
                      </td>
                      <td>
                        <span style={{ fontSize: 12 }}>
                          {r.referred_count} {r.referred_count === 1 ? "amigo" : "amigos"}
                          {r.referral_code && <span style={{ color: "#64748b" }}> ({r.referral_code})</span>}
                        </span>
                      </td>
                      <td>
                        {r.license_key && (
                          <div style={{ display: "flex", gap: 6 }}>
                            {r.license_revoked ? (
                              <button
                                type="button"
                                onClick={() => toggleLicense(r.license_key!, false)}
                                style={{ background: "#16a34a", color: "#fff", border: "none", padding: "4px 8px", borderRadius: 4, fontSize: 11, cursor: "pointer" }}
                              >
                                Reactivar
                              </button>
                            ) : (
                              <button
                                type="button"
                                onClick={() => toggleLicense(r.license_key!, true)}
                                style={{ background: "#dc2626", color: "#fff", border: "none", padding: "4px 8px", borderRadius: 4, fontSize: 11, cursor: "pointer" }}
                                title="Kill-switch: bloquea el uso de esta licencia"
                              >
                                Revocar
                              </button>
                            )}

                            <button
                              type="button"
                              onClick={() => resetActivations(r.license_key!)}
                              style={{ background: "#334155", color: "#fff", border: "none", padding: "4px 8px", borderRadius: 4, fontSize: 11, cursor: "pointer" }}
                              title="Libera las Macs activas para que el usuario pueda reinstalar"
                            >
                              Liberar Macs
                            </button>
                          </div>
                        )}
                      </td>
                    </tr>
                  ))}
                  {rows.length === 0 && (
                    <tr>
                      <td colSpan={7} style={{ textAlign: "center", padding: 24, color: "#64748b" }}>
                        No hay clientes registrados aún.
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
