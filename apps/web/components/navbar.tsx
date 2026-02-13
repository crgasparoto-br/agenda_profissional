"use client";

import Link from "next/link";
import Image from "next/image";
import { useEffect, useState } from "react";
import { ChevronRight, ChevronDown } from "lucide-react";
import { getSupabaseBrowserClient } from "@/lib/supabase-browser";
import { AccessPath, parseAccessPath } from "@/lib/access-path";

type ProfileState = {
  full_name: string;
  tenant_id: string;
  role: "owner" | "admin" | "staff" | "receptionist";
} | null;

type TenantRow = {
  type: "individual" | "group";
  name: string;
  logo_url: string | null;
} | null;

export function Navbar() {
  const [profile, setProfile] = useState<ProfileState>(null);
  const [accessPath, setAccessPath] = useState<AccessPath>("professional");
  const [tenantAccountType, setTenantAccountType] = useState<"individual" | "group" | null>(null);
  const [tenantName, setTenantName] = useState<string>("Agenda Profissional");
  const [tenantLogoUrl, setTenantLogoUrl] = useState<string>("/brand/agenda-logo.png");

  useEffect(() => {
    const supabase = getSupabaseBrowserClient();
    let active = true;

    async function loadProfile() {
      const { data }: { data: { user: { id: string; user_metadata?: Record<string, unknown> } | null } } =
        await supabase.auth.getUser();

      if (!active) return;

      if (!data.user) {
        setAccessPath("professional");
        setProfile(null);
        setTenantAccountType(null);
        setTenantName("Agenda Profissional");
        setTenantLogoUrl("/brand/agenda-logo.png");
        return;
      }

      setAccessPath(parseAccessPath(data.user.user_metadata?.access_path));

      const { data: profileData } = await supabase
        .from("profiles")
        .select("full_name, role, tenant_id")
        .eq("id", data.user.id)
        .maybeSingle();

      if (!active) return;

      const typedProfile = profileData as ProfileState;
      if (!typedProfile) {
        setProfile(null);
        setTenantAccountType(null);
        setTenantName("Agenda Profissional");
        setTenantLogoUrl("/brand/agenda-logo.png");
        return;
      }

      setProfile(typedProfile);

      const { data: tenantData } = await supabase
        .from("tenants")
        .select("type, name, logo_url")
        .eq("id", typedProfile.tenant_id)
        .maybeSingle();

      if (!active) return;

      const accountType = (tenantData as TenantRow)?.type;
      const tenantInfo = tenantData as TenantRow;
      if (accountType === "individual" || accountType === "group") {
        setTenantAccountType(accountType);
      } else {
        setTenantAccountType(null);
      }
      setTenantName(tenantInfo?.name ?? "Agenda Profissional");
      setTenantLogoUrl(tenantInfo?.logo_url ?? "/brand/agenda-logo.png");
    }

    loadProfile();

    const {
      data: { subscription }
    } = supabase.auth.onAuthStateChange(() => {
      loadProfile();
    });

    return () => {
      active = false;
      subscription.unsubscribe();
    };
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
      <div className="side-nav-brand">
        <Image
          src={tenantLogoUrl || "/brand/agenda-logo.png"}
          alt={`Logo ${tenantName}`}
          className="side-nav-logo"
          width={36}
          height={36}
          unoptimized
          onError={() => setTenantLogoUrl("/brand/agenda-logo.png")}
        />
        <strong>{tenantName}</strong>
      </div>
      {profile ? <small className="side-nav-meta">{profile.full_name}</small> : null}

      <nav className="side-nav-links">
        {accessPath === "client" ? (
          <Link href="/client-area">Área do cliente</Link>
        ) : (
          <>
            <Link href="/dashboard">Agenda</Link>
            {showPjRegistrationsMenu ? (
              <details className="side-nav-menu">
                <summary className="side-nav-menu-summary">
                  <span>Cadastros</span>
                  <span className="side-nav-menu-icon" aria-hidden="true">
                    <ChevronRight size={16} className="icon-closed" />
                    <ChevronDown size={16} className="icon-open" />
                  </span>
                </summary>
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
            <details className="side-nav-menu">
              <summary className="side-nav-menu-summary">
                <span>Configurações</span>
                <span className="side-nav-menu-icon" aria-hidden="true">
                  <ChevronRight size={16} className="icon-closed" />
                  <ChevronDown size={16} className="icon-open" />
                </span>
              </summary>
              <div className="side-nav-menu-panel">
                <Link href="/onboarding">Configuração inicial</Link>
                {canManage ? <Link href="/whatsapp">WhatsApp + IA</Link> : null}
              </div>
            </details>
          </>
        )}
      </nav>

      <button className="secondary side-nav-signout" onClick={signOut} type="button">
        Sair
      </button>
    </aside>
  );
}
