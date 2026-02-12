"use client";

import { usePathname } from "next/navigation";
import { Navbar } from "@/components/navbar";

export function AppShell({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const hideMenu = pathname === "/login";

  if (hideMenu) {
    return (
      <div className="app-shell auth-shell">
        <main>{children}</main>
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

