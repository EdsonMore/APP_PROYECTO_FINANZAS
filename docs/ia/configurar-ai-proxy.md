# Configurar `ai-proxy` (Fase 5C-Infra)

La app nunca tiene la clave de Gemini. La tiene la Edge Function `ai-proxy`
como secreto de Supabase. Estos pasos los haces tú: Claude no toca tus
proyectos de Supabase ni de Google.

> **Nunca** pegues la clave de Gemini, la `service_role` ni contraseñas en el
> chat, en un archivo del repo o en un commit. Todo se escribe en tu terminal.

Orden: primero **saldoclaro-test** (pasos 1 a 6), y recién cuando todo funcione,
lo mismo en **saldoclaro-prod**.

## 1. Facturación de Gemini (antes de usuarios reales)

En el tier gratis, Google puede usar lo que le envías para mejorar sus
productos, y personas pueden revisarlo. Con datos financieros reales hace falta
el tier de pago.

1. Abre Google AI Studio → **API keys**. Mira a qué proyecto de Google Cloud
   pertenece tu clave.
2. En Google Cloud Console → **Billing**, vincula ese proyecto a una cuenta de
   facturación (con tarjeta).
3. Vuelve a AI Studio: el proyecto tiene que figurar con plan **Paid** (no
   "Free").
4. En **Billing → Budgets & alerts**, crea un presupuesto de **US$ 5 al mes**
   con alertas al 50%, 90% y 100%. Con el límite de 10 consultas al día por
   usuario, 1,000 usuarios activos rondan US$ 10-40 al mes.

## 2. Supabase CLI

```powershell
npm i -g supabase          # o: scoop install supabase
supabase login             # abre el navegador
supabase link --project-ref <REF-DE-SALDOCLARO-TEST>
```

El `project-ref` está en Supabase → Project Settings → General.

## 3. Base de datos

1. En Supabase → SQL Editor de **saldoclaro-test**, pega y ejecuta
   `supabase/migrations/20261015000100_ai_usage.sql`.
2. Crea dos usuarios de prueba (Authentication → Add user, Auto Confirm),
   reemplaza los UUID de ejemplo de `supabase/tests/verificar_ai_usage.sql`
   (`aaaaaaaa-…` y `bbbbbbbb-…`) **solo en el editor, sin guardarlos en el
   repo**, y ejecútalo. Tiene que decir **"ai_usage OK"** (termina en
   ROLLBACK: no deja nada).

## 4. Secreto

En tu terminal (la clave no queda en el historial del repo):

```powershell
$k = Read-Host "Clave de Gemini" -AsSecureString
$plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($k))
supabase secrets set GEMINI_API_KEY=$plain
Remove-Variable plain, k
```

Opcionales (tienen valores por defecto):

```powershell
supabase secrets set GEMINI_MODEL=gemini-2.5-flash-lite
supabase secrets set AI_DAILY_LIMIT=10
```

`GEMINI_MODEL` se cambia acá, sin sacar una versión nueva de la app (por
ejemplo, si el 1 de enero de 2027 sube el precio de algún modelo).

## 5. Desplegar

```powershell
supabase functions deploy ai-proxy
```

Deja la verificación de JWT activada (es la opción por defecto): sin sesión,
la función ni siquiera arranca.

## 6. Probar con curl

1. Token de tu usuario de prueba. La contraseña la escribes tú, en la
   terminal, y no queda en ningún archivo:

```powershell
$url  = "https://<REF-DE-SALDOCLARO-TEST>.supabase.co"
$anon = "<ANON KEY de saldoclaro-test>"          # la pública, NO la service_role
$mail = "<correo del usuario de prueba>"
$pass = Read-Host "Contraseña del usuario de prueba"
$body = @{ email = $mail; password = $pass } | ConvertTo-Json
$tok  = (Invoke-RestMethod "$url/auth/v1/token?grant_type=password" -Method Post `
          -Headers @{ apikey = $anon } -ContentType "application/json" -Body $body).access_token
Remove-Variable pass, body
```

2. Una consulta con el ejemplo del repo:

```powershell
curl.exe -s -X POST "$url/functions/v1/ai-proxy" `
  -H "Authorization: Bearer $tok" -H "apikey: $anon" -H "Content-Type: application/json" `
  --data-binary "@docs/ia/ejemplo.json"
```

Esperado: `{"text":"…","left":9}`. Los montos del texto tienen que estar en
`ejemplo.json` (S/ 850.00, S/ 120.00, S/ 45.00, etc.).

3. Los casos de error:

| Prueba | Cómo | Esperado |
|---|---|---|
| Sin sesión | sin el encabezado `Authorization` | 401 |
| Pregunta desconocida | `"question": "otra"` | 400 `{"error":"bad_request","detail":"question"}` |
| Sin consentimiento | sin `consentVersion` | 400 `detail: "consent"` |
| Límite | 10 consultas válidas y una más | 429 `{"error":"limit","left":0}` |

4. Logs: Supabase → Edge Functions → ai-proxy → Logs. Solo tienen que verse
   códigos (`ai-proxy: gemini_timeout`, etc.), nunca hechos ni respuestas.

## Después, en prod

Repite 3, 4 y 5 con `supabase link --project-ref <REF-DE-SALDOCLARO-PROD>`. En
prod no corras el script de verificación con usuarios reales.
