"""Genera la tarjeta animada del README (`card-{light,dark}.svg`) y las pestañas de arriba.

La tarjeta es un tiquete de caja dibujado en SVG, con animaciones solo de CSS (GitHub quita
los scripts de las imágenes). Se vuelve a generar después de cambiar un dato:

    python docs/assets/readme/build_readme_card.py
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from xml.sax.saxutils import escape

OUT = Path(__file__).resolve().parent
WIDTH = 800
SERIF = "Georgia, 'Iowan Old Style', 'Times New Roman', serif"
MONO = "ui-monospace, 'Cascadia Mono', Consolas, Menlo, 'DejaVu Sans Mono', monospace"


@dataclass(frozen=True)
class Palette:
    name: str
    paper: str
    card: str
    ink: str
    muted: str
    rule: str
    accent: str
    standby: str
    ok: str
    tape: str
    pill_bg: str
    pill_fg: str


LIGHT = Palette("light", "#F3ECE1", "#FCF8F1", "#241D18", "#6B5D50", "#D2C2AC",
                "#B83A26", "#2F6F73", "#2E7D4F", "#E8D2A6", "#2A211B", "#FCF8F1")
DARK = Palette("dark", "#15110E", "#1E1915", "#EFE7DD", "#B5A797", "#4B4036",
               "#F0785C", "#5FB3B8", "#5BC48A", "#4F4337", "#F0E6D6", "#1E1915")


def t(x: float, y: float, cls: str, text: str, anchor: str = "start", extra: str = "") -> str:
    a = f' text-anchor="{anchor}"' if anchor != "start" else ""
    return f'<text x="{x}" y="{y}" class="{cls}"{a}{extra}>{escape(text)}</text>'


def style(p: Palette) -> str:
    return f"""<style>
.k {{ font: 700 13px {MONO}; fill: {p.muted}; letter-spacing: 3px; }}
.title {{ font: 700 60px {SERIF}; fill: {p.ink}; }}
.tag {{ font: italic 400 23px {SERIF}; fill: {p.muted}; }}
.h {{ font: 700 30px {SERIF}; fill: {p.ink}; }}
.b {{ font: 400 19px {SERIF}; fill: {p.ink}; }}
.m {{ font: 400 17px {SERIF}; fill: {p.muted}; }}
.d {{ font: 700 15px {MONO}; fill: {p.ink}; }}
.da {{ font: 700 15px {MONO}; fill: {p.accent}; }}
.ds {{ font: 600 13px {MONO}; fill: {p.muted}; }}
.big {{ font: 700 44px {MONO}; fill: {p.accent}; }}
.stamp {{ font: 800 15px {MONO}; letter-spacing: 2px; }}
.pill {{ font: 700 13px {MONO}; fill: {p.pill_fg}; letter-spacing: 1px; }}
.num {{ font: 700 13px {MONO}; fill: {p.ink}; }}
.fb {{ transform-box: fill-box; transform-origin: center; }}
.fbot {{ transform-box: fill-box; transform-origin: center bottom; }}
.pkt {{ animation: pkt 3.6s linear infinite both; }}
.pkt2 {{ animation: pkt 3.6s linear 1.2s infinite both; }}
.pkt3 {{ animation: pkt 3.6s linear 2.4s infinite both; }}
.blink {{ animation: blink 1.2s steps(1) infinite; }}
.pulse {{ animation: pulse 1.8s ease-in-out infinite; }}
.node {{ opacity: 0; animation: node 10s steps(1) infinite both; }}
.grow {{ animation: grow 9s cubic-bezier(.2,.7,.2,1) infinite both; }}
.stp {{ animation: stp 12s cubic-bezier(.2,.9,.3,1.4) infinite both; }}
.chk {{ stroke-dasharray: 30; animation: chk 12s ease-out infinite both; }}
.float {{ animation: float 6s ease-in-out infinite alternate; }}
@keyframes pkt {{ 0% {{ transform: translateX(0); opacity: 0; }} 8% {{ opacity: 1; }}
  85% {{ opacity: 1; }} 100% {{ transform: translateX(78px); opacity: 0; }} }}
@keyframes blink {{ 50% {{ opacity: .2; }} }}
@keyframes pulse {{ 50% {{ opacity: .35; }} }}
@keyframes node {{ 0% {{ opacity: .3; }} 20%, 100% {{ opacity: 0; }} }}
@keyframes grow {{ 0% {{ transform: scaleY(0); }} 25%, 100% {{ transform: scaleY(1); }} }}
@keyframes stp {{ 0% {{ opacity: 0; transform: scale(1.8) rotate(-8deg); }}
  6%, 100% {{ opacity: 1; transform: scale(1) rotate(-4deg); }} }}
@keyframes chk {{ 0% {{ stroke-dashoffset: 30; }} 5%, 100% {{ stroke-dashoffset: 0; }} }}
@keyframes float {{ from {{ transform: translateY(-4px); }} to {{ transform: translateY(4px); }} }}
@media (prefers-reduced-motion: reduce) {{
  * {{ animation: none !important; }}
  .pkt, .pkt2, .pkt3 {{ display: none; }}
}}
</style>"""


def section_head(p: Palette, y: float, kicker: str, heading: str) -> list[str]:
    return [
        t(50, y, "k", kicker),
        t(50, y + 38, "h", heading),
        f'<rect x="50" y="{y + 54}" width="50" height="4" fill="{p.accent}"/>',
    ]


def cylinder(p: Palette, cx: float, top: float, color: str, label: str, role: str, delay: str) -> list[str]:
    w, h, ry = 110, 130, 18
    x = cx - w / 2
    out = [
        f'<rect x="{x}" y="{top}" width="{w}" height="{h}" fill="{color}"/>',
        f'<ellipse cx="{cx}" cy="{top + h}" rx="{w / 2}" ry="{ry}" fill="{color}"/>',
    ]
    for i in (1, 2):
        yy = top + i * h / 3
        out.append(f'<path d="M{x} {yy} A{w / 2} {ry} 0 0 0 {x + w} {yy}" fill="none" '
                   f'stroke="{p.card}" stroke-opacity=".45" stroke-width="2"/>')
    out.append(f'<ellipse cx="{cx}" cy="{top}" rx="{w / 2}" ry="{ry}" fill="{color}" '
               f'stroke="{p.card}" stroke-opacity=".6" stroke-width="2"/>')
    out.append(f'<circle cx="{x + w - 18}" cy="{top + 40}" r="4" fill="{p.card}" class="blink" '
               f'style="animation-delay:{delay}"/>')
    out.append(t(cx, top + h + 48, "d", label, "middle"))
    out.append(t(cx, top + h + 66, "ds", role, "middle"))
    return out


def receipt_edge(x: float, y: float, w: float, fill: str, down: bool = True) -> str:
    """Borde dentado de tiquete (triángulos pequeños)."""
    step, depth = 12, 7
    pts = [f"{x},{y}"]
    n = int(w // step)
    for i in range(n):
        pts.append(f"{x + i * step + step / 2},{y + (depth if down else -depth)}")
        pts.append(f"{x + (i + 1) * step},{y}")
    return f'<polygon points="{" ".join(pts)}" fill="{fill}"/>'


def build_card(p: Palette) -> str:
    e: list[str] = []
    fill_acc = f' fill="{p.accent}"'
    # ---------------- encabezado ----------------
    e.append(t(50, 78, "k", "TIQUETE N.º 0001 · SUPER BRUNCA · HOJA 01"))
    e.append(t(46, 140, "title", "Super"))
    e.append(t(46, 200, "title", "Brunca"))
    e.append(t(50, 248, "tag", "La base de datos que sigue"))
    e.append(t(50, 276, "tag", "vendiendo si se cae un servidor."))
    e.append(t(50, 310, "m", "Oracle 21c · PL/SQL · Data Guard · RMAN."))
    e.append(f'<rect x="50" y="330" width="292" height="34" rx="17" fill="{p.pill_bg}"/>')
    e.append(f'<circle cx="70" cy="347" r="6" fill="{p.ok}" class="pulse"/>')
    e.append(t(86, 352, "pill", "REDO APPLY · EN TIEMPO REAL"))

    # Ilustración: principal -> standby con paquetes de redo
    e.append('<g class="float">')
    e += cylinder(p, 470, 120, p.accent, "CADENA", "PRIMARY", "0s")
    e += cylinder(p, 690, 120, p.standby, "CADENA_STBY", "STANDBY", ".6s")
    e.append(f'<line x1="528" y1="185" x2="632" y2="185" stroke="{p.muted}" stroke-width="2" '
             f'stroke-dasharray="6 6"/>')
    e.append(t(580, 166, "ds", "redo · 1521", "middle"))
    e.append(t(580, 213, "ds", "ASYNC", "middle"))
    for cls in ("pkt", "pkt2", "pkt3"):
        e.append(f'<g class="{cls}"><rect x="532" y="179" width="22" height="12" rx="2" '
                 f'fill="{p.tape}" stroke="{p.ink}" stroke-width="1.2"/></g>')
    e.append("</g>")

    # ---------------- cifras ----------------
    stats = [("3,76M", "personas del", "padrón, 0 rechazos"),
             ("65", "tablas y", "225 índices"),
             ("11", "jobs de", "DBMS_SCHEDULER"),
             ("0", "ventas perdidas", "en el failover")]
    for i, (big, l1, l2) in enumerate(stats):
        x = 50 + i * 179
        e.append(f'<rect x="{x}" y="408" width="163" height="100" rx="4" fill="{p.card}" '
                 f'stroke="{p.rule}" stroke-width="1.5"/>')
        e.append(f'<rect x="{x}" y="408" width="163" height="7" rx="2" fill="{p.accent}"/>')
        e.append(t(x + 13, 462, "big", big))
        e.append(t(x + 13, 484, "ds", l1))
        e.append(t(x + 13, 499, "ds", l2))

    # ---------------- 1. cómo viaja una venta ----------------
    y = 570
    e += section_head(p, y, "CÓMO VIAJA UNA VENTA", "De la caja a la otra computadora")
    steps = [("VENTA", "INSERT en", "VEN_FACTURA"),
             ("TRIGGERS", "crédito, kárdex,", "auditoría"),
             ("REDO", "50 MB o", "5 minutos"),
             ("DATA GUARD", "ASYNC por", "el puerto 1521"),
             ("STANDBY", "aplica en", "tiempo real")]
    cy = y + 120
    e.append(f'<line x1="90" y1="{cy}" x2="710" y2="{cy}" stroke="{p.rule}" stroke-width="3"/>')
    for i, (name, l1, l2) in enumerate(steps):
        cx = 90 + i * 155
        e.append(f'<circle cx="{cx}" cy="{cy}" r="28" fill="{p.card}" stroke="{p.accent}" stroke-width="3"/>')
        e.append(f'<circle cx="{cx}" cy="{cy}" r="28" fill="{p.accent}" class="node" '
                 f'style="animation-delay:{i * 2}s"/>')
        e.append(t(cx, cy + 5, "num", str(i + 1), "middle"))
        e.append(t(cx, cy + 58, "d", name, "middle"))
        e.append(t(cx, cy + 78, "ds", l1, "middle"))
        e.append(t(cx, cy + 94, "ds", l2, "middle"))
    e.append(t(50, cy + 140, "m", "Si la standby se apaga, la principal sigue vendiendo. Al volver,"))
    e.append(t(50, cy + 162, "m", "la standby pide sola los archivelogs que le faltan (FAL)."))

    # ---------------- 2. reglas en la base ----------------
    y = cy + 225
    e += section_head(p, y, "LAS REGLAS VIVEN EN LA BASE", "Un tiquete que no pasa")
    ry = y + 90
    rx, rw, rh = 50, 330, 300
    e.append(f'<rect x="{rx}" y="{ry}" width="{rw}" height="{rh}" fill="{p.card}" '
             f'stroke="{p.rule}" stroke-width="1.5"/>')
    e.append(receipt_edge(rx, ry + rh, rw, p.card))
    e.append(f'<rect x="{rx + 120}" y="{ry - 12}" width="90" height="24" fill="{p.tape}" '
             f'opacity=".85" transform="rotate(-3 {rx + 165} {ry})"/>')
    lines = [("SUPER BRUNCA · CAJA 02", None),
             ("factura a crédito", "₡50 000 000"),
             ("cliente 1042 · saldo", "₡1 840 000"),
             ("límite de crédito", "₡2 000 000")]
    yy = ry + 42
    for left, right in lines:
        e.append(t(rx + 22, yy, "d" if right is None else "ds", left))
        if right:
            e.append(t(rx + rw - 22, yy, "ds", right, "end"))
        yy += 30
        if right is None:
            e.append(f'<line x1="{rx + 22}" y1="{yy - 16}" x2="{rx + rw - 22}" y2="{yy - 16}" '
                     f'stroke="{p.rule}" stroke-dasharray="4 4"/>')
    e.append(f'<line x1="{rx + 22}" y1="{yy - 8}" x2="{rx + rw - 22}" y2="{yy - 8}" '
             f'stroke="{p.rule}" stroke-dasharray="4 4"/>')
    e.append(f'<g class="stp fb"><rect x="{rx + 48}" y="{yy + 22}" width="234" height="58" rx="6" '
             f'fill="none" stroke="{p.accent}" stroke-width="3"/>'
             f'{t(rx + 165, yy + 47, "stamp", "RECHAZADA", "middle", fill_acc)}'
             f'{t(rx + 165, yy + 68, "stamp", "ORA-20010", "middle", fill_acc)}</g>')

    # columna derecha: reglas
    gx = 420
    rules = [("crédito", "crea la cuenta por cobrar"),
             ("abono", "saldada = factura cancelada"),
             ("costo", "queda en el historial"),
             ("factura", "mueve el kárdex"),
             ("cambio", "bitácora con antes/después")]
    yy = ry + 22
    for code, desc in rules:
        e.append(f'<circle cx="{gx + 6}" cy="{yy - 5}" r="4" fill="{p.accent}"/>')
        e.append(t(gx + 20, yy, "d", code))
        e.append(t(gx + 20, yy + 18, "ds", desc))
        yy += 46
    e.append(t(gx, yy + 4, "ds", "-20010 · -20015 · -20018 ..."))
    e.append(t(gx, yy + 21, "ds", "un código por cada regla"))
    e.append(t(50, ry + rh + 50, "m", "Son triggers: se cumplen vengan los datos de donde vengan."))
    e.append(t(50, ry + rh + 72, "m", "Con SAVEPOINT y ROLLBACK TO, una venta nunca queda a medias."))

    # ---------------- 3. RMAN ----------------
    y = ry + rh + 135
    e += section_head(p, y, "RESPALDO Y RECUPERACIÓN", "Una semana de RMAN")
    base = y + 270
    days = ["D", "L", "K", "M", "J", "V", "S"]
    for i, dname in enumerate(days):
        x = 64 + i * 50
        hgt = 160 if i == 0 else 46
        col = p.accent if i == 0 else p.standby
        e.append(f'<rect x="{x}" y="{base - hgt}" width="32" height="{hgt}" rx="3" fill="{col}" '
                 f'class="grow fbot" style="animation-delay:{i * .15}s"/>')
        e.append(t(x + 16, base + 22, "d", dname, "middle"))
    e.append(f'<line x1="54" y1="{base}" x2="400" y2="{base}" stroke="{p.rule}" stroke-width="2"/>')
    e.append(t(64, base - 172, "da", "NIVEL 0"))
    e.append(t(120, base - 58, "ds", "nivel 1 · solo bloques cambiados"))
    facts = [("01:00", "comprimido, 2 canales"),
             ("VALIDATE", "cada respaldo se verifica"),
             ("14 días", "de retención"),
             ("03:00", "purga > 3 días: solo lo"),
             ("", "aplicado y respaldado")]
    yy = y + 110
    for k, v in facts:
        if not k:
            yy -= 12
        if k:
            e.append(t(450, yy, "d", k))
            yy += 18
        e.append(t(450, yy, "ds", v))
        yy += 30
    rec = [("COMPLETA", "restore + recover"),
           ("PUNTO EN EL TIEMPO", "until time + resetlogs"),
           ("UN SOLO PDB", "probado en 21c")]
    by = base + 60
    for i, (name, sub) in enumerate(rec):
        x = 50 + i * 238
        e.append(f'<rect x="{x}" y="{by}" width="222" height="70" rx="4" fill="{p.card}" '
                 f'stroke="{p.rule}" stroke-width="1.5"/>')
        e.append(t(x + 16, by + 30, "d", name))
        e.append(t(x + 16, by + 52, "ds", sub))
        if i == 2:
            e.append(f'<path d="M{x + 186} {by + 32} l8 8 l14 -16" fill="none" stroke="{p.ok}" '
                     f'stroke-width="4" stroke-linecap="round" class="chk"/>')

    # ---------------- 4. pruebas ----------------
    y = by + 140
    e += section_head(p, y, "CUANDO ALGO FALLA", "Probado, no solo configurado")
    tests = [("SWITCHOVER", "ida y vuelta,", "sin perder datos"),
             ("FAILOVER", "docker kill a la principal:", "la última venta estaba"),
             ("RECONSTRUCCIÓN", "la antigua principal", "vuelve como standby"),
             ("REPLICACIÓN", "reinstalar el esquema", "completo: retraso 0")]
    for i, (name, l1, l2) in enumerate(tests):
        x = 50 + (i % 2) * 358
        yy = y + 90 + (i // 2) * 110
        e.append(f'<rect x="{x}" y="{yy}" width="342" height="92" rx="4" fill="{p.card}" '
                 f'stroke="{p.rule}" stroke-width="1.5"/>')
        e.append(f'<circle cx="{x + 40}" cy="{yy + 46}" r="22" fill="none" stroke="{p.ok}" stroke-width="3"/>')
        e.append(f'<path d="M{x + 29} {yy + 46} l8 8 l14 -16" fill="none" stroke="{p.ok}" '
                 f'stroke-width="4" stroke-linecap="round" class="chk" style="animation-delay:{i * .4}s"/>')
        e.append(t(x + 80, yy + 34, "d", name))
        e.append(t(x + 80, yy + 56, "ds", l1))
        e.append(t(x + 80, yy + 74, "ds", l2))

    # ---------------- 5. qué hay adentro ----------------
    y = y + 90 + 220 + 50
    e += section_head(p, y, "QUÉ HAY ADENTRO", "Un repositorio, tres cajones")
    boxes = [("sql/", "instalador 00 → 06", ["· 10 paquetes PL/SQL", "· 21 triggers", "· seguridad y correo"]),
             ("07_Standby_y_RMAN/", "Data Guard + RMAN", ["· redo 50 MB / 5 min", "· purga de 3 días", "· switchover, failover"]),
             ("menu.ps1", "PowerShell", ["· detecta la PC y el rol", "· muestra el comando", "· 15 opciones"])]
    fy = y + 90
    for i, (name, sub, items) in enumerate(boxes):
        x = 50 + i * 238
        e.append(f'<path d="M{x} {fy + 12} h70 l12 -12 h140 v150 h-222 z" fill="{p.card}" '
                 f'stroke="{p.rule}" stroke-width="1.5"/>')
        e.append(t(x + 16, fy + 44, "da", name))
        e.append(t(x + 16, fy + 64, "ds", sub))
        for j, it in enumerate(items):
            e.append(t(x + 16, fy + 94 + j * 18, "ds", it))
    e.append(f'<rect x="50" y="{fy + 185}" width="700" height="52" rx="4" fill="{p.pill_bg}"/>')
    e.append(t(400, fy + 216, "pill", "TODO SE PARAMETRIZA EN SEG_PARAMETRO · SIN TOCAR EL CÓDIGO", "middle"))

    # ---------------- pie ----------------
    sy = fy + 300
    e.append(f'<g class="stp fb" style="animation-delay:.5s"><rect x="180" y="{sy}" width="440" height="66" '
             f'rx="6" fill="none" stroke="{p.accent}" stroke-width="3"/>'
             f'{t(400, sy + 28, "stamp", "ORACLE 21c ENTERPRISE", "middle", fill_acc)}'
             f'{t(400, sy + 50, "stamp", "DOS COMPUTADORAS · DOCKER", "middle", fill_acc)}</g>')
    e.append(t(400, sy + 118, "m", "Universidad Nacional · Sede Regional Brunca", "middle"))
    e.append(t(400, sy + 140, "m", "Administración de Bases de Datos, 2026", "middle"))
    e.append(t(400, sy + 172, "ds", "gracias por su compra · vuelva pronto", "middle"))
    e.append(t(400, sy + 196, "d", "Keylor Pineda · Diego Bonilla", "middle"))
    height = int(sy + 250)

    # ---------------- fondo ----------------
    bg = [f'<rect width="{WIDTH}" height="{height}" fill="{p.paper}"/>',
          f'<rect x="20" y="28" width="760" height="{height - 56}" fill="{p.card}" opacity=".55"/>',
          receipt_edge(20, 28, 760, p.card, down=False),
          receipt_edge(20, height - 28, 760, p.card, down=True)]
    for ly in range(140, height - 60, 36):
        bg.append(f'<line x1="36" y1="{ly}" x2="764" y2="{ly}" stroke="{p.rule}" opacity=".22"/>')
    bg.append(f'<line x1="36" y1="40" x2="36" y2="{height - 40}" stroke="{p.accent}" opacity=".18"/>')

    desc = ("Super Brunca, base de datos Oracle 21c con Data Guard y RMAN para una cadena de "
            "supermercados. Todo el contenido de esta tarjeta está como texto debajo de ella.")
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {WIDTH} {height}" width="{WIDTH}" '
            f'height="{height}" role="img" aria-labelledby="t d"><title id="t">Super Brunca</title>'
            f'<desc id="d">{escape(desc)}</desc>{style(p)}' + "".join(bg) + "".join(e) + "</svg>\n")


def tab(label: str, p: Palette = LIGHT) -> str:
    w = max(110, 12 + len(label) * 10)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w + 6} 46" width="{w + 6}" height="46" '
            f'role="img" aria-label="{escape(label)}"><title>{escape(label)}</title>'
            f'<rect x="5" y="5" width="{w}" height="40" rx="6" fill="{p.pill_bg}"/>'
            f'<rect x="1" y="1" width="{w}" height="40" rx="6" fill="{p.tape}" stroke="{p.pill_bg}" stroke-width="2"/>'
            f'<text x="{w / 2 + 1}" y="27" text-anchor="middle" font-family="{MONO}" font-weight="700" '
            f'font-size="15" letter-spacing="1" fill="{p.pill_bg}">{escape(label)}</text></svg>\n')


def main() -> None:
    for pal in (LIGHT, DARK):
        (OUT / f"card-{pal.name}.svg").write_text(build_card(pal), encoding="utf-8")
    tabs = {"tab-instalar": "INSTALAR", "tab-standby": "STANDBY",
            "tab-tecnico": "MANUAL TÉCNICO", "tab-modelo": "MODELO"}
    for name, label in tabs.items():
        (OUT / f"{name}.svg").write_text(tab(label), encoding="utf-8")
    print("listo:", ", ".join(sorted(f.name for f in OUT.glob("*.svg"))))


if __name__ == "__main__":
    main()
