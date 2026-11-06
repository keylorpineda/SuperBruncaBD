import base64
import os
import subprocess
from pathlib import Path
import markdown_it
import fitz

BASE_DIR = Path(__file__).resolve().parent  # docs/manuales: aqui estan los .md, el logo y los .pdf
EDGE_EXE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"

# Cargar logo oficial de la UNA y codificar en base64 para evitar problemas de ruta en Edge
logo_bytes = (BASE_DIR / "logo_una_extraido.png").read_bytes()
logo_b64 = base64.b64encode(logo_bytes).decode("ascii")
LOGO_DATA_URI = f"data:image/png;base64,{logo_b64}"

def build_cover_html(title: str) -> str:
    """
    Construye la portada exactamente igual a Documentacion_Tecnica.pdf:
    - Logo UNA centrado en la parte superior (189.4pt x 150.75pt).
    - Sede Regional Brunca (Negrita 12pt).
    - Campus Pérez Zeledón (Regular 12pt).
    - Solo el Título en negrita 12pt (sin subtítulos, sin 'Entregable #2').
    - Información del curso y profesor (Regular 12pt).
    - Bloque de estudiantes: Diego Bonilla Mora y Pineda Alvarez Keylor Steven (Regular 12pt).
    - Fecha: Octubre del 2026 (Regular 12pt).
    Todo 100% centrado horizontalmente en Times New Roman.
    """
    return f"""
    <div class="cover-page">
        <img class="cover-logo" src="{LOGO_DATA_URI}" alt="Universidad Nacional de Costa Rica" />
        <p class="p-sede-bold">Sede Regional Brunca</p>
        <p class="p-campus">Campus Pérez Zeledón</p>
        <p class="p-title">{title}</p>
        <div class="p-course-block">
            <p>Curso: Administración de bases de datos</p>
            <p>Profesor: Hairol Romero Sandi</p>
            <p style="margin-bottom: 0;">II Ciclo - Grupo 84</p>
        </div>
        <div class="p-authors-block">
            <p>Estudiantes:</p>
            <p>Diego Bonilla Mora</p>
            <p style="margin-bottom: 0;">Pineda Alvarez Keylor Steven</p>
        </div>
        <p class="p-date">Octubre del 2026</p>
    </div>
    """

CSS_STYLES = """
@page {
    size: letter;
    margin: 2.2cm 2.2cm 2.2cm 2.2cm;
}

@media print {
    body {
        -webkit-print-color-adjust: exact;
        print-color-adjust: exact;
    }
}

* {
    box-sizing: border-box;
}

body {
    font-family: 'Times New Roman', 'Nimbus Roman No9 L', 'FreeSerif', Times, serif;
    font-size: 12pt;
    line-height: 1.25;
    color: #000000;
    margin: 0;
    padding: 0;
}

/* ================== PORTADA INSTITUCIONAL (1:1 Documentacion_Tecnica.pdf) ================== */
.cover-page {
    text-align: center;
    page-break-after: always;
    break-after: page;
}

.cover-logo {
    width: 189.4pt;
    height: 150.75pt;
    margin: 18pt auto 24pt auto;
    display: block;
}

.p-sede-bold {
    font-family: 'Times New Roman', Times, serif;
    font-weight: bold;
    font-size: 12pt;
    margin: 0 0 10pt 0;
    text-align: center;
}

.p-campus {
    font-family: 'Times New Roman', Times, serif;
    font-size: 12pt;
    margin: 0 0 34pt 0;
    text-align: center;
}

.p-title {
    font-family: 'Times New Roman', Times, serif;
    font-weight: bold;
    font-size: 12pt;
    margin: 0 0 24pt 0;
    text-align: center;
}

.p-course-block {
    font-family: 'Times New Roman', Times, serif;
    font-size: 12pt;
    margin: 0 0 34pt 0;
    text-align: center;
}

.p-course-block p {
    margin: 0 0 8pt 0;
    text-align: center;
    font-size: 12pt;
}

.p-authors-block {
    font-family: 'Times New Roman', Times, serif;
    font-size: 12pt;
    margin: 0 0 120pt 0;
    text-align: center;
}

.p-authors-block p {
    margin: 0 0 8pt 0;
    text-align: center;
    font-size: 12pt;
}

.p-date {
    font-family: 'Times New Roman', Times, serif;
    font-size: 12pt;
    margin: 0;
    text-align: center;
}

.page-break {
    page-break-after: always;
    break-after: page;
}

/* ================== CONTENIDO ================== */
.content-body {
    font-family: 'Times New Roman', Times, serif;
    font-size: 12pt;
}

h1 {
    font-family: 'Times New Roman', Times, serif;
    font-size: 14pt;
    font-weight: bold;
    margin-top: 20pt;
    margin-bottom: 6pt;
    page-break-after: avoid;
    break-after: avoid;
    color: #000;
}

h2 {
    font-family: 'Times New Roman', Times, serif;
    font-size: 12pt;
    font-weight: bold;
    margin-top: 14pt;
    margin-bottom: 4pt;
    page-break-after: avoid;
    break-after: avoid;
    color: #000;
}

h3 {
    font-family: 'Times New Roman', Times, serif;
    font-size: 12pt;
    font-weight: bold;
    font-style: italic;
    margin-top: 10pt;
    margin-bottom: 3pt;
    page-break-after: avoid;
    break-after: avoid;
    color: #111;
}

p {
    font-family: 'Times New Roman', Times, serif;
    font-size: 12pt;
    text-align: justify;
    line-height: 1.30;
    margin-top: 0;
    margin-bottom: 9pt;
}

ul, ol {
    margin-top: 0;
    margin-bottom: 9pt;
    padding-left: 24pt;
}

li {
    font-family: 'Times New Roman', Times, serif;
    font-size: 12pt;
    text-align: justify;
    line-height: 1.30;
    margin-bottom: 4pt;
}

/* Tablas con formato idéntico a Documentacion_Tecnica.pdf */
table {
    width: 100%;
    border-collapse: collapse;
    margin: 14pt 0 16pt 0;
    font-family: 'Times New Roman', Times, serif;
    font-size: 11pt;
    page-break-inside: auto;
}

tr {
    page-break-inside: avoid;
    break-inside: avoid;
}

th {
    border-top: 1.5px solid #666;
    border-bottom: 1.5px solid #666;
    padding: 5pt 6pt;
    text-align: left;
    font-weight: bold;
    font-size: 11pt;
    background-color: transparent;
}

td {
    padding: 5pt 6pt;
    vertical-align: top;
    border-bottom: 1px solid #d4d4d4;
    font-size: 11pt;
}

table tr:last-child td {
    border-bottom: 1.5px solid #666;
}

/* Código y bloques preformateados limpios */
pre {
    background-color: #f7f7f7;
    border: 1px solid #cccccc;
    padding: 8pt 10pt;
    font-family: Consolas, 'Courier New', monospace;
    font-size: 8pt;
    line-height: 1.22;
    white-space: pre-wrap;
    word-break: break-word;
    max-width: 100%;
    page-break-inside: avoid;
    break-inside: avoid;
    margin: 8pt 0 12pt 0;
}

code {
    font-family: Consolas, 'Courier New', monospace;
    font-size: 8.5pt;
    background-color: #f0f0f0;
    padding: 1pt 3pt;
    word-break: break-word;
}

pre code {
    background-color: transparent;
    padding: 0;
    font-size: 8pt;
    white-space: pre-wrap;
}

blockquote {
    margin: 8pt 0;
    padding: 6pt 12pt;
    border-left: 3px solid #8B0000;
    background-color: #fcfcfc;
    font-size: 11pt;
    page-break-inside: avoid;
    break-inside: avoid;
}

blockquote p {
    margin: 0;
    font-size: 11pt;
}
"""

def markdown_to_clean_html(md_text: str) -> str:
    md = markdown_it.MarkdownIt("commonmark", {"breaks": True, "html": True})
    md.enable("table")
    return md.render(md_text)

def generate_pdf(md_filename: str, output_pdf_filename: str, doc_title: str):
    md_path = BASE_DIR / md_filename
    with open(md_path, "r", encoding="utf-8") as f:
        raw_text = f.read()

    # Extraer el cuerpo eliminando encabezados previos informales
    # Si contiene separador de metadatos o empieza en la primera sección numerada "1."
    lines = raw_text.splitlines()
    start_idx = 0
    for idx, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith("# 1.") or stripped.startswith("## 1.") or stripped.startswith("1."):
            start_idx = idx
            break

    if start_idx > 0:
        body_lines = lines[start_idx:]
    else:
        # Fallback split
        parts = raw_text.split("---", 2)
        if len(parts) >= 3:
            body_lines = parts[2].splitlines()
        else:
            body_lines = raw_text.splitlines()

    # Convertir títulos "## 1." a "# 1." para que sean H1 si venían con "##"
    processed_lines = []
    for l in body_lines:
        # Si contiene "Sistema Integral de Cadena de Supermercados — Entregable #2" lo omitimos
        if "Entregable #2" in l or "Sistema Integral de Cadena de Supermercados" in l:
            continue
        # Promover secciones numéricas principales "## 1." a "# 1."
        if l.startswith("## 1. ") or l.startswith("## 2. ") or l.startswith("## 3. ") or l.startswith("## 4. ") or l.startswith("## 5. ") or l.startswith("## 6. ") or l.startswith("## 7. ") or l.startswith("## 8. "):
            processed_lines.append(l[1:]) # Quita un '#' para volverlo H1
        else:
            processed_lines.append(l)

    body_md = "\n".join(processed_lines).strip()
    body_html = markdown_to_clean_html(body_md)
    cover_html = build_cover_html(doc_title)

    full_html = f"""<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="utf-8">
    <title>{doc_title}</title>
    <style>
    {CSS_STYLES}
    </style>
</head>
<body>
    {cover_html}
    <div class="content-body">
        {body_html}
    </div>
</body>
</html>
"""

    temp_html_path = BASE_DIR / f"{Path(output_pdf_filename).stem}.html"
    with open(temp_html_path, "w", encoding="utf-8") as f:
        f.write(full_html)

    pdf_out_path = BASE_DIR / output_pdf_filename
    
    file_uri = temp_html_path.as_uri()
    cmd = [
        EDGE_EXE,
        "--headless",
        "--disable-gpu",
        "--no-pdf-header-footer",
        f"--print-to-pdf={str(pdf_out_path)}",
        file_uri
    ]
    
    print(f"Generating PDF for: {doc_title}...")
    subprocess.run(cmd, check=True)
    print(f"Created: {pdf_out_path} (exists: {pdf_out_path.exists()})")

    # Verificar portada con PyMuPDF
    doc = fitz.open(str(pdf_out_path))
    print(f"[{output_pdf_filename}] Total pages: {len(doc)}")
    p0 = doc[0]
    blocks = p0.get_text("blocks")
    print(f"[{output_pdf_filename}] Cover Page text blocks:")
    for b in blocks:
        print(f"   y0={b[1]:.1f}, y1={b[3]:.1f}, x0={b[0]:.1f}: {repr(b[4].strip())}")
    imgs = p0.get_images()
    print(f"[{output_pdf_filename}] Cover Page images count: {len(imgs)}")
    if imgs:
        print(f"   Image rect: {p0.get_image_rects(imgs[0][0])}")
    doc.close()
    temp_html_path.unlink(missing_ok=True)  # borrar el HTML temporal

if __name__ == "__main__":
    docs = [
        (
            "Manual_Instalacion_y_Despliegue.md",
            "Manual_Instalacion_y_Despliegue.pdf",
            "Manual de Instalación y Despliegue"
        ),
        (
            "Manual_Administracion_Standby.md",
            "Manual_Administracion_Standby.pdf",
            "Manual de Administración del Standby y Alta Disponibilidad"
        ),
        (
            "Manual_Tecnico_de_Administracion_y_Mantenimiento.md",
            "Manual_Tecnico_de_Administracion_y_Mantenimiento.pdf",
            "Manual Técnico de Administración y Mantenimiento"
        )
    ]
    
    for md_f, pdf_f, title in docs:
        generate_pdf(md_f, pdf_f, title)
    print("\nAll PDFs successfully generated with exact Documentacion_Tecnica.pdf formatting!")
