#!/usr/bin/env python3
"""Regenerate themes.json.

Sources, merged by install name (first source wins on duplicates):
  1. the stock themes installed on this machine
  2. the community list on https://omarchy.org/themes
  3. optionally the Omarchy theme registry feed (--registry), which lists
     far more themes than omarchy.org does

Usage:
  scripts/fetch-theme-list.py                    # stock + omarchy.org
  scripts/fetch-theme-list.py --registry         # also the registry (300+ themes)
  scripts/fetch-theme-list.py --from page.html   # parse a saved copy of omarchy.org/themes
"""
import argparse
import datetime as dt
import glob
import html
import json
import os
import re
import sys
import urllib.request

SITE_URL = "https://omarchy.org/themes"
REGISTRY_URL = "https://andreas-bylund.github.io/omarchy-theme-registry/index.json"
OMARCHY_PATH = os.environ.get("OMARCHY_PATH", "/usr/share/omarchy")
UA = {"User-Agent": "omarchy-theme-photograph"}


def theme_name_from_repo(url: str) -> str:
    """Mirror the rule omarchy-theme-install uses to name a cloned theme."""
    path = url
    if "://" not in path and ":" in path and "/" not in path.split(":", 1)[0]:
        path = path.split(":", 1)[1]
    name = os.path.basename(path.rstrip("/"))
    if name.endswith(".git"):
        name = name[:-4]
    name = re.sub(r"^omarchy-", "", name)
    name = re.sub(r"-theme$", "", name)
    return name.lower()


def title_case(slug: str) -> str:
    return " ".join(w[:1].upper() + w[1:] for w in slug.split("-"))


def fetch(url: str) -> str:
    req = urllib.request.Request(url, headers=UA)
    return urllib.request.urlopen(req, timeout=30).read().decode("utf-8")


def parse_site(src: str):
    themes = []
    for fig in re.findall(r'<figure class="themes__theme[^"]*">(.*?)</figure>', src, re.S):
        m = re.search(r'<a href="([^"]+)"><img src="/assets/themes/([^"]+)\.webp"', fig)
        c = re.search(r"<figcaption><a href=\"[^\"]+\">([^<]+)</a>", fig)
        if not m:
            continue
        repo, slug = m.group(1), m.group(2)
        themes.append({
            "name": html.unescape(c.group(1)) if c else title_case(slug),
            "slug": slug,
            "repo": repo,
            "install_name": theme_name_from_repo(repo),
            "stock": False,
            "source": "omarchy.org",
        })
    return themes


def registry_themes(url: str):
    doc = json.loads(fetch(url))
    themes = []
    for t in doc.get("themes", []):
        repo = t.get("repo")
        if not repo or t.get("archived"):
            continue
        themes.append({
            "name": t.get("name") or title_case(t["slug"]),
            "slug": t["slug"],
            "repo": repo,
            "install_name": theme_name_from_repo(repo),
            "stock": False,
            "source": "registry",
        })
    return themes


def stock_themes():
    out = []
    for path in sorted(glob.glob(os.path.join(OMARCHY_PATH, "themes", "*", ""))):
        slug = os.path.basename(path.rstrip("/"))
        out.append({"name": title_case(slug), "slug": slug, "repo": None, "install_name": slug, "stock": True, "source": "stock"})
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--from", dest="src", help="parse a saved copy of omarchy.org/themes instead of downloading")
    ap.add_argument("--registry", nargs="?", const=REGISTRY_URL, default=None, metavar="URL",
                    help="also include the Omarchy theme registry feed (default URL when given without a value)")
    ap.add_argument("--no-site", action="store_true", help="skip omarchy.org/themes")
    ap.add_argument("--no-stock", action="store_true", help="leave out the stock themes of this machine")
    ap.add_argument("--out", default=os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "themes.json"))
    args = ap.parse_args()

    sources = []
    merged = {}

    def add(themes):
        for t in themes:
            merged.setdefault(t["install_name"], t)

    if not args.no_stock:
        add(stock_themes())
        sources.append("stock")

    if not args.no_site:
        src = open(args.src, encoding="utf-8").read() if args.src else fetch(SITE_URL)
        site = parse_site(src)
        if not site:
            sys.exit("no themes found on omarchy.org/themes; has the page layout changed?")
        add(site)
        sources.append(SITE_URL)

    if args.registry:
        add(registry_themes(args.registry))
        sources.append(args.registry)

    themes = sorted(merged.values(), key=lambda t: (not t["stock"], t["name"].lower()))
    doc = {
        "sources": sources,
        "generated_at": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "count": len(themes),
        "themes": themes,
    }
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(doc, f, indent=2, ensure_ascii=False)
        f.write("\n")
    community = sum(1 for t in themes if not t["stock"])
    print(f"wrote {args.out}: {len(themes)} themes ({community} community) from {', '.join(sources)}")


if __name__ == "__main__":
    main()
