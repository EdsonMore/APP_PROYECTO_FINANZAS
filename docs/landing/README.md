# Landing de SaldoClaro

HTML + CSS, sin JavaScript, sin cookies, sin analítica y sin recursos externos:
las fuentes (Newsreader y Geist, licencia OFL en `fonts/`) y la imagen van en
esta carpeta, así que funciona offline.

| Archivo | Qué es |
|---|---|
| `index.html` | Portada |
| `styles.css` | Sistema visual "Cuaderno" |
| `privacidad.html`, `terminos.html` | Generados desde `assets/legal/*.md` |
| `generar_legal.py` | Regenera las dos páginas legales (solo Python estándar) |
| `home.png` | Captura del Home (46 KB) |
| `fonts/` | WOFF2 + licencias OFL |

## Cambiar los textos legales o el correo

1. Edita `assets/legal/privacidad.md` y `assets/legal/terminos.md` (son los que
   muestra la app) y copia los mismos archivos a `docs/play-store/`.
2. Desde la raíz del repo: `python docs/landing/generar_legal.py`.
3. Si cambia el correo de contacto (hoy `saldoclaro.oficial@gmail.com`, por confirmar), cámbialo también en `index.html` y `borrar-cuenta.html`.
4. `flutter test test/features/settings/legal_test.dart`: falla si la app, la
   carpeta de Play y la web no dicen lo mismo.

## Publicar gratis

### GitHub Pages (recomendado)

La forma más simple es publicar solo esta carpeta con una rama aparte:

```
git subtree push --prefix docs/landing origin gh-pages
```

Luego en GitHub: Settings → Pages → Source: "Deploy from a branch" → rama
`gh-pages`, carpeta `/ (root)`. En uno o dos minutos queda en
`https://<usuario>.github.io/<repo>/`. Repite el `subtree push` cada vez que
cambie la landing.

Ojo: el repo tiene que ser público para usar Pages gratis. Si prefieres no
abrirlo, usa Netlify.

### Netlify

1. Entra a https://app.netlify.com/drop.
2. Arrastra la carpeta `docs/landing` completa.
3. Netlify te da una URL `https://<nombre>.netlify.app` (puedes cambiar el
   nombre en Site settings).

### URL para Play Console

La política queda en `<url de la landing>/privacidad.html`. Esa es la URL que
pide Play en "Política de privacidad".
