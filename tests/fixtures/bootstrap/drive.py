"""Run bootstrap.py's main() with GitHub replaced and the browser click driven.

  python3 drive.py <bootstrap-dir> <manifest-log> [bootstrap args…]

Each "browser open" fetches the local page, records the manifest it would POST,
and follows GitHub's redirect back with the page's own state. The conversion
answers as GitHub would, with an App named after the manifest.
"""
import json
import re
import sys
import threading
import urllib.request
from html import unescape

sys.path.insert(0, sys.argv[1])
import bootstrap  # noqa: E402

LOG = sys.argv[2]
seen = {}


def fake_open(url):
    def click():
        page = urllib.request.urlopen(url, timeout=10).read().decode()
        state = re.search(r"state=([^\"&]+)", page).group(1)
        manifest = json.loads(unescape(re.search(r'name="manifest" value="([^"]*)"', page).group(1)))
        with open(LOG, "a") as fh:
            fh.write(json.dumps(manifest) + "\n")
        seen["name"] = manifest["name"]
        urllib.request.urlopen(f"{url}callback?state={state}&code=c", timeout=10).read()
    threading.Thread(target=click, daemon=True).start()
    return True


def fake_convert(code):
    name = seen["name"]
    return {"id": len(name), "pem": f"PEM for {name}", "slug": name, "owner": {"login": "tester"}}


bootstrap.webbrowser.open = fake_open
bootstrap.convert_manifest = fake_convert
bootstrap.gh_login = lambda: "tester"
sys.argv = ["bootstrap.py"] + sys.argv[3:]
sys.exit(bootstrap.main())
