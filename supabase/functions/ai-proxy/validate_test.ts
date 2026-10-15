// deno test supabase/functions/ai-proxy/
import { allowedCents, amountsIn, checkBody, renderFacts, validateAmounts } from "./validate.ts";

function eq(actual: unknown, expected: unknown, msg = "") {
  const a = JSON.stringify(actual), e = JSON.stringify(expected);
  if (a !== e) throw new Error(`${msg}\n  esperado: ${e}\n  obtenido: ${a}`);
}

Deno.test("amountsIn: lee S/ con miles y decimales; ignora % y días", () => {
  eq(amountsIn("Te quedan S/ 1,234.56 y vence S/ 45.00 en 3 días (+35%)."), [123456, 4500]);
  eq(amountsIn("S/45 sin espacio y S/ 7.5"), [4500, 750]);
  eq(amountsIn("−S/ 20.00 y -S/ 3.00"), [2000, 300], "el signo no importa");
});

Deno.test("allowedCents: todos los campos …Cents, anidados en listas, más el monto de la pregunta", () => {
  const facts = { balanceCents: 85000, pending: [{ amountCents: 4500 }, { amountCents: -2000 }], days: 17 };
  eq([...allowedCents(facts, { amountCents: 12000 })].sort((a, b) => a - b), [2000, 4500, 12000, 85000]);
});

Deno.test("validateAmounts: permitidos pasan; uno inventado falla; ±1 céntimo se tolera", () => {
  const ok = new Set([4500, 85000]);
  eq(validateAmounts("Pagas S/ 45.00 y te quedan S/ 850.00.", ok), true);
  eq(validateAmounts("Pagas S/ 46.00.", ok), false);
  eq(validateAmounts("Pagas S/ 45.01.", ok), true);
  eq(validateAmounts("Sin montos, solo 3 días.", ok), true);
});

Deno.test("renderFacts: los …Cents se escriben como S/ para el modelo", () => {
  eq(renderFacts({ balanceCents: 123456, pending: [{ amountCents: 4500, name: "Internet" }], days: 17 }), {
    balanceCents: "S/ 1,234.56",
    pending: [{ amountCents: "S/ 45.00", name: "Internet" }],
    days: 17,
  });
});

Deno.test("checkBody: lo válido pasa", () => {
  eq(checkBody({ question: "cut", facts: { a: 1 }, consentVersion: 1 }), null);
  eq(checkBody({ question: "can_spend", facts: {}, input: { amountCents: 4500, item: "zapatillas" }, consentVersion: 1 }), null);
});

Deno.test("checkBody: rechaza pregunta desconocida, hechos grandes, item largo, monto faltante y consentimiento viejo", () => {
  eq(checkBody({ question: "otra", facts: {}, consentVersion: 1 }), "question");
  eq(checkBody({ question: "cut", facts: { x: "a".repeat(9000) }, consentVersion: 1 }), "facts");
  eq(checkBody({ question: "cut", facts: [], consentVersion: 1 }), "facts");
  eq(checkBody({ question: "can_spend", facts: {}, input: { amountCents: 4500, item: "a".repeat(41) }, consentVersion: 1 }), "item");
  eq(checkBody({ question: "can_spend", facts: {}, input: { item: "x" }, consentVersion: 1 }), "amount");
  eq(checkBody({ question: "what_if", facts: {}, input: { amountCents: -5 }, consentVersion: 1 }), "amount");
  eq(checkBody({ question: "cut", facts: {} }), "consent");
  eq(checkBody({ question: "cut", facts: {}, consentVersion: 0 }), "consent");
  eq(checkBody(null), "body");
});

Deno.test("checkBody (5C-Chat): free exige texto de 1 a 200 caracteres", () => {
  eq(checkBody({ question: "free", facts: {}, input: { text: "¿Voy bien este mes?" }, consentVersion: 1 }), null);
  eq(checkBody({ question: "free", facts: {}, consentVersion: 1 }), "text");
  eq(checkBody({ question: "free", facts: {}, input: { text: "   " }, consentVersion: 1 }), "text");
  eq(checkBody({ question: "free", facts: {}, input: { text: "a".repeat(201) }, consentVersion: 1 }), "text");
});
