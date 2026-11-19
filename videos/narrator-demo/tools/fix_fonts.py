"""Gives every composition the same local fonts: no network imports, no missing files."""
import re, sys
BLOCK = """@font-face { font-family: "Instrument Serif"; font-style: normal; font-weight: 400; src: url("assets/fonts/InstrumentSerif.ttf") format("truetype"); font-display: block; }
@font-face { font-family: "Instrument Serif"; font-style: italic; font-weight: 400; src: url("assets/fonts/InstrumentSerif-Italic.woff2") format("woff2"); font-display: block; }
@font-face { font-family: "Archivo"; font-style: normal; font-weight: 100 900; src: url("assets/fonts/Archivo.ttf") format("truetype"); font-display: block; }
"""
for path in sys.argv[1:]:
    html = open(path).read()
    html = re.sub(r"[ \t]*@import url\([\"']https://fonts\.googleapis\.com[^)]*\);?[ \t]*\n?", "", html)
    html = re.sub(r"[ \t]*@font-face\s*\{[^}]*\}[ \t]*\n?", "", html)
    html = re.sub(r"(<style[^>]*>\n?)", lambda m: m.group(1) + BLOCK, html, count=1)
    assert "assets/fonts/Archivo.ttf" in html, path
    open(path, "w").write(html)
    print("fonts set:", path)
