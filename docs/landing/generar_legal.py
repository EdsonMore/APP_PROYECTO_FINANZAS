"""Genera privacidad.html y terminos.html desde assets/legal/*.md (el mismo
texto que muestra la app). Solo usa la biblioteca estándar de Python.

Uso, desde la raíz del repo:  python docs/landing/generar_legal.py
Volver a correrlo cada vez que cambien los .md (por ejemplo, al poner el correo).
"""
import html
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = pathlib.Path(__file__).resolve().parent
PAGES = [
    ("privacidad.md", "privacidad.html", "Política de privacidad"),
    ("terminos.md", "terminos.html", "Términos y condiciones"),
]


def to_html(md: str) -> tuple[str, str]:
    """Mismo Markdown mínimo que parseLegal() en la app: # título, ## subtítulo,
    - viñetas y párrafos. Devuelve (título, cuerpo)."""
    title, body, in_list = "", [], False
    for raw in md.splitlines():
        line = raw.strip()
        is_item = line.startswith("- ")
        if in_list and not is_item:
            body.append("    </ul>")
            in_list = False
        if not line:
            continue
        text = html.escape(line[2:] if is_item else line.lstrip("# "))
        if line.startswith("# "):
            title = text
        elif line.startswith("## "):
            body.append(f"    <h2>{text}</h2>")
        elif is_item:
            if not in_list:
                body.append("    <ul>")
                in_list = True
            body.append(f"      <li>{text}</li>")
        elif line.startswith("Última actualización"):
            body.append(f'    <p class="updated">{text}</p>')
        else:
            body.append(f"    <p>{text}</p>")
    if in_list:
        body.append("    </ul>")
    return title, "\n".join(body)


TEMPLATE = """<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{page_title} | SaldoClaro</title>
  <link rel="stylesheet" href="styles.css">
</head>
<body>
  <main class="legal">
    <a class="back" href="index.html">‹ Volver a SaldoClaro</a>
    <h1>{title}</h1>
{body}
  </main>
  <footer>
    <p>© 2026 SaldoClaro. Hecho en Perú.</p>
  </footer>
</body>
</html>
"""

for src, dst, page_title in PAGES:
    md = (ROOT / "assets" / "legal" / src).read_text(encoding="utf-8")
    title, body = to_html(md)
    (OUT / dst).write_text(TEMPLATE.format(page_title=page_title, title=title, body=body), encoding="utf-8", newline="\n")
    print("generado", dst)
