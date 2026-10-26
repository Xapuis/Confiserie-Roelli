#!/usr/bin/env bash
# ----------------------------------------------------------------------------
#  build-deploy.sh — prépare le dossier deploy/ à envoyer sur Infomaniak
#
#  Copie uniquement ce que le site utilise réellement : les 10 pages, le CSS,
#  le JS, le .htaccess, les favicons, et chaque fichier de assets/ référencé
#  par une page, le CSS ou le JS (src, href, srcset, poster, url(...)).
#  Les originaux, maquettes et outils de développement restent dehors.
#
#  Utilisation :  ./build-deploy.sh
#  Puis envoyer le CONTENU de deploy/ à la racine du site (FTP / gestionnaire
#  de fichiers Infomaniak), en remplaçant l'existant.
#
#  S'arrête avec une erreur si une page référence un fichier introuvable.
# ----------------------------------------------------------------------------
set -euo pipefail
cd "$(dirname "$0")"

python3 - <<'PY'
import html, os, re, shutil, sys

PAGES = ["index", "patisserie", "boulangerie", "confiserie", "magasins",
         "histoire", "tilleuls", "contact", "actualites", "404"]
ALWAYS = [".htaccess", "favicon.ico", "style.css", "js/i18n.js", "js/main.js"]
OUT = "deploy"

refs = set()

def add(url):
    url = html.unescape(url.strip()).split("#")[0].split("?")[0]
    if not url or re.match(r"^(https?:|//|mailto:|tel:|data:)", url):
        return
    refs.add(url.lstrip("/"))

def scan_html(text):
    for m in re.finditer(r'\b(?:src|href|poster)="([^"]+)"', text):
        add(m.group(1))
    for m in re.finditer(r'\b(?:srcset|data-sources)="([^"]+)"', text):
        for part in m.group(1).split(","):
            add(part.strip().split(" ")[0])
    scan_css(text)

def scan_css(text):
    for m in re.finditer(r"url\(\s*['\"]?([^'\")]+)['\"]?\s*\)", text):
        add(m.group(1))

for p in PAGES:
    refs.add(p + ".html")
    with open(p + ".html", encoding="utf-8") as f:
        scan_html(f.read())
with open("style.css", encoding="utf-8") as f:
    scan_css(f.read())
for js in ("js/main.js", "js/i18n.js"):
    with open(js, encoding="utf-8") as f:
        for m in re.finditer(r"['\"`]((?:assets|js)/[^'\"`\s]+)['\"`]", f.read()):
            add(m.group(1))

files = sorted(refs | set(ALWAYS))
missing = [f for f in files if not os.path.isfile(f)]
if missing:
    print("ERREUR — fichiers référencés introuvables :", *missing, sep="\n  ")
    sys.exit(1)

shutil.rmtree(OUT, ignore_errors=True)
for f in files:
    dest = os.path.join(OUT, f)
    os.makedirs(os.path.dirname(dest) or OUT, exist_ok=True)
    shutil.copy2(f, dest)

total = sum(os.path.getsize(f) for f in files)
print(f"deploy/ prêt : {len(files)} fichiers, {total / 1e6:.1f} Mo")
PY
