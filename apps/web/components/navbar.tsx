"use client";

import Image from "next/image";
import Link from "next/link";
import { useEffect, useState } from "react";
import { getSupabaseBrowserClient } from "@/lib/supabase-browser";

type ProfileState = {
  full_name: string;
  role: "owner" | "admin" | "staff" | "receptionist";
} | null;

export function Navbar() {
  const [profile, setProfile] = useState<ProfileState>(null);

  useEffect(() => {
    const supabase = getSupabaseBrowserClient();

    supabase.auth.getUser().then(async ({ data }: { data: { user: { id: string } | null } }) => {
      if (!data.user) return;

      const { data: profileData } = await supabase
        .from("profiles")
        .select("full_name, role")
        .eq("id", data.user.id)
        .maybeSingle();

      if (profileData) {
        setProfile(profileData as ProfileState);
      }
    });
  }, []);

  const canManage = profile && ["owner", "admin", "receptionist"].includes(profile.role);

  async function signOut() {
    const supabase = getSupabaseBrowserClient();
    await supabase.auth.signOut();
    window.location.href = "/login";
  }

  return (
    <header className="nav">
      <div className="nav-inner">
        <div className="row align-center">
          <Link className="nav-brand" href="/dashboard">
            <Image
              src="/brand/agenda-logo.png"
              width={36}
              height={36}
              alt="Agenda Profissional"
              priority
            />
            <strong>Agenda Profissional</strong>
          </Link>
          {profile ? <small className="nav-meta">{profile.full_name}</small> : null}
        </div>

        <nav className="nav-links">
          <Link href="/dashboard">Dashboard</Link>
          {canManage ? <Link href="/clients">Clientes</Link> : null}
          {canManage ? <Link href="/services">Serviços</Link> : null}
          {canManage ? <Link href="/professionals">Profissionais</Link> : null}
          {canManage ? <Link href="/schedules">Horários</Link> : null}
          {canManage ? <Link href="/appointments/new">Novo agendamento</Link> : null}
          <Link href="/onboarding">Onboarding</Link>
          <button className="secondary" onClick={signOut} type="button">
            Sair
          </button>
        </nav>
      </div>
    </header>
  );
}

