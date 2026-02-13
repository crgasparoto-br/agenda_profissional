"use client";

import { FormEvent, useState } from "react";
import Image from "next/image";
import { useRouter } from "next/navigation";
import { getSupabaseBrowserClient } from "@/lib/supabase-browser";
import { parseAccessPath } from "@/lib/access-path";
import { Button } from "@/components/ui/button";

export default function LoginPage() {
  const [mode, setMode] = useState<"signin" | "signup">("signin");
  const [fullName, setFullName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [showConfirmPassword, setShowConfirmPassword] = useState(false);
  const [status, setStatus] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const router = useRouter();
  const invalidCredentialsRegex = /invalid login credentials/i;
  const alreadyRegisteredRegex = /user already registered|already exists|user_already_exists/i;

  function getFriendlyAuthError(message: string) {
    if (invalidCredentialsRegex.test(message)) {
      return "Email ou senha invalido.";
    }
    if (alreadyRegisteredRegex.test(message)) {
      return "Este e-mail já está cadastrado. Tente entrar ou recuperar sua senha.";
    }
    return message;
  }

  async function handleForgotPassword() {
    setError(null);
    setStatus(null);

    if (!email) {
      setError("Informe o email para recuperar a senha.");
      return;
    }

    try {
      const supabase = getSupabaseBrowserClient();
      const { error: resetError } = await supabase.auth.resetPasswordForEmail(email, {
        redirectTo: `${window.location.origin}/login`
      });

      if (resetError) {
        setError(getFriendlyAuthError(resetError.message));
        return;
      }

      setStatus("Enviamos um link para redefinir sua senha.");
    } catch {
      setError("Não foi possível enviar a recuperação de senha.");
    }
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setLoading(true);
    setError(null);
    setStatus(null);
    try {
      const supabase = getSupabaseBrowserClient();

      if (mode === "signup") {
        if (password.length < 6) {
          setError("A senha deve ter pelo menos 6 caracteres.");
          return;
        }

        if (password !== confirmPassword) {
          setError("As senhas não conferem.");
          return;
        }

        const { data, error: signUpError } = await supabase.auth.signUp({
          email,
          password,
          options: {
            data: {
              access_path: "professional",
              full_name: fullName || null
            }
          }
        });

        if (signUpError) {
          const isAlreadyRegistered = alreadyRegisteredRegex.test(signUpError.message);
          if (isAlreadyRegistered) {
            const { data: signInData, error: signInError } = await supabase.auth.signInWithPassword({
              email,
              password
            });

            if (signInError) {
              setError("Este e-mail já está cadastrado, mas a senha informada não confere.");
              return;
            }

            const path = parseAccessPath(signInData.user?.user_metadata?.access_path);
            router.push(path === "client" ? "/client-area" : "/onboarding");
            return;
          }

          setError(getFriendlyAuthError(signUpError.message));
          return;
        }

        if (!data.session) {
          setStatus("Conta criada. Verifique seu email para confirmar o acesso.");
          return;
        }

        router.push("/onboarding");
        return;
      }

      const { data, error: signInError } = await supabase.auth.signInWithPassword({ email, password });

      if (signInError) {
        setError(getFriendlyAuthError(signInError.message));
        return;
      }

      const path = parseAccessPath(data.user?.user_metadata?.access_path);
      router.push(path === "client" ? "/client-area" : "/onboarding");
    } catch (err) {
      const message = err instanceof Error ? err.message : "";
      const isNetworkError =
        err instanceof TypeError ||
        /failed to fetch|networkerror|network request failed/i.test(message);

      if (isNetworkError) {
        setError("Não foi possível conectar ao servidor de autenticação.");
        return;
      }

      setError(getFriendlyAuthError(message || "Erro inesperado ao autenticar."));
    } finally {
      setLoading(false);
    }
  }

  return (
    <section className="card col narrow">
      <Image src="/brand/agenda-logo.png" alt="Logo Agenda Profissional" width={72} height={72} priority />
      <h1>{mode === "signin" ? "Login" : "Criar conta"}</h1>

      <div className="row">
        <Button
          type="button"
          variant={mode === "signin" ? "default" : "outline"}
          onClick={() => setMode("signin")}
        >
          Entrar
        </Button>
        <Button
          type="button"
          variant={mode === "signup" ? "default" : "outline"}
          onClick={() => setMode("signup")}
        >
          Criar usuário
        </Button>
      </div>

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
          <div className="password-field">
            <input
              className="password-input"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              type={showPassword ? "text" : "password"}
              minLength={6}
              required
            />
            <button
              type="button"
              className="password-toggle"
              onClick={() => setShowPassword((current) => !current)}
              aria-label={showPassword ? "Ocultar senha" : "Mostrar senha"}
              aria-pressed={showPassword}
            >
              <svg viewBox="0 0 24 24" aria-hidden="true">
                <path
                  d={
                    showPassword
                      ? "M4 4L20 20M10.6 10.6A2 2 0 0013.4 13.4M9.9 5.2A11.2 11.2 0 0112 5c4.7 0 8.6 2.9 10 7-0.5 1.4-1.3 2.7-2.3 3.7M6.1 6.1A11.3 11.3 0 002 12c1.4 4.1 5.3 7 10 7 1.4 0 2.8-0.3 4-0.8"
                      : "M2 12s3.8-7 10-7 10 7 10 7-3.8 7-10 7S2 12 2 12zm10 3a3 3 0 100-6 3 3 0 000 6z"
                  }
                />
              </svg>
            </button>
          </div>
        </label>

        {mode === "signup" ? (
          <label className="col">
            Confirmar senha
            <div className="password-field">
              <input
                className="password-input"
                value={confirmPassword}
                onChange={(e) => setConfirmPassword(e.target.value)}
                type={showConfirmPassword ? "text" : "password"}
                minLength={6}
                required
              />
              <button
                type="button"
                className="password-toggle"
                onClick={() => setShowConfirmPassword((current) => !current)}
                aria-label={showConfirmPassword ? "Ocultar senha" : "Mostrar senha"}
                aria-pressed={showConfirmPassword}
              >
                <svg viewBox="0 0 24 24" aria-hidden="true">
                  <path
                    d={
                      showConfirmPassword
                        ? "M4 4L20 20M10.6 10.6A2 2 0 0013.4 13.4M9.9 5.2A11.2 11.2 0 0112 5c4.7 0 8.6 2.9 10 7-0.5 1.4-1.3 2.7-2.3 3.7M6.1 6.1A11.3 11.3 0 002 12c1.4 4.1 5.3 7 10 7 1.4 0 2.8-0.3 4-0.8"
                        : "M2 12s3.8-7 10-7 10 7 10 7-3.8 7-10 7S2 12 2 12zm10 3a3 3 0 100-6 3 3 0 000 6z"
                    }
                  />
                </svg>
              </button>
            </div>
          </label>
        ) : null}

        {status ? <div className="notice">{status}</div> : null}
        {error ? <div className="error">{error}</div> : null}

        <Button type="submit" disabled={loading}>
          {loading
            ? mode === "signin"
              ? "Entrando..."
              : "Criando..."
            : mode === "signin"
              ? "Entrar"
              : "Criar conta"}
        </Button>
        {mode === "signin" ? (
          <Button type="button" variant="outline" onClick={handleForgotPassword} disabled={loading}>
            Esqueci minha senha
          </Button>
        ) : null}
      </form>

      <p className="text-muted">Acesso exclusivo para profissionais e equipes de empresas.</p>
    </section>
  );
}

