"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { getSupabaseBrowserClient } from "@/lib/supabase-browser";

export default function ClientAreaPage() {
  const router = useRouter();
  const [email, setEmail] = useState<string | null>(null);

  useEffect(() => {
    const supabase = getSupabaseBrowserClient();

    supabase.auth.getUser().then(({ data }) => {
      if (!data.user) {
        router.push("/login");
        return;
      }

      setEmail(data.user.email ?? null);
    });
  }, [router]);

  return (
    <section className="card col medium">
      <h1>Área do Cliente</h1>
      <p>Você entrou no caminho de cliente.</p>
      <p className="text-muted">Conta: {email ?? "-"}</p>
      <p className="text-muted">Próximo passo: conectar consultas, lembretes e histórico para clientes finais.</p>
    </section>
  );
}
