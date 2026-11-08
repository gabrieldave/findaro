"use client";

import { Suspense, useEffect, useState } from "react";
import { useSearchParams } from "next/navigation";
import styles from "../marketing.module.css";

function GraciasInner() {
  const params = useSearchParams();
  const sessionId = params.get("session_id") || "";
  const [downloadUrl, setDownloadUrl] = useState<string | null>(null);
  const [msg, setMsg] = useState("Confirmando tu pago…");

  useEffect(() => {
    if (!sessionId) {
      setMsg("Falta session_id. Si pagaste, revisa tu correo o el panel admin.");
      return;
    }
    let tries = 0;
    const tick = async () => {
      tries += 1;
      const res = await fetch("/api/gracias/confirm", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ sessionId }),
      });
      const json = await res.json();
      if (json.ok && json.data?.downloadUrl) {
        setDownloadUrl(json.data.downloadUrl);
        setMsg(`Listo, ${json.data.name || "gracias"}. Tu descarga está lista.`);
        return;
      }
      if (tries < 12) {
        setMsg("Esperando confirmación de Stripe…");
        setTimeout(tick, 2500);
      } else {
        setMsg(
          json.error ||
            "Pago recibido; la descarga llegará cuando Stripe confirme. Escribe a soporte si tarda más de 5 min.",
        );
      }
    };
    void tick();
  }, [sessionId]);

  return (
    <main className={styles.page}>
      <div className={styles.card}>
        <p className={styles.brand}>FINDARO</p>
        <h1>¡Gracias!</h1>
        <p className={styles.sub}>{msg}</p>
        {downloadUrl && (
          <a className={styles.cta} href={downloadUrl}>
            Descargar Findaro.dmg
          </a>
        )}
      </div>
    </main>
  );
}

export default function GraciasPage() {
  return (
    <Suspense fallback={<main className={styles.page}><p>Cargando…</p></main>}>
      <GraciasInner />
    </Suspense>
  );
}
