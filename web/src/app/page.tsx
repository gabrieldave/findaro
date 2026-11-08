import { redirect } from "next/navigation";

/** Landing marketing estática (HTML migrado) vive en /findaro-landing.html */
export default function Home() {
  redirect("/findaro-landing.html");
}
