#!/usr/bin/env python3
"""Bootstrap per-developer GitHub Apps for the agent roles.

Creates one App per chosen role (`reviewer`, and any other role defined under
`dnbg-workflow/roles/`), one after another, by driving the GitHub App Manifest
flow end to end except the one browser click GitHub requires to create any App:

  1. Build the role's App manifest from `roles/<role>/permissions.json` (no
     webhook).
  2. Serve a local page that POSTs the manifest to GitHub's create-from-manifest
     URL; you click "Create GitHub App" in the browser.
  3. GitHub redirects back to this server with a temporary code.
  4. Exchange the code via POST /app-manifests/{code}/conversions for the App's
     id, slug, and private key (PEM) — returned exactly once, here.
  5. Save the key (mode 600) and config in the role's own config dir. The key
     never leaves this machine; `as-role.sh` mints short-lived tokens from it.

Stdlib only — no third-party packages.

Example:
  # every role not yet set up, user-owned public Apps:
  python3 bootstrap.py
  # just the reviewer, org-owned private App (needs app-creation rights there):
  python3 bootstrap.py --roles reviewer --owner-type org --org my-org
"""
from __future__ import annotations

import argparse
import html
import json
import os
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
ROLES_DIR = Path(__file__).resolve().parent.parent.parent / "roles"


def defined_roles() -> list[str]:
    """Every role with data under roles/, in name order."""
    return sorted(d.name for d in ROLES_DIR.iterdir() if (d / "permissions.json").is_file())


def default_config_dir(role: str) -> Path:
    """DNBG_<ROLE>_CONFIG_DIR, else ~/.config/dnbg/<role> — as lib-role.sh reads it."""
    env = os.environ.get(f"DNBG_{role.upper().replace('-', '_')}_CONFIG_DIR")
    base = Path(os.environ.get("XDG_CONFIG_HOME") or (Path.home() / ".config"))
    return Path(env).expanduser() if env else base / "dnbg" / role


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


def build_manifest(role: str, name: str, redirect_url: str, public: bool) -> dict:
    return {
        "name": name,
        "url": "https://github.com/dbaggott/claude-plugins",
        "redirect_url": redirect_url,
        "public": public,
        # No hook_attributes => no webhook. Every role is driven locally, not
        # by GitHub events.
        "default_events": [],
        # `gh pr checks` alone needs three of these, because statusCheckRollup
        # spans check runs, the workflow run each check suite points at, and
        # legacy commit statuses — a missing one fails the whole query, not the
        # node it covers. `actions` was confirmed against a live failure;
        # `statuses` is the one an Actions-only repo never exercises, and is
        # here for repos whose CI posts commit statuses instead of check runs.
        "default_permissions": role_permissions(role),
    }


def role_permissions(role: str) -> dict:
    """The role's App permission set, shared with mint-token.sh's runtime audit."""
    return json.loads((ROLES_DIR / role / "permissions.json").read_text())["required"]


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


def run_flow(args: argparse.Namespace, role: str, name: str, config_dir: Path) -> dict | None:
    """Create one role's App. Returns its summary, or None after printing why not."""
    # Default to user-owned + public: the only model installable on BOTH the org
    # (for org PRs) and your personal account (for personal repos). Private Apps
    # install only on their owner, so --owner-type org covers org repos only.
    owner_type = args.owner_type or "user"
    public = owner_type == "user"

    # CSRF guard: GitHub echoes this back on the /callback redirect, so the
    # callback handler only accepts a code that came from the page we served.
    state = secrets.token_urlsafe(24)
    if owner_type == "org":
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
                manifest = build_manifest(role, name, f"http://localhost:{args.port}/callback", public)
                # Auto-submitting form: the manifest must be POSTed to GitHub.
                # html.escape so the embedded JSON is safe in the attribute
                # regardless of manifest content (defense-in-depth).
                manifest_attr = html.escape(json.dumps(manifest), quote=True)
                self._html(200, f"""<!doctype html><html><body>
<form id="f" action="{html.escape(create_url, quote=True)}" method="post">
  <input type="hidden" name="manifest" value="{manifest_attr}">
</form>
<p>Redirecting you to GitHub to create the {html.escape(role)} App
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
<h3>{html.escape(role)} App created: {html.escape(app.get('slug', ''))}</h3>
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
        return None
    threading.Thread(target=server.serve_forever, daemon=True).start()

    open_url = f"http://localhost:{args.port}/"
    print(f"Opening {open_url} — complete the {role} App's creation in your browser.", file=sys.stderr)
    if not args.no_browser:
        webbrowser.open(open_url)

    if not done.wait(timeout=args.timeout):
        print(f"Timed out after {args.timeout}s waiting for the GitHub callback.", file=sys.stderr)
        server.shutdown()
        server.server_close()
        return None
    server.shutdown()
    # Released here, so the next role's flow can bind the same port.
    server.server_close()

    if "error" in result or "app" not in result:
        print(f"Setup failed for {role}: {result.get('error', 'unknown error')}", file=sys.stderr)
        return None

    app = result["app"]
    slug = app.get("slug", "")
    return {
        "role": role,
        "app_id": str(app["id"]),
        "slug": slug,
        "bot_login": f"{slug}[bot]" if slug else "",
        "config_dir": str(config_dir),
        "install_url": f"https://github.com/apps/{slug}/installations/new",
    }


def choose_roles(requested: str | None) -> list[str]:
    """The named roles, or by default every defined role with no config yet."""
    known = defined_roles()
    if requested:
        roles = [r.strip() for r in requested.split(",") if r.strip()]
        unknown = [r for r in roles if r not in known]
        if unknown:
            raise SystemExit(f"unknown role(s) {', '.join(unknown)}; defined: {', '.join(known)}")
        return roles
    return [r for r in known if not (default_config_dir(r) / "config.json").exists()]


def run(args: argparse.Namespace) -> int:
    roles = choose_roles(args.roles)
    if not roles:
        print("Every role already has an App set up; name one with --roles to create "
              "another.", file=sys.stderr)
        return 0
    if len(roles) > 1 and (args.name or args.config_dir):
        print("--name and --config-dir apply to one role; pass --roles <one role>.", file=sys.stderr)
        return 2
    if (args.owner_type or "user") == "org" and not args.org:
        print("--org is required for an org-owned App", file=sys.stderr)
        return 2

    login = gh_login()
    created: list[dict] = []
    status = 0
    for role in roles:
        name = args.name or (f"agent-{role}-{login}" if login else f"agent-{role}")
        config_dir = Path(args.config_dir).expanduser() if args.config_dir else default_config_dir(role)
        summary = run_flow(args, role, name, config_dir)
        if summary is None:
            status = 1
            left = roles[roles.index(role) + 1:]
            if left:
                print(f"Stopped before: {', '.join(left)}.", file=sys.stderr)
            break
        created.append(summary)
    print(json.dumps(created, indent=2))
    return status


def main() -> int:
    p = argparse.ArgumentParser(description="Bootstrap the agent roles' GitHub Apps.")
    p.add_argument("--roles",
                   help="comma-separated roles to create Apps for (default: every role "
                        "under roles/ with no config.json yet)")
    p.add_argument("--owner-type", choices=["org", "user"], default=None,
                   help="user (default): user-owned public App — installable on the org AND "
                        "your personal account, so it covers both. "
                        "org: org-owned private App — org repos only (no personal repos).")
    p.add_argument("--org", default=None,
                   help="organization login; required only with --owner-type org")
    p.add_argument("--name", help="App name, with one role (default agent-<role>-<your-login>; "
                                  "must be globally unique)")
    p.add_argument("--port", type=int, default=8765, help="localhost callback port")
    p.add_argument("--timeout", type=int, default=600, help="seconds to wait for the browser callback")
    p.add_argument("--no-browser", action="store_true", help="don't auto-open the browser")
    p.add_argument("--config-dir",
                   help="where to store credentials, with one role "
                        "(default DNBG_<ROLE>_CONFIG_DIR, else ~/.config/dnbg/<role>)")
    return run(p.parse_args())


if __name__ == "__main__":
    sys.exit(main())
