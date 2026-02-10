import "./globals.css";
import type { Metadata } from "next";
import { Inter } from "next/font/google";
import { Navbar } from "@/components/navbar";

const inter = Inter({
  subsets: ["latin"],
  variable: "--font-inter",
  weight: ["400", "500", "600"],
  display: "swap"
});

export const metadata: Metadata = {
  title: "Agenda Profissional",
  description: "Painel web do MVP de agendamentos",
  icons: {
    icon: "/brand/agenda-logo.png",
    apple: "/brand/agenda-logo.png"
  }
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="pt-BR" suppressHydrationWarning>
      <body className={inter.variable} suppressHydrationWarning>
        <header className="top-header">
          <div className="top-header-inner">Agenda Profissional</div>
        </header>
        <div className="app-shell">
          <Navbar />
          <main>{children}</main>
        </div>
      </body>
    </html>
  );
}
