// deno test supabase/functions/ai-proxy/
import { type Deps, makeHandler } from "./handler.ts";

function eq(actual: unknown, expected: unknown, msg = "") {
  const a = JSON.stringify(actual), e = JSON.stringify(expected);
  if (a !== e) throw new Error(`${msg}\n  esperado: ${e}\n  obtenido: ${a}`);
}

/// Gemini falso: responde los textos en orden; registra lo que recibió.
function fake(opts: { used?: number; user?: string | null; answers?: (string | "timeout" | "502")[] } = {}) {
  const calls = { gemini: [] as { body: any; headers: Record<string, string>; url: string }[], recorded: 0 };
  const answers = [...(opts.answers ?? ["Te quedan S/ 850.00."])];
  const deps: Deps = {
    userId: () => Promise.resolve(opts.user === undefined ? "u1" : opts.user),
    usedToday: () => Promise.resolve(opts.used ?? 0),
    recordUse: () => Promise.resolve((opts.used ?? 0) + ++calls.recorded),
    gemini: (url, init) => {
      calls.gemini.push({ url, body: JSON.parse(init.body as string), headers: init.headers as Record<string, string> });
      const a = answers.shift() ?? "";
      if (a === "timeout") {
        return new Promise((_, reject) => init.signal!.addEventListener("abort", () => reject(new DOMException("x", "AbortError"))));
      }
      if (a === "502") return Promise.resolve(new Response("{}", { status: 503 }));
      return Promise.resolve(Response.json({ candidates: [{ content: { parts: [{ text: a }] } }] }));
    },
    apiKey: "CLAVE-DE-PRUEBA",
    model: "gemini-2.5-flash-lite",
    limit: 10,
    timeoutMs: 50,
  };
  return { deps, calls };
}

const facts = { balanceCents: 85000, days: 17 };
const body = (extra: Record<string, unknown> = {}) =>
  JSON.stringify({ question: "cut", facts, consentVersion: 1, ...extra });
const post = (b: string, auth = "Bearer jwt") =>
  new Request("http://x/ai-proxy", { method: "POST", headers: { Authorization: auth }, body: b });

Deno.test("solo POST", async () => {
  const { deps } = fake();
  eq((await makeHandler(deps)(new Request("http://x/ai-proxy"))).status, 405);
});

Deno.test("sin sesión: 401 y no llama a Gemini", async () => {
  const { deps, calls } = fake({ user: null });
  eq((await makeHandler(deps)(post(body()))).status, 401);
  eq((await makeHandler(deps)(post(body(), ""))).status, 401);
  eq(calls.gemini.length, 0);
});

Deno.test("cuerpo inválido: 400 con el motivo", async () => {
  const { deps, calls } = fake();
  const r = await makeHandler(deps)(post(body({ question: "chat_libre" })));
  eq([r.status, await r.json()], [400, { error: "bad_request", detail: "question" }]);
  eq((await makeHandler(deps)(post("no es json"))).status, 400);
  eq(calls.gemini.length, 0);
});

Deno.test("con 10 usadas: 429 sin llamar a Gemini", async () => {
  const { deps, calls } = fake({ used: 10 });
  const r = await makeHandler(deps)(post(body()));
  eq([r.status, await r.json()], [429, { error: "limit", left: 0 }]);
  eq(calls.gemini.length, 0);
});

Deno.test("respuesta válida: solo {text, left}; registra 1 uso; clave en el encabezado", async () => {
  const { deps, calls } = fake({ used: 3 });
  const r = await makeHandler(deps)(post(body()));
  eq([r.status, await r.json()], [200, { text: "Te quedan S/ 850.00.", left: 6 }]);
  eq(calls.recorded, 1);
  eq(calls.gemini[0].url.includes("CLAVE"), false, "la clave no va en la URL");
  eq(calls.gemini[0].headers["x-goog-api-key"], "CLAVE-DE-PRUEBA");
  eq(calls.gemini[0].url, "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent");
});

Deno.test("el prompt usa la plantilla y los montos ya escritos como S/; el item va como dato", async () => {
  const { deps, calls } = fake({ answers: ["Con S/ 120.00 te quedan S/ 850.00."] });
  await makeHandler(deps)(post(body({ question: "can_spend", input: { amountCents: 12000, item: "zapa<tillas>" } })));
  const text = calls.gemini[0].body.contents[0].parts[0].text as string;
  eq(text.includes("¿Puedo gastar S/ 120.00 en <item>zapatillas</item>"), true, text);
  eq(text.includes('"balanceCents": "S/ 850.00"'), true, text);
  eq(calls.gemini[0].body.systemInstruction.parts[0].text.includes("SOLO los montos"), true);
  eq(calls.gemini[0].body.generationConfig, { temperature: 0.3, maxOutputTokens: 400 });
});

Deno.test("monto inventado: reintenta una vez; si se corrige, éxito con un solo registro", async () => {
  const { deps, calls } = fake({ answers: ["Ahorras S/ 123.00.", "Te quedan S/ 850.00."] });
  const r = await makeHandler(deps)(post(body()));
  eq([r.status, (await r.json()).text], [200, "Te quedan S/ 850.00."]);
  eq(calls.gemini.length, 2);
  eq(calls.gemini[1].body.contents[0].parts[0].text.includes("Usa SOLO estos montos: S/ 850.00."), true);
  eq(calls.recorded, 1);
});

Deno.test("inventa dos veces: 422 y no cuenta (I3)", async () => {
  const { deps, calls } = fake({ answers: ["S/ 1.00", "S/ 2.00"] });
  const r = await makeHandler(deps)(post(body()));
  eq([r.status, await r.json()], [422, { error: "unverified" }]);
  eq(calls.recorded, 0);
});

Deno.test("Gemini tarda: 504 y no cuenta; Gemini falla: 502 y no cuenta", async () => {
  const slow = fake({ answers: ["timeout"] });
  eq((await makeHandler(slow.deps)(post(body()))).status, 504);
  eq(slow.calls.recorded, 0);
  const down = fake({ answers: ["502"] });
  eq((await makeHandler(down.deps)(post(body()))).status, 502);
  eq(down.calls.recorded, 0);
});

Deno.test("los logs nunca llevan hechos, pregunta ni respuesta", async () => {
  const logged: string[] = [];
  const orig = { log: console.log, error: console.error, warn: console.warn, info: console.info };
  const spy = (...a: unknown[]) => logged.push(a.map(String).join(" "));
  Object.assign(console, { log: spy, error: spy, warn: spy, info: spy });
  try {
    for (const answers of [["Te quedan S/ 850.00."], ["S/ 9.00", "S/ 9.00"], ["timeout"], ["502"]]) {
      const { deps } = fake({ answers });
      await makeHandler(deps)(post(body({ question: "can_spend", input: { amountCents: 12000, item: "zapatillas" } })));
    }
  } finally {
    Object.assign(console, orig);
  }
  const all = logged.join("\n");
  for (const secret of ["850", "zapatillas", "balanceCents", "Te quedan", "CLAVE"]) {
    eq(all.includes(secret), false, `"${secret}" apareció en un log:\n${all}`);
  }
});
