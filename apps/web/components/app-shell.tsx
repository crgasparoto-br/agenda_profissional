"use client";

import { useEffect, useMemo, useState } from "react";
import { usePathname, useRouter } from "next/navigation";
import { Navbar } from "@/components/navbar";
import { getSupabaseBrowserClient } from "@/lib/supabase-browser";

export function AppShell({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const router = useRouter();
  const [authState, setAuthState] = useState<"checking" | "authenticated" | "unauthenticated">("checking");
  const publicPaths = useMemo(() => new Set(["/", "/login"]), []);
  const isPublicRoute = publicPaths.has(pathname);

  useEffect(() => {
    let active = true;
    const supabase = getSupabaseBrowserClient();

    async function resolveAuth() {
      const { data } = await supabase.auth.getUser();
      if (!active) return;

      const nextState = data.user ? "authenticated" : "unauthenticated";
      setAuthState(nextState);

      if (!data.user && !isPublicRoute) {
        router.replace("/login");
      }
    }

    resolveAuth();

    const {
      data: { subscription }
    } = supabase.auth.onAuthStateChange((_event, session) => {
      if (!active) return;

      const nextState = session?.user ? "authenticated" : "unauthenticated";
      setAuthState(nextState);

      if (!session?.user && !isPublicRoute) {
        router.replace("/login");
      }
    });

    return () => {
      active = false;
      subscription.unsubscribe();
    };
  }, [isPublicRoute, router]);

  if (isPublicRoute) {
    return (
      <div className="app-shell auth-shell">
        <main>{children}</main>
      </div>
    );
  }

  if (authState !== "authenticated") {
    return (
      <div className="app-shell auth-shell">
        <main>
          <section className="card col narrow">
            <h1>Verificando acesso</h1>
            <p>Estamos confirmando sua sessão para abrir a agenda.</p>
          </section>
        </main>
      </div>
    );
  }

  return (
    <div className="app-shell">
      <Navbar />
      <main>{children}</main>
    </div>
  );
}
