"use client";

import { FormEvent, useState } from "react";
import Image from "next/image";
import { useRouter } from "next/navigation";
import { getSupabaseBrowserClient } from "@/lib/supabase-browser";
import { AccessPath, parseAccessPath } from "@/lib/access-path";

export default function LoginPage() {
  const [mode, setMode] = useState<"signin" | "signup">("signin");
  const [accessPath, setAccessPath] = useState<AccessPath>("professional");
  const [fullName, setFullName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [status, setStatus] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const router = useRouter();

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setLoading(true);
    setError(null);
    setStatus(null);

    const supabase = getSupabaseBrowserClient();

    if (mode === "signup") {
      if (password.length < 6) {
        setLoading(false);
        setError("A senha deve ter pelo menos 6 caracteres.");
        return;
      }

      if (password !== confirmPassword) {
        setLoading(false);
        setError("As senhas não conferem.");
        return;
      }

      const { data, error: signUpError } = await supabase.auth.signUp({
        email,
        password,
        options: {
          data: {
            access_path: accessPath,
            full_name: fullName || null
          }
        }
      });

      setLoading(false);

      if (signUpError) {
        setError(signUpError.message);
        return;
      }

      if (!data.session) {
        setStatus("Conta criada. Verifique seu email para confirmar o acesso.");
        return;
      }

      router.push(accessPath === "client" ? "/client-area" : "/onboarding");
      return;
    }

    const { data, error: signInError } = await supabase.auth.signInWithPassword({ email, password });
    setLoading(false);

    if (signInError) {
      setError(signInError.message);
      return;
    }

    const path = parseAccessPath(data.user?.user_metadata?.access_path);
    router.push(path === "client" ? "/client-area" : "/onboarding");
  }

  return (
    <section className="card col narrow">
      <Image src="/brand/agenda-logo.png" alt="Logo Agenda Profissional" width={72} height={72} priority />
      <h1>{mode === "signin" ? "Login" : "Criar conta"}</h1>

      <div className="row">
        <button
          type="button"
          className={mode === "signin" ? "" : "secondary"}
          onClick={() => setMode("signin")}
        >
          Entrar
        </button>
        <button
          type="button"
          className={mode === "signup" ? "" : "secondary"}
          onClick={() => setMode("signup")}
        >
          Criar usuário
        </button>
      </div>

      <label className="col">
        Caminho de acesso
        <select value={accessPath} onChange={(e) => setAccessPath(parseAccessPath(e.target.value))}>
          <option value="professional">Profissional / Clínica</option>
          <option value="client">Cliente</option>
        </select>
      </label>

      <form className="col" onSubmit={handleSubmit}>
        {mode === "signup" ? (
          <label className="col">
            Nome completo
            <input value={fullName} onChange={(e) => setFullName(e.target.value)} required />
          </label>
        ) : null}

        <label className="col">
          Email
          <input value={email} onChange={(e) => setEmail(e.target.value)} type="email" required />
        </label>

        <label className="col">
          Senha
          <input
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            type="password"
            minLength={6}
            required
          />
        </label>

        {mode === "signup" ? (
          <label className="col">
            Confirmar senha
            <input
              value={confirmPassword}
              onChange={(e) => setConfirmPassword(e.target.value)}
              type="password"
              minLength={6}
              required
            />
          </label>
        ) : null}

        {status ? <div className="notice">{status}</div> : null}
        {error ? <div className="error">{error}</div> : null}

        <button type="submit" disabled={loading}>
          {loading
            ? mode === "signin"
              ? "Entrando..."
              : "Criando..."
            : mode === "signin"
              ? "Entrar"
              : "Criar conta"}
        </button>
      </form>

      <p className="text-muted">Escolha o caminho correto para direcionar o fluxo após autenticação.</p>
    </section>
  );
}
