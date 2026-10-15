// Flujo de ai-proxy con las dependencias inyectadas (tests sin red; index.ts las cablea).
import { buildPrompt, retryNote, SYSTEM } from "./prompts.ts";
import { allowedCents, type Body, checkBody, validateAmounts } from "./validate.ts";

export interface Deps {
  /** Id del usuario del JWT, o null si la sesión no sirve. */
  userId(auth: string): Promise<string | null>;
  /** Consultas de hoy (día de Lima). */
  usedToday(auth: string): Promise<number>;
  /** Suma 1 y devuelve el total de hoy. Solo tras una respuesta válida (I3). */
  recordUse(auth: string): Promise<number>;
  gemini(url: string, init: RequestInit): Promise<Response>;
  apiKey: string;
  model: string;
  limit: number;
  timeoutMs: number;
}

const json = (status: number, body: unknown) => Response.json(body, { status });

class UpstreamError extends Error {}

/** Nunca se loguea el cuerpo, los hechos ni la respuesta: solo un código. */
const log = (code: string) => console.error(`ai-proxy: ${code}`);

export function makeHandler(deps: Deps): (req: Request) => Promise<Response> {
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${deps.model}:generateContent`;

  async function ask(prompt: string, signal: AbortSignal): Promise<string> {
    const res = await deps.gemini(url, {
      method: "POST",
      // La clave va en el encabezado: en la URL quedaría en logs intermedios.
      headers: { "content-type": "application/json", "x-goog-api-key": deps.apiKey },
      body: JSON.stringify({
        systemInstruction: { parts: [{ text: SYSTEM }] },
        contents: [{ role: "user", parts: [{ text: prompt }] }],
        generationConfig: { temperature: 0.3, maxOutputTokens: 400 },
      }),
      signal,
    });
    if (!res.ok) throw new UpstreamError();
    const data = await res.json();
    const text = (data?.candidates?.[0]?.content?.parts ?? []).map((p: { text?: string }) => p.text ?? "").join("").trim();
    if (!text) throw new UpstreamError();
    return text;
  }

  return async (req) => {
    if (req.method !== "POST") return json(405, { error: "method" });
    if (!deps.apiKey) {
      log("config");
      return json(500, { error: "config" });
    }
    const auth = req.headers.get("Authorization") ?? "";
    if (!auth.startsWith("Bearer ") || !(await deps.userId(auth))) return json(401, { error: "session" });

    let body: Body;
    try {
      body = await req.json();
    } catch {
      return json(400, { error: "bad_request", detail: "body" });
    }
    const bad = checkBody(body);
    if (bad) return json(400, { error: "bad_request", detail: bad });

    // ponytail: leer y después sumar; dos consultas simultáneas pueden pasar el límite por 1.
    if ((await deps.usedToday(auth)) >= deps.limit) return json(429, { error: "limit", left: 0 });

    const allowed = allowedCents(body.facts, body.input);
    const prompt = buildPrompt(body.question, body.facts, body.input);
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), deps.timeoutMs);
    try {
      let text = await ask(prompt, controller.signal);
      if (!validateAmounts(text, allowed)) {
        text = await ask(prompt + retryNote(allowed), controller.signal);
        if (!validateAmounts(text, allowed)) {
          log("unverified");
          return json(422, { error: "unverified" });
        }
      }
      const used = await deps.recordUse(auth);
      return json(200, { text, left: Math.max(0, deps.limit - used) });
    } catch (_) {
      if (controller.signal.aborted) {
        log("gemini_timeout");
        return json(504, { error: "timeout" });
      }
      log("gemini_error");
      return json(502, { error: "upstream" });
    } finally {
      clearTimeout(timer);
    }
  };
}
