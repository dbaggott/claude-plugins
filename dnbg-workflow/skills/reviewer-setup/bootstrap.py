#!/usr/bin/env python3
"""Bootstrap a per-developer GitHub App for the local reviewer bot.

Drives the GitHub App Manifest flow end to end, except the one browser click
GitHub requires to create any App:

  1. Build an App manifest (pull_requests:write, contents:write,
     checks:read, metadata:read; no webhook).
  2. Serve a local page that POSTs the manifest to GitHub's create-from-manifest
     URL; you click "Create GitHub App" in the browser.
  3. GitHub redirects back to this server with a temporary code.
  4. Exchange the code via POST /app-manifests/{code}/conversions for the App's
     id, slug, and private key (PEM) — returned exactly once, here.
  5. Save the key (mode 600) and config locally. The key never leaves this
     machine; the reviewer skill mints short-lived tokens from it.

Stdlib only — no third-party packages.

Example:
  # org-owned, private App (needs app-creation rights in the org):
  python3 bootstrap.py --owner-type org --org my-org
  # user-owned, public App (self-serve; an org owner approves the install):
  python3 bootstrap.py --owner-type user
"""
from __future__ import annotations

import argparse
import html
import json
import os
import pathlib
import secrets
import stat
import subprocess
import sys
import threading
import urllib.error
import urllib.request
import webbrowser
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

API_ROOT = "https://api.github.com"


def gh_login() -> str:
    """Current `gh`-authenticated user login, for a unique default App name."""
    try:
        out = subprocess.run(
            ["gh", "api", "user", "--jq", ".login"],
            capture_output=True, text=True, check=True,
        )
        return out.stdout.strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return ""


def build_manifest(name: str, redirect_url: str, public: bool) -> dict:
    return {
        "name": name,
        "url": "https://github.com/dbaggott/claude-plugins",
        "redirect_url": redirect_url,
        "public": public,
        # No hook_attributes => no webhook. The reviewer is invoked locally,
        # not driven by GitHub events.
        "default_events": [],
        # `gh pr checks` alone needs three of these, because statusCheckRollup
        # spans check runs, the workflow run each check suite points at, and
        # legacy commit statuses — a missing one fails the whole query, not the
        # node it covers. `actions` was confirmed against a live failure;
        # `statuses` is the one an Actions-only repo never exercises, and is
        # here for repos whose CI posts commit statuses instead of check runs.
        "default_permissions": _permissions(),
    }


def _permissions() -> dict:
    """The App's permission set, shared with mint-token.sh's runtime audit."""
    here = pathlib.Path(__file__).resolve().parent
    return json.loads((here / "permissions.json").read_text())["required"]


def convert_manifest(code: str) -> dict:
    """Exchange the manifest code for App credentials (no auth — code-gated)."""
    req = urllib.request.Request(
        f"{API_ROOT}/app-manifests/{code}/conversions",
        method="POST",
        data=b"",
        headers={
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "Content-Length": "0",
            "User-Agent": "reviewer-setup",
        },
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read())


def save_credentials(config_dir: Path, owner_type: str, org: str, app: dict) -> None:
    config_dir.mkdir(parents=True, exist_ok=True)
    # 0700, and chmod rather than mkdir(mode=...): that argument is masked by the
    # umask and is ignored outright when the directory already exists, which is
    # the common case on a re-run. The file modes below are not sufficient on
    # their own — a 0600 PEM inside a group-writable directory can still be
    # REPLACED, and mint-token.sh would sign a JWT with whatever it finds. It
    # refuses such a directory; this is the other half of that contract.
    config_dir.chmod(stat.S_IRWXU)
    pem_path = config_dir / "private-key.pem"
    # Create the key file restricted from the start — no world-readable window.
    # (write_text would create it at 0644-ish and only narrow it after the bytes
    # land.) The App private key is the bot's full credential.
    fd = os.open(pem_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as fh:
        fh.write(app["pem"])

    slug = app.get("slug", "")
    config = {
        "app_id": str(app["id"]),
        "slug": slug,
        "bot_login": f"{slug}[bot]" if slug else "",
        "owner_type": owner_type,
        "owner": org if owner_type == "org" else app.get("owner", {}).get("login", ""),
        "installation_id": "",  # filled after the App is installed (mint-token can also discover it)
        "html_url": app.get("html_url", ""),
    }
    config_path = config_dir / "config.json"
    config_path.write_text(json.dumps(config, indent=2) + "\n")
    config_path.chmod(stat.S_IRUSR | stat.S_IWUSR)


def run_flow(args: argparse.Namespace) -> int:
    login = gh_login()
    name = args.name or (f"agent-reviewer-{login}" if login else "agent-reviewer")
    config_dir = Path(args.config_dir).expanduser()

    # Default to user-owned + public: the only model installable on BOTH the org
    # (for org PRs) and your personal account (for personal repos). Private Apps
    # install only on their owner, so --owner-type org reviews org repos only.
    owner_type = args.owner_type or "user"
    public = owner_type == "user"

    # CSRF guard: GitHub echoes this back on the /callback redirect, so the
    # callback handler only accepts a code that came from the page we served.
    state = secrets.token_urlsafe(24)
    if owner_type == "org":
        if not args.org:
            print("--org is required for an org-owned App", file=sys.stderr)
            return 2
        create_url = f"https://github.com/organizations/{args.org}/settings/apps/new?state={state}"
    else:
        create_url = f"https://github.com/settings/apps/new?state={state}"

    result: dict = {}
    done = threading.Event()

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_):  # quiet
            pass

        def _html(self, code: int, body: str) -> None:
            self.send_response(code)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write(body.encode())

        def do_GET(self):  # noqa: N802
            parsed = urlparse(self.path)
            if parsed.path == "/":
                manifest = build_manifest(name, f"http://localhost:{args.port}/callback", public)
                # Auto-submitting form: the manifest must be POSTed to GitHub.
                # html.escape so the embedded JSON is safe in the attribute
                # regardless of manifest content (defense-in-depth).
                manifest_attr = html.escape(json.dumps(manifest), quote=True)
                self._html(200, f"""<!doctype html><html><body>
<form id="f" action="{html.escape(create_url, quote=True)}" method="post">
  <input type="hidden" name="manifest" value="{manifest_attr}">
</form>
<p>Redirecting you to GitHub to create the reviewer App
(<b>{name}</b>)&hellip; if nothing happens, click Create.</p>
<button form="f" type="submit">Create GitHub App</button>
<script>document.getElementById('f').submit();</script>
</body></html>""")
            elif parsed.path == "/callback":
                qs = parse_qs(parsed.query)
                if (qs.get("state") or [""])[0] != state:
                    self._html(400, "<p>State mismatch — possible CSRF. Setup aborted.</p>")
                    result["error"] = "state mismatch on callback"
                    done.set()
                    return
                code = (qs.get("code") or [""])[0]
                if not code:
                    self._html(400, "<p>No code in callback. Setup failed.</p>")
                    result["error"] = "no code in callback"
                    done.set()
                    return
                try:
                    app = convert_manifest(code)
                    # Validate here (not in save_credentials) so a malformed 200
                    # response fails fast with an accurate message instead of
                    # raising KeyError out of the save step and hanging main.
                    if not all(k in app for k in ("id", "pem", "slug")):
                        raise KeyError("conversion response missing id/pem/slug")
                except (urllib.error.HTTPError, urllib.error.URLError, KeyError) as exc:
                    self._html(500, f"<p>Manifest conversion failed: {html.escape(str(exc))}</p>")
                    result["error"] = f"manifest conversion failed: {exc}"
                    done.set()
                    return
                # The App now exists on GitHub. If saving its key fails (dir not
                # writable, disk full, chmod fails) the App is orphaned — say so
                # explicitly rather than dying with a traceback in main.
                try:
                    save_credentials(config_dir, owner_type, args.org or "", app)
                except OSError as exc:
                    msg = (f"App '{app.get('slug', '')}' was created on GitHub, but saving its "
                           f"credentials to {config_dir} failed ({exc}). Delete the App in its "
                           f"GitHub settings, fix the directory, and re-run setup.")
                    self._html(500, f"<p>{html.escape(msg)}</p>")
                    result["error"] = msg
                    done.set()
                    return
                result["app"] = app
                install_url = f"https://github.com/apps/{app.get('slug', '')}/installations/new"
                self._html(200, f"""<!doctype html><html><body>
<h3>Reviewer App created: {html.escape(app.get('slug', ''))}</h3>
<p>Credentials saved to {html.escape(str(config_dir))}. You can close this tab and return to the terminal.</p>
<p>Next: install it &mdash; <a href="{html.escape(install_url)}">{html.escape(install_url)}</a></p>
</body></html>""")
                done.set()
            else:
                self._html(404, "not found")

    try:
        server = HTTPServer(("localhost", args.port), Handler)
    except OSError as exc:
        print(f"Could not bind localhost:{args.port} ({exc}) — it may be in use by a "
              f"previous run. Retry with --port <other>.", file=sys.stderr)
        return 1
    threading.Thread(target=server.serve_forever, daemon=True).start()

    open_url = f"http://localhost:{args.port}/"
    print(f"Opening {open_url} — complete the App creation in your browser.", file=sys.stderr)
    if not args.no_browser:
        webbrowser.open(open_url)

    if not done.wait(timeout=args.timeout):
        print(f"Timed out after {args.timeout}s waiting for the GitHub callback.", file=sys.stderr)
        server.shutdown()
        return 1
    server.shutdown()

    if "error" in result or "app" not in result:
        print(f"Setup failed: {result.get('error', 'unknown error')}", file=sys.stderr)
        return 1

    app = result["app"]
    slug = app.get("slug", "")
    print(json.dumps({
        "app_id": str(app["id"]),
        "slug": slug,
        "bot_login": f"{slug}[bot]" if slug else "",
        "config_dir": str(config_dir),
        "install_url": f"https://github.com/apps/{slug}/installations/new",
    }, indent=2))
    return 0


def main() -> int:
    p = argparse.ArgumentParser(description="Bootstrap the local reviewer GitHub App.")
    p.add_argument("--owner-type", choices=["org", "user"], default=None,
                   help="user (default): user-owned public App — installable on the org AND "
                        "your personal account, so it reviews both. "
                        "org: org-owned private App — org repos only (no personal repos).")
    p.add_argument("--org", default=None,
                   help="organization login; required only with --owner-type org")
    p.add_argument("--name", help="App name (default agent-reviewer-<your-login>; must be globally unique)")
    p.add_argument("--port", type=int, default=8765, help="localhost callback port")
    p.add_argument("--timeout", type=int, default=600, help="seconds to wait for the browser callback")
    p.add_argument("--no-browser", action="store_true", help="don't auto-open the browser")
    p.add_argument("--config-dir",
                   default=os.environ.get("DNBG_REVIEWER_CONFIG_DIR")
                   or str(Path(os.environ.get("XDG_CONFIG_HOME") or (Path.home() / ".config"))
                          / "dnbg" / "reviewer"),
                   help="where to store credentials")
    return run_flow(p.parse_args())


if __name__ == "__main__":
    sys.exit(main())
