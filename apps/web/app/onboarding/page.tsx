"use client";

import { FormEvent, useEffect, useMemo, useState } from "react";
import Image from "next/image";
import { useRouter } from "next/navigation";
import { BootstrapTenantInputSchema } from "@agenda-profissional/shared";
import { getSupabaseBrowserClient } from "@/lib/supabase-browser";
import { parseAccessPath } from "@/lib/access-path";
import { getFunctionErrorMessage } from "@/lib/function-error";
import { formatPhone, normalizePhone } from "@/lib/phone";

type ProfileRow = {
  id: string;
  tenant_id: string;
  full_name: string;
  phone: string | null;
} | null;

type TenantRow = {
  id: string;
  type: "individual" | "group";
  name: string;
  logo_url: string | null;
} | null;

type ServiceLocationRow = {
  id: string;
  name: string;
  address_line: string;
  city: string;
  state: string;
  postal_code: string | null;
  country: string;
  latitude: number | null;
  longitude: number | null;
  is_active: boolean;
};

type ServiceLocationDraft = {
  id: string | null;
  name: string;
  addressLine: string;
  city: string;
  state: string;
  postalCode: string;
  country: string;
  latitude: string;
  longitude: string;
  isActive: boolean;
};

const MAX_LOGO_SIZE_BYTES = 5 * 1024 * 1024;
const ALLOWED_LOGO_TYPES = new Set(["image/png", "image/jpeg", "image/webp", "image/svg+xml"]);

function createDefaultServiceLocationDraft(): ServiceLocationDraft {
  return {
    id: null,
    name: "Endereço principal",
    addressLine: "",
    city: "",
    state: "",
    postalCode: "",
    country: "BR",
    latitude: "",
    longitude: "",
    isActive: true
  };
}

export default function OnboardingPage() {
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL ?? "";
  const router = useRouter();
  const [tenantType, setTenantType] = useState<"individual" | "group">("individual");
  const [tenantName, setTenantName] = useState("");
  const [fullName, setFullName] = useState("");
  const [phone, setPhone] = useState("");
  const [tenantId, setTenantId] = useState<string | null>(null);
  const [userId, setUserId] = useState<string | null>(null);
  const [isInitialized, setIsInitialized] = useState(false);
  const [loading, setLoading] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [logoUrl, setLogoUrl] = useState<string | null>(null);
  const [logoFile, setLogoFile] = useState<File | null>(null);
  const [tenantServiceLocationDraft, setTenantServiceLocationDraft] = useState<ServiceLocationDraft>(
    createDefaultServiceLocationDraft()
  );
  const [status, setStatus] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const logoPreviewUrl = useMemo(() => {
    if (!logoFile) return null;
    return URL.createObjectURL(logoFile);
  }, [logoFile]);

  useEffect(() => {
    return () => {
      if (logoPreviewUrl) URL.revokeObjectURL(logoPreviewUrl);
    };
  }, [logoPreviewUrl]);

  useEffect(() => {
    const supabase = getSupabaseBrowserClient();
    supabase.auth.getUser().then(async ({ data }) => {
      if (!data.user?.id) {
        router.push("/login");
        return;
      }

      setUserId(data.user.id);

      const path = parseAccessPath(data.user.user_metadata?.access_path);
      if (path === "client") {
        router.push("/client-area");
        return;
      }

      const { data: profileData } = await supabase
        .from("profiles")
        .select("id, tenant_id, full_name, phone")
        .eq("id", data.user.id)
        .maybeSingle();

      const typedProfile = profileData as ProfileRow;
      if (!typedProfile?.tenant_id) {
        setLoading(false);
        return;
      }

      setTenantId(typedProfile.tenant_id);
      setFullName(typedProfile.full_name ?? "");
      setPhone(formatPhone(typedProfile.phone ?? ""));

      const { data: tenantData } = await supabase
        .from("tenants")
        .select("id, type, name, logo_url")
        .eq("id", typedProfile.tenant_id)
        .maybeSingle();

      const typedTenant = tenantData as TenantRow;
      if (typedTenant) {
        setTenantType(typedTenant.type);
        setTenantName(typedTenant.name);
        setLogoUrl(typedTenant.logo_url);
        if (typedTenant.type === "individual" && !typedProfile.full_name) {
          setFullName(typedTenant.name);
        }
        setIsInitialized(true);
      }

      const serviceLocationsTable = (supabase as any).from("service_locations");
      const { data: locationData } = await serviceLocationsTable
        .select("id, name, address_line, city, state, postal_code, country, latitude, longitude, is_active")
        .eq("tenant_id", typedProfile.tenant_id)
        .is("professional_id", null)
        .order("updated_at", { ascending: false })
        .limit(1)
        .maybeSingle();
      const typedLocation = (locationData ?? null) as ServiceLocationRow | null;
      setTenantServiceLocationDraft(
        typedLocation
          ? {
              id: typedLocation.id,
              name: typedLocation.name,
              addressLine: typedLocation.address_line,
              city: typedLocation.city,
              state: typedLocation.state,
              postalCode: typedLocation.postal_code ?? "",
              country: typedLocation.country,
              latitude: typedLocation.latitude?.toString() ?? "",
              longitude: typedLocation.longitude?.toString() ?? "",
              isActive: typedLocation.is_active
            }
          : createDefaultServiceLocationDraft()
      );

      setLoading(false);
    });
  }, [router]);

  function updateTenantServiceLocationDraft(patch: Partial<ServiceLocationDraft>) {
    setTenantServiceLocationDraft((prev) => ({
      ...prev,
      ...patch
    }));
  }

  function parseTenantServiceLocationDraft(): {
    payload: Record<string, unknown> | null;
    error: string | null;
  } {
    const draft = tenantServiceLocationDraft;
    const hasAnyData = Boolean(
      draft.name.trim() ||
        draft.addressLine.trim() ||
        draft.city.trim() ||
        draft.state.trim() ||
        draft.postalCode.trim() ||
        draft.country.trim() ||
        draft.latitude.trim() ||
        draft.longitude.trim()
    );
    if (!hasAnyData) {
      return { payload: null, error: null };
    }

    if (!draft.name.trim()) return { payload: null, error: "Endereço da empresa: informe o nome do local." };
    if (!draft.addressLine.trim()) return { payload: null, error: "Endereço da empresa: informe o endereço." };
    if (!draft.city.trim()) return { payload: null, error: "Endereço da empresa: informe a cidade." };
    if (!draft.state.trim()) return { payload: null, error: "Endereço da empresa: informe o estado." };
    if (!draft.country.trim()) return { payload: null, error: "Endereço da empresa: informe o país." };

    let lat: number | null = null;
    let lng: number | null = null;
    if (draft.latitude.trim() || draft.longitude.trim()) {
      lat = Number(draft.latitude);
      lng = Number(draft.longitude);
      if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
        return { payload: null, error: "Endereço da empresa: latitude/longitude inválidas." };
      }
      if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
        return { payload: null, error: "Endereço da empresa: latitude/longitude fora de faixa." };
      }
    }

    return {
      payload: {
        name: draft.name.trim(),
        address_line: draft.addressLine.trim(),
        city: draft.city.trim(),
        state: draft.state.trim(),
        postal_code: draft.postalCode.trim() || null,
        country: draft.country.trim().toUpperCase(),
        latitude: lat,
        longitude: lng,
        is_active: draft.isActive
      },
      error: null
    };
  }

  async function saveTenantServiceLocation(targetTenantId: string): Promise<boolean> {
    const parsed = parseTenantServiceLocationDraft();
    if (parsed.error) {
      setError(parsed.error);
      return false;
    }
    if (!parsed.payload) return true;

    const supabase = getSupabaseBrowserClient();
    const table = (supabase as any).from("service_locations");
    const payload = {
      tenant_id: targetTenantId,
      professional_id: null,
      ...parsed.payload
    };
    const mutation = tenantServiceLocationDraft.id
      ? table.update(payload).eq("id", tenantServiceLocationDraft.id).is("professional_id", null)
      : table.insert(payload);
    const { error: saveError } = await mutation;
    if (saveError) {
      setError(saveError.message);
      return false;
    }
    return true;
  }

  async function uploadLogoForTenant(targetTenantId: string, file: File): Promise<string> {
    if (!ALLOWED_LOGO_TYPES.has(file.type)) {
      throw new Error("Formato de logo invalido. Use PNG, JPG, WEBP ou SVG.");
    }
    if (file.size > MAX_LOGO_SIZE_BYTES) {
      throw new Error("Logo muito grande. Limite de 5MB.");
    }

    const extFromMime: Record<string, string> = {
      "image/png": "png",
      "image/jpeg": "jpg",
      "image/webp": "webp",
      "image/svg+xml": "svg"
    };
    const ext = extFromMime[file.type] ?? "png";
    const objectPath = `${targetTenantId}/logo.${ext}`;

    const supabase = getSupabaseBrowserClient();
    const { error: uploadError } = await supabase.storage.from("tenant-assets").upload(objectPath, file, {
      upsert: true,
      cacheControl: "3600",
      contentType: file.type
    });

    if (uploadError) {
      throw new Error(uploadError.message);
    }

    const { data } = supabase.storage.from("tenant-assets").getPublicUrl(objectPath);
    return `${data.publicUrl}?v=${Date.now()}`;
  }

  async function handleSubmit(event: FormEvent) {
    event.preventDefault();
    if (submitting) return;
    setError(null);
    setStatus(null);
    setSubmitting(true);

    try {
      const resolvedFullName = tenantType === "individual" ? tenantName.trim() : fullName.trim();

      if (isInitialized && tenantId && userId) {
        if (tenantName.trim().length < 2) {
          setError("Nome profissional ou da empresa invalido.");
          return;
        }
        if (resolvedFullName.length < 2) {
          setError("Nome completo invalido.");
          return;
        }

        const supabase = getSupabaseBrowserClient();
        let nextLogoUrl = logoUrl;
        if (logoFile) {
          nextLogoUrl = await uploadLogoForTenant(tenantId, logoFile);
        }

        const tenantsTable = (supabase as any).from("tenants");
        const { error: tenantUpdateError } = await tenantsTable
          .update({
            type: tenantType,
            name: tenantName.trim(),
            logo_url: nextLogoUrl
          })
          .eq("id", tenantId);

        if (tenantUpdateError) {
          setError(tenantUpdateError.message);
          return;
        }

        const { error: profileUpdateError } = await supabase
          .from("profiles")
          .update({
            full_name: resolvedFullName,
            phone: normalizePhone(phone) || null
          })
          .eq("id", userId);

        if (profileUpdateError) {
          setError(profileUpdateError.message);
          return;
        }
        const locationSaved = await saveTenantServiceLocation(tenantId);
        if (!locationSaved) {
          return;
        }

        setLogoUrl(nextLogoUrl);
        setLogoFile(null);
        setStatus("configuração atualizada com sucesso.");
        return;
      }

      const parsed = BootstrapTenantInputSchema.safeParse({
        tenant_type: tenantType,
        tenant_name: tenantName,
        full_name: resolvedFullName,
        phone: normalizePhone(phone)
      });

      if (!parsed.success) {
        setError("Dados invalidos.");
        return;
      }

      const supabase = getSupabaseBrowserClient();
      const { data, error: fnError } = await supabase.functions.invoke("bootstrap-tenant", {
        body: parsed.data
      });

      if (fnError) {
        const baseError = await getFunctionErrorMessage(fnError, "Não foi possível concluir a configuração inicial.");
        const networkEdgeError =
          typeof fnError.message === "string" &&
          /failed to send a request to the edge function/i.test(fnError.message);

        if (networkEdgeError) {
          setError(`${baseError} URL atual do Supabase: ${supabaseUrl || "Não definida"}.`);
          return;
        }

        setError(baseError);
        return;
      }

      const createdTenantId = (data as { tenant_id?: string } | null)?.tenant_id ?? null;
      if (createdTenantId && logoFile) {
        try {
          const createdLogoUrl = await uploadLogoForTenant(createdTenantId, logoFile);
          const tenantsTable = (supabase as any).from("tenants");
          await tenantsTable.update({ logo_url: createdLogoUrl }).eq("id", createdTenantId);
        } catch (logoError) {
          const message = logoError instanceof Error ? logoError.message : "Falha ao enviar logo.";
          setStatus(`organização inicializada: ${createdTenantId}.`);
          setError(`configuração salva, mas o logo Não foi aplicado: ${message}`);
          router.push("/dashboard");
          return;
        }
      }

      if (createdTenantId) {
        const locationSaved = await saveTenantServiceLocation(createdTenantId);
        if (!locationSaved) {
          return;
        }
      }

      setStatus(`organização inicializada: ${createdTenantId ?? "ok"}`);
      router.push("/dashboard");
    } finally {
      setSubmitting(false);
    }
  }

  if (loading) {
    return (
      <section className="card col">
        <h1>configuração inicial</h1>
        <p>Carregando dados da organização...</p>
      </section>
    );
  }

  return (
    <section className="card col">
      <h1>configuração inicial</h1>
      <p>
        {isInitialized
          ? "Mantenha os dados da sua organização e identidade visual."
          : "Configure seu perfil para iniciar sua agenda profissional."}
      </p>
      <form className="col" onSubmit={handleSubmit}>
        <label className="col">
          Tipo de conta
          <select value={tenantType} onChange={(e) => setTenantType(e.target.value as "individual" | "group")}>
            <option value="individual">Individual (PF)</option>
            <option value="group">Equipe / Empresa (PJ)</option>
          </select>
        </label>

        <label className="col">
          Nome profissional ou da empresa
          <input
            value={tenantName}
            onChange={(e) => {
              const value = e.target.value;
              setTenantName(value);
              if (tenantType === "individual") {
                setFullName(value);
              }
            }}
            required
          />
        </label>

        {tenantType === "group" ? (
          <label className="col">
            Nome completo
            <input value={fullName} onChange={(e) => setFullName(e.target.value)} required />
          </label>
        ) : null}

        <label className="col">
          Telefone
          <input
            value={phone}
            onChange={(e) => setPhone(formatPhone(e.target.value))}
            inputMode="tel"
            placeholder="(11) 99999-9999"
          />
        </label>

        <div className="card col">
          <h2>Endereço padrão da empresa</h2>
          <div className="absence-grid">
            <label className="col">
              Nome do local
              <input
                value={tenantServiceLocationDraft.name}
                onChange={(e) => updateTenantServiceLocationDraft({ name: e.target.value })}
                placeholder="Ex.: Unidade Centro"
              />
            </label>
            <label className="col absence-reason">
              Endereço
              <input
                value={tenantServiceLocationDraft.addressLine}
                onChange={(e) => updateTenantServiceLocationDraft({ addressLine: e.target.value })}
                placeholder="Rua, número e complemento"
              />
            </label>
            <label className="col">
              Cidade
              <input
                value={tenantServiceLocationDraft.city}
                onChange={(e) => updateTenantServiceLocationDraft({ city: e.target.value })}
              />
            </label>
            <label className="col">
              Estado
              <input
                value={tenantServiceLocationDraft.state}
                onChange={(e) => updateTenantServiceLocationDraft({ state: e.target.value })}
              />
            </label>
            <label className="col">
              CEP
              <input
                value={tenantServiceLocationDraft.postalCode}
                onChange={(e) => updateTenantServiceLocationDraft({ postalCode: e.target.value })}
              />
            </label>
            <label className="col">
              País
              <input
                value={tenantServiceLocationDraft.country}
                onChange={(e) => updateTenantServiceLocationDraft({ country: e.target.value })}
              />
            </label>
            <label className="col">
              Latitude (opcional)
              <input
                value={tenantServiceLocationDraft.latitude}
                onChange={(e) => updateTenantServiceLocationDraft({ latitude: e.target.value })}
                placeholder="-23.56321"
              />
            </label>
            <label className="col">
              Longitude (opcional)
              <input
                value={tenantServiceLocationDraft.longitude}
                onChange={(e) => updateTenantServiceLocationDraft({ longitude: e.target.value })}
                placeholder="-46.65425"
              />
            </label>
          </div>
          <label className="checkbox-row">
            <input
              type="checkbox"
              checked={tenantServiceLocationDraft.isActive}
              onChange={(e) => updateTenantServiceLocationDraft({ isActive: e.target.checked })}
            />
            Endereço ativo
          </label>
          <small className="text-muted">
            Este endereço é usado como fallback quando o profissional não tem endereço próprio.
          </small>
        </div>

        <label className="col">
          Logotipo da organização
          <input
            type="file"
            accept="image/png,image/jpeg,image/webp,image/svg+xml"
            onChange={(e) => setLogoFile(e.target.files?.[0] ?? null)}
          />
          <small className="text-muted">Formatos: PNG, JPG, WEBP, SVG. Limite: 5MB.</small>
        </label>

        <div className="row align-center">
          <Image
            src={logoPreviewUrl ?? logoUrl ?? "/brand/agenda-logo.png"}
            alt="Previa do logotipo"
            width={56}
            height={56}
            className="nav-logo"
            unoptimized
          />
          <small className="text-muted">
            {logoFile
              ? "Nova logo selecionada. Salve para aplicar."
              : logoUrl
                ? "Logo atual da organização."
                : "Sem logo customizada. Sera usado o padrao."}
          </small>
        </div>

        {status ? <div className="notice">{status}</div> : null}
        {error ? <div className="error">{error}</div> : null}

        <button type="submit" disabled={submitting}>
          {submitting ? "Salvando..." : isInitialized ? "Salvar configuracoes" : "Concluir configuração"}
        </button>
      </form>
    </section>
  );
}

