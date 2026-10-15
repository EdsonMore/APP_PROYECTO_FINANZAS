// ai-proxy (fase 5C-Infra): la app nunca tiene la clave de Gemini. Esta función
// la lee de los secretos de Supabase, verifica la sesión, aplica el límite diario
// y valida que la respuesta no invente montos. Despliegue: docs/ia/configurar-ai-proxy.md
//
// Secretos: GEMINI_API_KEY (obligatorio), GEMINI_MODEL, AI_DAILY_LIMIT.
// SUPABASE_URL y SUPABASE_ANON_KEY los pone Supabase. No usa service_role: cada
// consulta a la base va con el JWT del propio usuario.
import { createClient } from "npm:@supabase/supabase-js@2";
import { makeHandler } from "./handler.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

const asUser = (auth: string) =>
  createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: auth } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

async function rpcInt(auth: string, fn: "ai_usage_today" | "ai_record_use"): Promise<number> {
  const { data, error } = await asUser(auth).rpc(fn);
  if (error) throw new Error(fn);
  return Number(data ?? 0);
}

Deno.serve(makeHandler({
  userId: async (auth) => {
    const { data, error } = await asUser(auth).auth.getUser(auth.slice("Bearer ".length));
    return error ? null : (data.user?.id ?? null);
  },
  usedToday: (auth) => rpcInt(auth, "ai_usage_today"),
  recordUse: (auth) => rpcInt(auth, "ai_record_use"),
  gemini: (url, init) => fetch(url, init),
  apiKey: Deno.env.get("GEMINI_API_KEY") ?? "",
  model: Deno.env.get("GEMINI_MODEL") ?? "gemini-2.5-flash-lite",
  limit: Number(Deno.env.get("AI_DAILY_LIMIT") ?? "10"),
  timeoutMs: 15_000,
}));
