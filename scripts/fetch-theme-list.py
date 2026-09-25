#!/usr/bin/env python3
"""Regenerate themes.json.

Sources, merged by install name (first source wins on duplicates):
  1. the stock themes installed on this machine
  2. the community list on https://omarchy.org/themes
  3. optionally the Omarchy theme registry feed (--registry), which lists
     far more themes than omarchy.org does

Before merging, every GitHub URL is checked for a rename: a renamed repository
answers 301 on the web with its new address, so the same theme listed under an
old name on omarchy.org and a new name in the registry becomes one entry (the
new name, with the old one kept in "renamed_from"). --no-resolve skips this.

Usage:
  scripts/fetch-theme-list.py                    # stock + omarchy.org
  scripts/fetch-theme-list.py --registry         # also the registry (300+ themes)
  scripts/fetch-theme-list.py --from page.html   # parse a saved copy of omarchy.org/themes
"""
import argparse
import concurrent.futures
import datetime as dt
import glob
import html
import json
import os
import re
import sys
import urllib.error
import urllib.request

SITE_URL = "https://omarchy.org/themes"
REGISTRY_URL = "https://andreas-bylund.github.io/omarchy-theme-registry/index.json"
OMARCHY_PATH = os.environ.get("OMARCHY_PATH", "/usr/share/omarchy")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.environ.get("OTP_OUT", os.path.join(ROOT, "out"))
UA = {"User-Agent": "omarchy-theme-photograph"}
GITHUB_REPO = re.compile(r"^https?://(?:www\.)?github\.com/([^/]+)/([^/?#]+?)(?:\.git)?/?$")


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


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None  # surface 3xx as HTTPError instead of following it


_NO_REDIRECT = urllib.request.build_opener(_NoRedirect)


def resolve_repo(url: str):
    """Return (url, status) after asking github.com whether the repo moved.

    status is "ok", "renamed" (url is the new address), "missing" (404) or
    "unknown" (network trouble; url is unchanged). Non-GitHub URLs are "ok".
    """
    m = GITHUB_REPO.match(url.strip())
    if not m:
        return url, "ok"
    req = urllib.request.Request(f"https://github.com/{m.group(1)}/{m.group(2)}", method="HEAD", headers=UA)
    try:
        with _NO_REDIRECT.open(req, timeout=20):
            return url, "ok"
    except urllib.error.HTTPError as e:
        if e.code in (301, 302, 307, 308):
            t = GITHUB_REPO.match(e.headers.get("Location", ""))
            if t:
                return f"https://github.com/{t.group(1)}/{t.group(2)}", "renamed"
            return url, "unknown"
        return url, "missing" if e.code == 404 else "unknown"
    except (urllib.error.URLError, OSError, TimeoutError):
        return url, "unknown"


def resolve_renames(themes, out_dir=OUT_DIR):
    """Rewrite repo and install_name of renamed repos so duplicates merge."""
    urls = sorted({t["repo"] for t in themes if t.get("repo")})
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        results = dict(zip(urls, pool.map(resolve_repo, urls)))
    counts = {"renamed": 0, "missing": 0, "unknown": 0}
    for t in themes:
        url = t.get("repo")
        if not url:
            continue
        new_url, status = results[url]
        if status == "ok":
            continue
        counts[status] += 1
        if status == "renamed":
            old_name = t["install_name"]
            t["renamed_from"] = url
            t["repo"] = new_url
            t["install_name"] = theme_name_from_repo(new_url)
            print(f"renamed: {url} -> {new_url} ({t['source']})", file=sys.stderr)
            if old_name != t["install_name"] and os.path.isfile(os.path.join(out_dir, old_name, "meta.json")):
                print(f"  ! {out_dir}/{old_name}/ was photographed under the old name; "
                      f"remove it, or the site keeps showing the theme twice", file=sys.stderr)
        elif status == "missing":
            print(f"missing: {url} answers 404 ({t['source']})", file=sys.stderr)
    print(f"checked {len(urls)} repos on github.com: {counts['renamed']} renamed, "
          f"{counts['missing']} missing, {counts['unknown']} unreachable", file=sys.stderr)


def title_case(slug: str) -> str:
    return " ".join(w[:1].upper() + w[1:] for w in slug.split("-"))


def fetch(url: str) -> str:
    req = urllib.request.Request(url, headers=UA)
    return urllib.request.urlopen(req, timeout=30).read().decode("utf-8")


def _site_theme(name, slug, repo):
    return {
        "name": name,
        "slug": slug,
        "repo": repo,
        "install_name": theme_name_from_repo(repo),
        "stock": False,
        "source": "omarchy.org",
    }


def parse_site(src: str):
    themes = []
    # Current omarchy.org/themes: a grid of <li><a href=repo><img .../><span>Name</span>
    for m in re.finditer(
        r'<a href="([^"]+)"[^>]*>\s*'
        r'<img src="/assets/themes/([^"]+)\.webp"[^>]*>\s*'
        r'<span[^>]*>([^<]+)</span>',
        src,
        re.S,
    ):
        repo, slug, caption = m.group(1), m.group(2), m.group(3)
        themes.append(_site_theme(html.unescape(caption.strip()), slug, repo))
    if themes:
        return themes

    # Older markup used <figure class="themes__theme">
    for fig in re.findall(r'<figure class="themes__theme[^"]*">(.*?)</figure>', src, re.S):
        m = re.search(r'<a href="([^"]+)"><img src="/assets/themes/([^"]+)\.webp"', fig)
        c = re.search(r"<figcaption><a href=\"[^\"]+\">([^<]+)</a>", fig)
        if not m:
            continue
        repo, slug = m.group(1), m.group(2)
        themes.append(_site_theme(html.unescape(c.group(1)) if c else title_case(slug), slug, repo))
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
    ap.add_argument("--no-resolve", action="store_true",
                    help="do not ask github.com whether repos were renamed (offline; duplicates may survive)")
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

    community = []
    if not args.no_site:
        src = open(args.src, encoding="utf-8").read() if args.src else fetch(SITE_URL)
        site = parse_site(src)
        if not site:
            sys.exit("no themes found on omarchy.org/themes; has the page layout changed?")
        community += site
        sources.append(SITE_URL)

    if args.registry:
        community += registry_themes(args.registry)
        sources.append(args.registry)

    # Same repo under two names (one source still has the old name) must
    # collapse into one entry, or it gets photographed and listed twice.
    if community and not args.no_resolve:
        resolve_renames(community)
    add(community)

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
