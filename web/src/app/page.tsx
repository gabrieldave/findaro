import { redirect } from "next/navigation";

export default async function Home(props: {
  searchParams: Promise<{ ref?: string }>;
}) {
  const searchParams = await props.searchParams;
  const ref = searchParams?.ref;
  if (ref) {
    redirect(`/comprar?ref=${encodeURIComponent(ref)}`);
  }
  redirect("/findaro-landing.html");
}
