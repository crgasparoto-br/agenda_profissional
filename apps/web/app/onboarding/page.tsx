"use client";

import { FormEvent, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { BootstrapTenantInputSchema } from "@agenda-profissional/shared";
import { getSupabaseBrowserClient } from "@/lib/supabase-browser";

export default function OnboardingPage() {
  const router = useRouter();
  const [tenantType, setTenantType] = useState<"individual" | "group">("individual");
  const [tenantName, setTenantName] = useState("");
  const [fullName, setFullName] = useState("");
  const [phone, setPhone] = useState("");
  const [status, setStatus] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const supabase = getSupabaseBrowserClient();
    supabase.auth.getSession().then(({ data }: { data: { session: unknown } }) => {
      if (!data.session) {
        router.push("/login");
      }
    });
  }, [router]);

  async function handleSubmit(event: FormEvent) {
    event.preventDefault();
    setError(null);
    setStatus(null);

    const parsed = BootstrapTenantInputSchema.safeParse({
      tenant_type: tenantType,
      tenant_name: tenantName,
      full_name: fullName,
      phone
    });

    if (!parsed.success) {
      setError("Dados inválidos");
      return;
    }

    const supabase = getSupabaseBrowserClient();
    const { data, error: fnError } = await supabase.functions.invoke("bootstrap-tenant", {
      body: parsed.data
    });

    if (fnError) {
      setError(fnError.message);
      return;
    }

    setStatus(`Tenant inicializado: ${data.tenant_id}`);
    router.push("/dashboard");
  }

  return (
    <section className="card col medium">
      <h1>Onboarding</h1>
      <p>Cria tenant, profile owner e professional no primeiro acesso.</p>
      <form className="col" onSubmit={handleSubmit}>
        <label className="col">
          Tipo de contratação
          <select value={tenantType} onChange={(e) => setTenantType(e.target.value as "individual" | "group")}>
            <option value="individual">Individual</option>
            <option value="group">Group (clínica)</option>
          </select>
        </label>

        <label className="col">
          Nome do tenant
          <input value={tenantName} onChange={(e) => setTenantName(e.target.value)} required />
        </label>

        <label className="col">
          Nome completo
          <input value={fullName} onChange={(e) => setFullName(e.target.value)} required />
        </label>

        <label className="col">
          Telefone
          <input value={phone} onChange={(e) => setPhone(e.target.value)} />
        </label>

        {status ? <div className="notice">{status}</div> : null}
        {error ? <div className="error">{error}</div> : null}

        <button type="submit">Concluir onboarding</button>
      </form>
    </section>
  );
}




