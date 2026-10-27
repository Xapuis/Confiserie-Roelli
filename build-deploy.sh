#!/usr/bin/env bash
# ----------------------------------------------------------------------------
#  build-deploy.sh — prépare le dossier deploy/ à envoyer sur Infomaniak
#
#  Copie uniquement ce que le site utilise réellement : les 11 pages, le CSS,
#  le JS, le .htaccess, robots.txt, sitemap.xml, les favicons, et chaque
#  fichier de assets/ référencé par une page, le CSS ou le JS (src, href,
#  srcset, poster, url(...), et les adresses {{BASE_URL}}/… des balises
#  de partage et des données structurées).
#  Les originaux, maquettes et outils de développement restent dehors.
#
#  Dans les copies, {{BASE_URL}} est remplacé par l'adresse ci-dessous
#  (balises canonical et Open Graph, données structurées, robots.txt,
#  sitemap.xml). Pour passer à « www », ne changer que cette ligne.
#  {{LASTMOD}} (sitemap.xml) devient la date du jour de la génération.
#
#  Utilisation :  ./build-deploy.sh
#  Puis envoyer le CONTENU de deploy/ à la racine du site (FTP / gestionnaire
#  de fichiers Infomaniak), en remplaçant l'existant.
#
#  S'arrête avec une erreur si une page référence un fichier introuvable.
# ----------------------------------------------------------------------------
set -euo pipefail
cd "$(dirname "$0")"

# Adresse du site, sans « / » final.
export BASE_URL="https://confiserie-roelli.ch"

python3 - <<'PY'
import datetime, html, os, re, shutil, sys

BASE_URL = os.environ["BASE_URL"].rstrip("/")
TODAY = datetime.date.today().isoformat()
PAGES = ["index", "patisserie", "boulangerie", "confiserie", "magasins",
         "histoire", "tilleuls", "contact", "actualites", "404",
         "mentions-legales"]
ALWAYS = [".htaccess", "favicon.ico", "style.css", "js/i18n.js", "js/main.js",
          "robots.txt", "sitemap.xml"]
WITH_BASE_URL = (".html", ".txt", ".xml")
OUT = "deploy"

refs = set()

def add(url):
    url = html.unescape(url.strip()).split("#")[0].split("?")[0]
    if not url or re.match(r"^(https?:|//|mailto:|tel:|data:|\{\{)", url):
        return
    refs.add(url.lstrip("/"))

def scan_html(text):
    for m in re.finditer(r'\b(?:src|href|poster)="([^"]+)"', text):
        add(m.group(1))
    for m in re.finditer(r'\b(?:srcset|data-sources)="([^"]+)"', text):
        for part in m.group(1).split(","):
            add(part.strip().split(" ")[0])
    # Balises de partage et JSON-LD : {{BASE_URL}}/chemin/fichier.ext
    for m in re.finditer(r'\{\{BASE_URL\}\}/([^"\s<#?]+\.[a-z0-9]+)', text):
        add(m.group(1))
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
    if f.endswith(WITH_BASE_URL):
        with open(f, encoding="utf-8") as src:
            text = src.read().replace("{{BASE_URL}}", BASE_URL).replace("{{LASTMOD}}", TODAY)
        with open(dest, "w", encoding="utf-8") as out:
            out.write(text)
        shutil.copystat(f, dest)
    else:
        shutil.copy2(f, dest)

leftover = [f for f in files if f.endswith(WITH_BASE_URL)
            and re.search(r"\{\{(BASE_URL|LASTMOD)\}\}", open(os.path.join(OUT, f), encoding="utf-8").read())]
if leftover:
    print("ERREUR — {{BASE_URL}} ou {{LASTMOD}} non remplacé dans :", *leftover, sep="\n  ")
    sys.exit(1)

total = sum(os.path.getsize(f) for f in files)
print(f"deploy/ prêt pour {BASE_URL} : {len(files)} fichiers, {total / 1e6:.1f} Mo")
PY
