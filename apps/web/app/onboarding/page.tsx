"use client";

import { FormEvent, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { BootstrapTenantInputSchema } from "@agenda-profissional/shared";
import { getSupabaseBrowserClient } from "@/lib/supabase-browser";
import { parseAccessPath } from "@/lib/access-path";
import { getFunctionErrorMessage } from "@/lib/function-error";
import { formatPhone } from "@/lib/phone";

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
    supabase.auth.getUser().then(({ data }) => {
      if (!data.user) {
        router.push("/login");
        return;
      }

      const path = parseAccessPath(data.user.user_metadata?.access_path);
      if (path === "client") {
        router.push("/client-area");
      }
    });
  }, [router]);

  async function handleSubmit(event: FormEvent) {
    event.preventDefault();
    setError(null);
    setStatus(null);

    const resolvedFullName = tenantType === "individual" ? tenantName.trim() : fullName.trim();
    const parsed = BootstrapTenantInputSchema.safeParse({
      tenant_type: tenantType,
      tenant_name: tenantName,
      full_name: resolvedFullName,
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
      setError(await getFunctionErrorMessage(fnError, "Nao foi possivel concluir a configuracao inicial."));
      return;
    }

    setStatus(`Organizacao inicializada: ${data.tenant_id}`);
    router.push("/dashboard");
  }

  return (
    <section className="card col medium">
      <h1>Configuração inicial</h1>
      <p>Configure seu perfil para iniciar sua agenda profissional.</p>
      <form className="col" onSubmit={handleSubmit}>
        <label className="col">
          Tipo de conta
          <select value={tenantType} onChange={(e) => setTenantType(e.target.value as "individual" | "group")}>
            <option value="individual">Individual (PF)</option>
            <option value="group">Equipe / Empresa (PJ)</option>
          </select>
        </label>

        <label className="col">
          Nome profissional ou da empresa
          <input
            value={tenantName}
            onChange={(e) => {
              const value = e.target.value;
              setTenantName(value);
              if (tenantType === "individual") {
                setFullName(value);
              }
            }}
            required
          />
        </label>

        {tenantType === "group" ? (
          <label className="col">
            Nome completo
            <input value={fullName} onChange={(e) => setFullName(e.target.value)} required />
          </label>
        ) : null}

        <label className="col">
          Telefone
          <input
            value={phone}
            onChange={(e) => setPhone(formatPhone(e.target.value))}
            inputMode="tel"
            placeholder="(11) 99999-9999"
          />
        </label>

        {status ? <div className="notice">{status}</div> : null}
        {error ? <div className="error">{error}</div> : null}

        <button type="submit">Concluir configuração</button>
      </form>
    </section>
  );
}




