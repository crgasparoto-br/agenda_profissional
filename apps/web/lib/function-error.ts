type FunctionInvokeError = {
  message?: string;
  context?: Response | string;
};

function toFriendlyMessage(raw: string) {
  const value = raw.trim();
  const lowered = value.toLowerCase();

  if (lowered.includes("professional is unavailable in this time range")) {
    return "Horario indisponivel.";
  }
  if (lowered.includes("horario indisponivel")) {
    return "Horario indisponivel.";
  }
  if (lowered.includes("no available professional")) {
    return "Nao ha profissional disponivel para esse horario.";
  }
  if (lowered.includes("time conflict for professional")) {
    return "Ja existe um agendamento para esse profissional no horario informado.";
  }

  return value;
}

export async function getFunctionErrorMessage(error: unknown, fallback: string) {
  const fnError = (error ?? {}) as FunctionInvokeError;
  const context = fnError.context;

  if (context instanceof Response) {
    const payload = await context
      .clone()
      .json()
      .catch(() => null) as { error?: string; message?: string } | null;
    const extracted = payload?.error || payload?.message;
    if (extracted) return toFriendlyMessage(extracted);
  }

  if (typeof context === "string") {
    try {
      const parsed = JSON.parse(context) as { error?: string; message?: string };
      const extracted = parsed.error || parsed.message;
      if (extracted) return toFriendlyMessage(extracted);
    } catch {
      // noop
    }
  }

  if (fnError.message && fnError.message.trim()) {
    return toFriendlyMessage(fnError.message);
  }

  return fallback;
}
