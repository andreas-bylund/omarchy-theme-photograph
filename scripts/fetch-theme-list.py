#!/usr/bin/env python3
"""Regenerate themes.json from the community list on https://omarchy.org/themes
plus the stock themes found on this machine.

Usage: scripts/fetch-theme-list.py [--from FILE.html] [--out themes.json] [--no-stock]
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

URL = "https://omarchy.org/themes"
OMARCHY_PATH = os.environ.get("OMARCHY_PATH", "/usr/share/omarchy")


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


def parse(src: str):
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
        })
    return themes


def stock_themes():
    out = []
    for path in sorted(glob.glob(os.path.join(OMARCHY_PATH, "themes", "*", ""))):
        slug = os.path.basename(path.rstrip("/"))
        out.append({"name": title_case(slug), "slug": slug, "repo": None, "install_name": slug, "stock": True})
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--from", dest="src", help="parse a saved copy of the page instead of downloading")
    ap.add_argument("--out", default=os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "themes.json"))
    ap.add_argument("--no-stock", action="store_true", help="leave out the stock themes of this machine")
    args = ap.parse_args()

    if args.src:
        src = open(args.src, encoding="utf-8").read()
    else:
        req = urllib.request.Request(URL, headers={"User-Agent": "omarchy-theme-photograph"})
        src = urllib.request.urlopen(req, timeout=30).read().decode("utf-8")

    community = parse(src)
    if not community:
        sys.exit("no themes found; has the page layout changed?")
    themes = ([] if args.no_stock else stock_themes()) + community
    doc = {
        "source": URL,
        "generated_at": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "count": len(themes),
        "themes": themes,
    }
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(doc, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"wrote {args.out}: {len(themes)} themes ({len(community)} community)")


if __name__ == "__main__":
    main()
