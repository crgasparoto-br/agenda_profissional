export type AccessPath = "professional" | "client";

export function parseAccessPath(raw: unknown): AccessPath {
  return raw === "client" ? "client" : "professional";
}
