"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { getSupabaseBrowserClient } from "@/lib/supabase-browser";
import { parseAccessPath } from "@/lib/access-path";

export default function HomePage() {
  const router = useRouter();

  useEffect(() => {
    let active = true;
    const supabase = getSupabaseBrowserClient();

    async function resolveEntryRoute() {
      const { data } = await supabase.auth.getUser();
      if (!active) return;

      if (!data.user) {
        router.replace("/login");
        return;
      }

      const accessPath = parseAccessPath(data.user.user_metadata?.access_path);
      if (accessPath === "client") {
        router.replace("/client-area");
        return;
      }

      const { data: profileData } = await supabase
        .from("profiles")
        .select("tenant_id")
        .eq("id", data.user.id)
        .maybeSingle();

      if (!active) return;
      router.replace(profileData?.tenant_id ? "/dashboard" : "/onboarding");
    }

    resolveEntryRoute();

    return () => {
      active = false;
    };
  }, [router]);

  return (
    <section className="card col narrow">
      <h1>Agenda Profissional</h1>
      <p>Redirecionando para o acesso correto...</p>
    </section>
  );
}
