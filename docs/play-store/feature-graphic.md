# Feature graphic (1024 × 500 PNG)

Concepto elegido: **1, "El número"**. Todavía no está generado.

## Concepto

Lo que la app responde, en una imagen: cuántos días te alcanza la plata.

- **Izquierda (≈ 40 %):** el ícono de la app (`assets/icons/logo-app-1024.png`,
  ~140 px) y debajo "SaldoClaro".
- **Derecha (≈ 60 %):** el número "~23 días" grande y, debajo, la línea de
  reserva: un trazo de 2 px en tinta que baja suave de izquierda a derecha,
  sin ejes ni grilla.
- **Único acento:** un punto terracota de ~10 px al final de la línea ("hoy").

## Paleta (sistema "Cuaderno", tema claro)

| Uso | Color |
|---|---|
| Fondo (canvas) | `#F7F6F3` |
| Texto y línea (tinta) | `#2B2A27` (`Palette.light.ink`) |
| Texto secundario (si hiciera falta) | `#6F6E69` (`Palette.light.inkMuted`) |
| Acento (terracota, slot 1 de la paleta categórica) | `#CA653C` |

Nada de verdes ni rojos: son los colores de ingreso y gasto en la app.

## Tipografía

- "SaldoClaro" y "~23 días": **Newsreader Medium (500)**, el archivo
  `assets/fonts/Newsreader16pt-Medium.ttf`. El número a ~150 px de alto;
  el nombre a ~56 px.
- No hay más texto.

## Notas para quien lo diseñe

- Play recorta y superpone botones en algunos lugares: deja ~60 px libres en
  los bordes y no pongas nada importante en el tercio inferior derecho.
- Sin bordes, sombras, degradados ni mockups de teléfono.
- El número es ilustrativo; no debe parecer un dato real del usuario.
- Exportar PNG de 24 bits sin transparencia, 1024 × 500 exactos.
