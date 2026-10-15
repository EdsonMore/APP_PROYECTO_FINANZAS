// Validación pura de ai-proxy (fase 5C-Infra). Sin red ni Deno APIs: se prueba
// con `deno test supabase/functions/ai-proxy/`.

/** Versión del consentimiento vigente. La app manda la que el usuario aceptó (I5). */
export const CONSENT_VERSION = 1;

export const QUESTIONS = ["cut", "can_spend", "what_if", "break_even", "save", "pay_first"] as const;
export type Question = (typeof QUESTIONS)[number];

/** Preguntas que traen un monto escrito por el usuario. */
const WITH_AMOUNT: readonly Question[] = ["can_spend", "what_if"];

const MAX_FACTS_BYTES = 8192;
const MAX_ITEM = 40;
const MAX_AMOUNT_CENTS = 10_000_000_000;

export type Input = { amountCents?: number; item?: string };
export type Body = { question: Question; facts: Record<string, unknown>; input?: Input; consentVersion: number };

const isObject = (v: unknown): v is Record<string, unknown> => typeof v === "object" && v !== null && !Array.isArray(v);

/** null si el cuerpo sirve; si no, el motivo (va en `detail` del 400). */
export function checkBody(b: unknown): string | null {
  if (!isObject(b)) return "body";
  if (!QUESTIONS.includes(b.question as Question)) return "question";
  if (!isObject(b.facts) || JSON.stringify(b.facts).length > MAX_FACTS_BYTES) return "facts";
  if (b.consentVersion !== CONSENT_VERSION) return "consent";
  const input = (isObject(b.input) ? b.input : {}) as Input;
  if (WITH_AMOUNT.includes(b.question as Question)) {
    const a = input.amountCents;
    if (typeof a !== "number" || !Number.isInteger(a) || a <= 0 || a > MAX_AMOUNT_CENTS) return "amount";
  }
  if (input.item !== undefined && (typeof input.item !== "string" || input.item.length > MAX_ITEM)) return "item";
  return null;
}

/** "S/ 1,234.56" en céntimos. */
export function soles(cents: number): string {
  return "S/ " + (Math.abs(cents) / 100).toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

/** Montos "S/ …" de un texto, en céntimos (sin signo). Días y porcentajes no cuentan. */
export function amountsIn(text: string): number[] {
  return [...text.matchAll(/S\/\s?(\d[\d,]*(?:\.\d+)?)/g)].map((m) => Math.round(parseFloat(m[1].replaceAll(",", "")) * 100));
}

/** Los montos que el modelo puede usar: cada campo …Cents de los hechos (a cualquier profundidad) y el de la pregunta. */
export function allowedCents(facts: unknown, input?: Input): Set<number> {
  const out = new Set<number>();
  const walk = (v: unknown) => {
    if (Array.isArray(v)) return v.forEach(walk);
    if (!isObject(v)) return;
    for (const [k, x] of Object.entries(v)) {
      if (k.endsWith("Cents") && typeof x === "number") out.add(Math.abs(Math.round(x)));
      else walk(x);
    }
  };
  walk(facts);
  if (typeof input?.amountCents === "number") out.add(Math.abs(input.amountCents));
  return out;
}

/** Cada monto del texto tiene que estar entre los permitidos (±1 céntimo). */
export function validateAmounts(text: string, allowed: Set<number>): boolean {
  const ok = [...allowed];
  return amountsIn(text).every((a) => ok.some((b) => Math.abs(a - b) <= 1));
}

/** Copia de los hechos con cada …Cents escrito como "S/ …": el modelo no convierte céntimos. */
export function renderFacts(v: unknown): unknown {
  if (Array.isArray(v)) return v.map(renderFacts);
  if (!isObject(v)) return v;
  return Object.fromEntries(
    Object.entries(v).map(([k, x]) => [k, k.endsWith("Cents") && typeof x === "number" ? soles(x) : renderFacts(x)]),
  );
}
