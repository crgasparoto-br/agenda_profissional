"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { getSupabaseBrowserClient } from "@/lib/supabase-browser";
import { AccessPath, parseAccessPath } from "@/lib/access-path";

type ProfileState = {
  full_name: string;
  tenant_id: string;
  role: "owner" | "admin" | "staff" | "receptionist";
} | null;

type TenantRow = {
  type: "individual" | "group";
} | null;

export function Navbar() {
  const [profile, setProfile] = useState<ProfileState>(null);
  const [accessPath, setAccessPath] = useState<AccessPath>("professional");
  const [tenantAccountType, setTenantAccountType] = useState<"individual" | "group" | null>(null);

  useEffect(() => {
    const supabase = getSupabaseBrowserClient();

    supabase.auth
      .getUser()
      .then(
        async ({ data }: { data: { user: { id: string; user_metadata?: Record<string, unknown> } | null } }) => {
          if (!data.user) return;

          setAccessPath(parseAccessPath(data.user.user_metadata?.access_path));

          const { data: profileData } = await supabase
            .from("profiles")
            .select("full_name, role, tenant_id")
            .eq("id", data.user.id)
            .maybeSingle();

          const typedProfile = profileData as ProfileState;
          if (typedProfile) {
            setProfile(typedProfile);

            const { data: tenantData } = await supabase
              .from("tenants")
              .select("type")
              .eq("id", typedProfile.tenant_id)
              .maybeSingle();

            const accountType = (tenantData as TenantRow)?.type;
            if (accountType === "individual" || accountType === "group") {
              setTenantAccountType(accountType);
            }
          }
        }
      );
  }, []);

  const canManage = profile && ["owner", "admin", "receptionist"].includes(profile.role);

  const showPjRegistrationsMenu = canManage && tenantAccountType === "group";

  async function signOut() {
    const supabase = getSupabaseBrowserClient();
    await supabase.auth.signOut();
    window.location.href = "/login";
  }

  return (
    <aside className="side-nav">
      {profile ? <small className="side-nav-meta">{profile.full_name}</small> : null}

      <nav className="side-nav-links">
        {accessPath === "client" ? (
          <Link href="/client-area">Área do cliente</Link>
        ) : (
          <>
            <Link href="/dashboard">Painel</Link>
            {showPjRegistrationsMenu ? (
              <details className="side-nav-menu">
                <summary className="side-nav-menu-summary">Cadastros</summary>
                <div className="side-nav-menu-panel">
                  <Link href="/clients">Clientes</Link>
                  <Link href="/services">Serviços</Link>
                  <Link href="/professionals">Profissionais</Link>
                  <Link href="/schedules">Horários</Link>
                </div>
              </details>
            ) : null}
            {canManage && !showPjRegistrationsMenu ? <Link href="/clients">Clientes</Link> : null}
            {canManage && !showPjRegistrationsMenu ? <Link href="/services">Serviços</Link> : null}
            {canManage && !showPjRegistrationsMenu ? <Link href="/professionals">Profissionais</Link> : null}
            {canManage && !showPjRegistrationsMenu ? <Link href="/schedules">Horários</Link> : null}
            {canManage ? <Link href="/appointments/new">Novo agendamento</Link> : null}
            <Link href="/onboarding">Configuração inicial</Link>
          </>
        )}
      </nav>

      <button className="secondary side-nav-signout" onClick={signOut} type="button">
        Sair
      </button>
    </aside>
  );
}
