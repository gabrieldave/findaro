"use client";

import { FormEvent, useEffect, useState } from "react";
import styles from "../marketing.module.css";

type Offer = {
  amountUsd: number;
  isPromo: boolean;
  remaining: number;
  promoLimit: number;
  regularPrice: number;
  label: string;
};

export default function ComprarPage() {
  const [offer, setOffer] = useState<Offer | null>(null);
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    fetch("/api/promo")
      .then((r) => r.json())
      .then((j) => j.ok && setOffer(j.data))
      .catch(() => setOffer(null));
  }, []);

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const res = await fetch("/api/checkout", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ name, email }),
      });
      const json = await res.json();
      if (!json.ok || !json.data?.url) {
        throw new Error(json.error || "No se pudo iniciar el pago");
      }
      window.location.href = json.data.url;
    } catch (err) {
      setError(err instanceof Error ? err.message : "Error");
      setBusy(false);
    }
  }

  return (
    <main className={styles.page}>
      <div className={styles.card}>
        <p className={styles.brand}>FINDARO</p>
        <h1>Licencia de por vida</h1>
        <p className={styles.sub}>
          Un solo pago. Actualizaciones incluidas. Descarga protegida tras Stripe.
        </p>

        {offer && (
          <div className={styles.priceBox}>
            <div className={styles.price}>${offer.amountUsd} USD</div>
            <p>{offer.label}</p>
            {offer.isPromo && (
              <p className={styles.promo}>
                Después de {offer.promoLimit} licencias el precio sube a $
                {offer.regularPrice}.
              </p>
            )}
          </div>
        )}

        <form className={styles.form} onSubmit={onSubmit}>
          <label>
            Nombre
            <input
              required
              minLength={2}
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="Tu nombre"
              autoComplete="name"
            />
          </label>
          <label>
            Correo
            <input
              required
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="tu@email.com"
              autoComplete="email"
            />
          </label>
          {error && <p className={styles.error}>{error}</p>}
          <button type="submit" disabled={busy} className={styles.cta}>
            {busy ? "Redirigiendo a Stripe…" : `Pagar $${offer?.amountUsd ?? 59} con Stripe`}
          </button>
        </form>
        <p className={styles.note}>
          Stripe cobra en la moneda local de tu tarjeta cuando aplica. Sin suscripción.
        </p>
      </div>
    </main>
  );
}
