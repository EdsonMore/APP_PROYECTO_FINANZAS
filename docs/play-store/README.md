# Publicar SaldoClaro en Google Play (Fase 2C)

**Estado:** todo preparado, sin publicar. La Fase 2C requiere una cuenta de
desarrollador de Google Play (pago único de **25 USD**). Hasta tenerla, no se
sube nada.

## Archivos de esta carpeta

| Archivo | Qué es |
|---|---|
| `descripcion.md` | Nombre, descripción corta y larga, categoría y etiquetas |
| `politica-privacidad.md` | Política de privacidad (idéntica a la de la app) |
| `terminos.md` | Términos y condiciones (idénticos a los de la app) |
| `firma.md` | Cómo crear el keystore de subida y firmar la release |
| `feature-graphic.md` | Concepto del gráfico de 1024 × 500 |

## Decisiones ya tomadas

- **Package name: `com.saldoclar.app`.** Se eligió así por decisión del
  desarrollador. Los package names son invisibles al usuario final y no se
  pueden cambiar después de publicar.
- **Versión:** `0.2.0+1` en `pubspec.yaml` (versionName 0.2.0, versionCode 1).
  Cada subida a Play necesita un versionCode mayor que el anterior: súbelo
  (`+2`, `+3`…) antes de cada `appbundle` nuevo.
- **Copia de seguridad de Android:** se mantiene activa y la política lo
  explica.

## Antes de empezar

- [ ] Confirmar que `saldoclaro.oficial@gmail.com` (provisional) es el correo del proyecto; si no, cambiarlo en
      `assets/legal/privacidad.md`, `assets/legal/terminos.md` y las copias de
      esta carpeta (un test exige que sean idénticas).
- [ ] Publicar `politica-privacidad.md` en una URL pública (por ejemplo GitHub
      Pages: Settings → Pages del repo, o un Gist). Play pide esa URL.
- [ ] Generar el feature graphic según `feature-graphic.md`.
- [ ] Sacar capturas del teléfono (mínimo 2; ideal 4 a 8): Home, registro,
      Presupuesto e Insights. Sirven las de `docs/screenshots/`.

## Pasos en Play Console

1. **Crear la cuenta** en https://play.google.com/console (25 USD, cuenta
   personal). Google verifica tu identidad; puede tardar unos días.
2. **Crear la app:** nombre "SaldoClaro", idioma español (Latinoamérica), App,
   Gratis.
3. **Firma:** crea el keystore de subida y `android/key.properties` siguiendo
   `firma.md`. Deja activado **Play App Signing** (es la opción por defecto).
4. **Compilar:** `flutter build appbundle --release`.
5. **Configurar la ficha** (Crecimiento → Presencia en Play Store → Ficha
   principal): textos de `descripcion.md`, ícono 512 × 512
   (`assets/icons/logo-app-1024.png` reducido), feature graphic y capturas.
6. **Contenido de la app** (Política → Contenido de la app):
   - Política de privacidad: la URL pública.
   - Anuncios: no tiene.
   - Acceso a la app: no requiere login (la cuenta es opcional).
   - Clasificación de contenido: completa el cuestionario (app de finanzas,
     sin contenido sensible).
   - Público objetivo: mayores de 18 (coherente con la política).
   - **Seguridad de los datos** (Fase 3: sync opcional):
     - ¿Recopila datos? **Sí**, solo si el usuario activa la sincronización.
       Marcar **"opcional"** en cada tipo:
       - Información personal → Dirección de correo electrónico. Finalidad:
         funcionalidad de la app y administración de la cuenta.
       - Información financiera → Otra información financiera (movimientos,
         saldo, techos). Finalidad: funcionalidad de la app.
     - ¿Comparte datos? **Sí, solo si el usuario activa la IA** (Fase 5C):
       - Información financiera → Otra información financiera (números ya
         resumidos: totales por categoría, promedios, saldo, pagos
         pendientes). Con Google (Gemini). **Opcional.** Finalidad:
         funcionalidad de la app. No se comparte el correo ni los movimientos
         uno por uno.
       - Supabase y el servicio de correo procesan los datos por nuestra
         cuenta; Google no lo cuenta como compartir. Gemini de pago también
         actúa por nuestra cuenta (Data Processing Addendum), pero lo
         declaramos como compartido por prudencia, hasta que lo revise el
         abogado.
     - Datos cifrados en tránsito: **Sí.**
     - El usuario puede pedir que se borren: **Sí**, desde la app y desde la
       URL pública de `docs/landing/borrar-cuenta.html`.
   - Apps financieras: declarar que no ofrece préstamos ni servicios
     financieros; es una herramienta de registro personal.
7. **Prueba cerrada** (Pruebas → Prueba cerrada): crea un track, sube el
   `.aab`, agrega a los testers por correo. Las cuentas personales nuevas
   necesitan una prueba cerrada con al menos 12 testers durante 14 días antes
   de poder pasar a producción.
8. **Producción:** cuando la prueba cerrada cumpla los requisitos, solicita el
   acceso a producción desde el panel y promueve la versión.

## Después de cada versión

- Subir el versionCode en `pubspec.yaml`.
- Actualizar la fecha de la política o los términos si cambian, y avisar
  dentro de la app (lo prometen los textos).
