import { Fragment, type CSSProperties, type ElementType } from "react";
import s from "./landing.module.css";

/** Titular que entra palabra por palabra (opacidad + desplazamiento + blur), escalonado. */
export default function KineticTitle({
  text,
  as: Tag = "h1",
  className,
  id,
  mode = "reveal",
}: {
  text: string;
  as?: ElementType;
  className?: string;
  id?: string;
  /** "enter": anima al cargar (solo CSS, no espera a JS). "reveal": anima al entrar en pantalla. */
  mode?: "enter" | "reveal";
}) {
  const words = text.split(" ");
  return (
    <Tag className={className} data-rv={mode === "reveal" ? "" : undefined} id={id}>
      {words.map((word, i) => (
        <Fragment key={i}>
          <span className={s.w} style={{ "--d": i } as CSSProperties}>
            {word}
          </span>
          {i < words.length - 1 ? " " : null}
        </Fragment>
      ))}
    </Tag>
  );
}
