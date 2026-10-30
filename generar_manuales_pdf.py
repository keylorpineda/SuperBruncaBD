import os
import subprocess
import markdown_it
from pathlib import Path

BASE_DIR = Path(r"C:\Users\Keylo\Documents\UNA\II CICLO 2026\Admin BD\Proyecto")
LOGO_PATH = (BASE_DIR / "logo_una_extraido.png").as_uri()

EDGE_EXE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"

def build_cover_html(title: str, subtitle: str = "Sistema Integral de Cadena de Supermercados — Entregable #2") -> str:
    return f"""
    <div class="cover-page">
        <div class="cover-logo-container">
            <img class="cover-logo" src="{LOGO_PATH}" alt="Universidad Nacional de Costa Rica" />
        </div>
        
        <div class="cover-sede">
            <p class="sede-title">Sede Regional Brunca</p>
            <p class="campus-title">Campus Pérez Zeledón</p>
        </div>
        
        <div class="cover-doc-title">
            <h1 class="main-title">{title}</h1>
            <p class="doc-subtitle">{subtitle}</p>
        </div>
        
        <div class="cover-course-info">
            <p>Curso: Administración de bases de datos</p>
            <p>Profesor: Hairol Romero Sandi</p>
            <p>II Ciclo - Grupo 84</p>
        </div>
        
        <div class="cover-authors-info">
            <p class="students-label">Estudiantes:</p>
            <p class="student-name">Diego Bonilla Mora</p>
            <p class="student-name">Pineda Alvarez Keylor Steven</p>
        </div>
        
        <div class="cover-date">
            <p>Octubre del 2026</p>
        </div>
    </div>
    <div class="page-break"></div>
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
    font-size: 10pt;
    line-height: 1.35;
    color: #111;
    margin: 0;
    padding: 0;
}

/* ================== PORTADA ================== */
.cover-page {
    height: 90vh;
    display: flex;
    flex-direction: column;
    justify-content: space-between;
    align-items: center;
    text-align: center;
    padding-top: 1.5cm;
    padding-bottom: 1.5cm;
}

.cover-logo-container {
    margin-bottom: 25px;
}

.cover-logo {
    width: 210px;
    height: auto;
}

.cover-sede {
    margin-bottom: 35px;
}

.sede-title {
    font-size: 12.5pt;
    font-weight: bold;
    margin: 0 0 4px 0;
}

.campus-title {
    font-size: 11.5pt;
    margin: 0;
}

.cover-doc-title {
    margin-bottom: 40px;
}

.main-title {
    font-size: 15.5pt;
    font-weight: bold;
    margin: 0 0 8px 0;
    line-height: 1.25;
}

.doc-subtitle {
    font-size: 11.5pt;
    color: #333;
    margin: 0;
}

.cover-course-info {
    font-size: 11pt;
    line-height: 1.5;
    margin-bottom: 35px;
}

.cover-course-info p {
    margin: 2px 0;
}

.cover-authors-info {
    font-size: 11pt;
    line-height: 1.5;
    margin-bottom: 45px;
}

.students-label {
    margin: 0 0 4px 0;
}

.student-name {
    margin: 2px 0;
}

.cover-date {
    font-size: 11pt;
    margin-top: auto;
}

.cover-date p {
    margin: 0;
}

.page-break {
    page-break-after: always;
    break-after: page;
}

/* ================== CONTENIDO ================== */
.content-body {
    padding-top: 5px;
}

h1 {
    font-size: 12.5pt;
    font-weight: bold;
    margin-top: 20px;
    margin-bottom: 7px;
    page-break-after: avoid;
    break-after: avoid;
    color: #000;
}

h2 {
    font-size: 11.5pt;
    font-weight: bold;
    margin-top: 15px;
    margin-bottom: 5px;
    page-break-after: avoid;
    break-after: avoid;
    color: #000;
}

h3 {
    font-size: 10.5pt;
    font-weight: bold;
    margin-top: 11px;
    margin-bottom: 4px;
    page-break-after: avoid;
    break-after: avoid;
    color: #111;
}

p {
    font-size: 9.8pt;
    text-align: justify;
    margin-top: 0;
    margin-bottom: 7px;
}

ul, ol {
    margin-top: 3px;
    margin-bottom: 7px;
    padding-left: 22px;
}

li {
    margin-bottom: 3.5px;
    text-align: justify;
    font-size: 9.8pt;
}

/* Tablas con formato idéntico a Documentacion_Tecnica.pdf */
table {
    width: 100%;
    border-collapse: collapse;
    margin: 12px 0 16px 0;
    font-size: 8.5pt;
    page-break-inside: auto;
}

tr {
    page-break-inside: avoid;
    break-inside: avoid;
}

th {
    border-top: 1.5px solid #222;
    border-bottom: 1.2px solid #222;
    padding: 4.5px 5px;
    text-align: left;
    font-weight: bold;
    text-transform: uppercase;
    font-size: 8.2pt;
    background-color: transparent;
}

td {
    padding: 4px 5px;
    vertical-align: top;
    border-bottom: 0.5px solid #dcdcdc;
    font-size: 8.3pt;
}

table tr:last-child td {
    border-bottom: 1.5px solid #222;
}

/* Código y bloques preformateados */
pre {
    background-color: #f7f7f9;
    border: 1px solid #d0d0d5;
    border-left: 3px solid #8B0000;
    padding: 7px 10px;
    border-radius: 2px;
    font-family: 'Consolas', 'Courier New', monospace;
    font-size: 7.8pt;
    line-height: 1.22;
    overflow-x: auto;
    page-break-inside: avoid;
    break-inside: avoid;
    margin: 7px 0 10px 0;
}

code {
    font-family: 'Consolas', 'Courier New', monospace;
    font-size: 8.2pt;
    background-color: #f2f2f5;
    padding: 1px 3px;
    border-radius: 2px;
}

pre code {
    background-color: transparent;
    padding: 0;
    border-radius: 0;
    font-size: 7.8pt;
}

blockquote {
    margin: 7px 0;
    padding: 5px 10px;
    border-left: 3px solid #8B0000;
    background-color: #fdfaf8;
    font-size: 8.8pt;
    page-break-inside: avoid;
    break-inside: avoid;
}

blockquote p {
    margin: 0;
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

    # Quitar el encabezado markdown previo hasta el primer separador "---"
    parts = raw_text.split("---", 2)
    if len(parts) >= 3:
        body_md = parts[2].strip()
    else:
        body_md = raw_text.strip()

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
    
    print(f"Generating PDF for {doc_title}...")
    subprocess.run(cmd, check=True)
    print(f"Created: {pdf_out_path} (exists: {pdf_out_path.exists()})")

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
    print("All PDFs successfully generated!")
