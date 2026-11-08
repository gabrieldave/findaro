"use client";

import { FormEvent, useState } from "react";
import styles from "../marketing.module.css";

type CustomerRow = {
  id: string;
  email: string;
  name: string;
  created_at: string;
  order_id: string | null;
  amount_usd: string | null;
  status: string | null;
  paid_at: string | null;
  promo_slot: boolean | null;
};

export default function AdminPage() {
  const [email, setEmail] = useState("");
  const [secret, setSecret] = useState("");
  const [rows, setRows] = useState<CustomerRow[]>([]);
  const [offer, setOffer] = useState<string>("");
  const [error, setError] = useState<string | null>(null);
  const [authed, setAuthed] = useState(false);

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
      o
        ? `${o.label} · vendidos ${o.soldCount}/${o.promoLimit}`
        : "",
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

  return (
    <main className={styles.page}>
      <div className={styles.cardWide}>
        <p className={styles.brand}>FINDARO · Admin</p>
        <h1>Clientes</h1>
        {!authed ? (
          <form className={styles.form} onSubmit={onLogin}>
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
            <p className={styles.sub}>{offer}</p>
            <button className={styles.secondary} type="button" onClick={() => void loadCustomers()}>
              Actualizar
            </button>
            <div className={styles.tableWrap}>
              <table className={styles.table}>
                <thead>
                  <tr>
                    <th>Nombre</th>
                    <th>Email</th>
                    <th>Estado</th>
                    <th>USD</th>
                    <th>Promo</th>
                    <th>Pago</th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map((r) => (
                    <tr key={r.id}>
                      <td>{r.name}</td>
                      <td>{r.email}</td>
                      <td>{r.status || "—"}</td>
                      <td>{r.amount_usd || "—"}</td>
                      <td>{r.promo_slot ? "sí" : "—"}</td>
                      <td>
                        {r.paid_at
                          ? new Date(r.paid_at).toLocaleString("es")
                          : "—"}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </>
        )}
      </div>
    </main>
  );
}
