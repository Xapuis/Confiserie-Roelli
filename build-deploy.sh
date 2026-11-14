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
#  {{LASTMOD}} (sitemap.xml) devient, pour chaque page, la date de son
#  dernier commit (ou la date du jour si elle a des modifications en cours).
#
#  Utilisation :  ./build-deploy.sh
#  Puis envoyer le CONTENU de deploy/ à la racine du site (FTP / gestionnaire
#  de fichiers Infomaniak), en remplaçant l'existant.
#
#  S'arrête avec une erreur si une page référence un fichier introuvable,
#  ou si les horaires des données structurées (index.html, magasins.html,
#  tilleuls.html) ou de llms.txt ne concordent pas.
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
          "robots.txt", "sitemap.xml", "llms.txt"]
WITH_BASE_URL = (".html", ".txt", ".xml")
OUT = "deploy"

# ── Horaires : les copies doivent concorder ─────────────────────────────────
# Les horaires des magasins sont écrits à la main dans le JSON-LD de
# index.html et magasins.html (5 magasins) et de tilleuls.html (Les Tilleuls),
# et dans llms.txt. On s'arrête si une copie a été oubliée.
import json

def jsonld_nodes(page):
    with open(page, encoding="utf-8") as f:
        text = f.read()
    nodes = {}
    for block in re.findall(r'<script type="application/ld\+json">(.*?)</script>', text, re.S):
        data = json.loads(block)
        for n in data.get("@graph", [data]):
            if "openingHoursSpecification" in n:
                nodes[n["@id"]] = n
    return nodes

def hours(node):
    return sorted((tuple(sorted(o["dayOfWeek"])), o["opens"], o["closes"])
                  for o in node["openingHoursSpecification"])

errors = []
ref = jsonld_nodes("magasins.html")
for page in ("index.html", "tilleuls.html"):
    other = jsonld_nodes(page)
    if page == "index.html" and set(other) != set(ref):
        errors.append("index.html et magasins.html ne décrivent pas les mêmes magasins")
    for node_id, node in other.items():
        if node_id not in ref:
            errors.append(f"{page} : « {node['name']} » absent de magasins.html")
        elif hours(node) != hours(ref[node_id]):
            errors.append(f"{page} : horaires de « {node['name']} » différents de magasins.html")
if not any(i.endswith("#porrentruy-tilleuls") for i in jsonld_nodes("tilleuls.html")):
    errors.append("tilleuls.html : données structurées des Tilleuls introuvables")

# llms.txt : chaque magasin (repéré par sa rue) doit afficher ses plages horaires.
with open("llms.txt", encoding="utf-8") as f:
    llms = f.read()
for node in ref.values():
    street = node["address"]["streetAddress"]
    m = re.search(r"^- .*" + re.escape(street) + r".*\n(.*)$", llms, re.M)
    if not m:
        errors.append(f"llms.txt : magasin « {street} » introuvable")
        continue
    for o in node["openingHoursSpecification"]:
        if f"{o['opens']}–{o['closes']}" not in m.group(1):
            errors.append(f"llms.txt : « {street} » n'affiche pas {o['opens']}–{o['closes']}")

if errors:
    print("ERREUR — horaires incohérents :", *errors, sep="\n  ")
    sys.exit(1)

# ── Sitemap : date de dernière modification réelle de chaque page ───────────
# Date du dernier commit qui a touché la page ; date du jour si la page a des
# modifications pas encore enregistrées dans git (ou si git est absent).
import subprocess

def page_lastmod(page):
    try:
        dirty = subprocess.run(["git", "status", "--porcelain", "--", page],
                               capture_output=True, text=True, check=True).stdout.strip()
        date = subprocess.run(["git", "log", "-1", "--format=%cs", "--", page],
                              capture_output=True, text=True, check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return TODAY
    return TODAY if dirty or not date else date

def sitemap_with_dates(text):
    def repl(m):
        path = m.group(1) or "index.html"
        return m.group(0).replace("{{LASTMOD}}", page_lastmod(path))
    return re.sub(r"<loc>\{\{BASE_URL\}\}/([^<]*)</loc>\s*<lastmod>\{\{LASTMOD\}\}</lastmod>",
                  repl, text)

refs = set()

def add(url):
    url = html.unescape(url.strip()).split("#")[0].split("?")[0]
    if not url or re.match(r"^(https?:|//|mailto:|tel:|data:|\{\{)", url):
        return
    url = url.lstrip("/")
    if url:                       # href="/" : la racine du site, rien à copier
        refs.add(url)

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
            text = src.read()
        if f == "sitemap.xml":
            text = sitemap_with_dates(text)
        text = text.replace("{{BASE_URL}}", BASE_URL).replace("{{LASTMOD}}", TODAY)
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
