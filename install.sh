#!/usr/bin/env bash
# One command, one credential, a working environment.
#
#   curl -fsSL https://raw.githubusercontent.com/when2buy/dev-setup/main/install.sh | bash
#
# That is the whole onboarding. This script needs NOTHING from you except the one
# credential you were handed, and nothing from us except this public file: no private
# repo, no clone, no checkout, no prior tooling. It:
#
#   1. installs the Infisical CLI into ~/.local/bin  (a single static binary, no root)
#   2. takes your credential and stores it in ~/.secrets/infisical.env, mode 600
#   3. installs `keys`, the loader that pulls this team's API keys into a shell
#   4. adds one line to your shell rc so every new shell has them
#   5. proves it worked by fetching for real and printing key NAMES and lengths
#
# It never prints a secret value, and it is safe to re-run — every step is idempotent.
#
# WHAT THE CREDENTIAL IS. It is not an API key. It is a door card: a machine identity's
# `<client id>:<client secret>` pair, which buys a 2-hour token, which fetches the actual
# keys. So the keys themselves are never mailed to anyone and never sit on your disk. When
# we rotate one, you do nothing — your next fetch is the new value.
#
# WHY THIS FILE IS PUBLIC. It contains no secret. The project ids below are room numbers:
# they say where the keys live, not how to open the door. Without a card they are useless,
# and every card is individually revocable. Keeping the installer public is the point —
# a newcomer with zero access can still run it.
set -euo pipefail

# ------------------------------------------------------------------ knobs
RAW="${TEAM_SETUP_RAW:-https://raw.githubusercontent.com/when2buy/dev-setup/main}"
CLI_VERSION="${INFISICAL_CLI_VERSION:-0.43.129}"   # pinned on purpose; see README
BIN="${TEAM_SETUP_BIN:-$HOME/.local/bin}"
SHARE="${TEAM_SETUP_SHARE:-$HOME/.local/share/team-keys}"
CARD="${TEAM_SETUP_CARD:-$HOME/.secrets/infisical.env}"
PROFILES="${TEAM_SETUP_PROFILES:-paper}"           # loaded in every new shell
EDIT_RC=1
FETCH=1

while [ $# -gt 0 ]; do
    case "$1" in
        --profiles) PROFILES="$2"; shift ;;
        --no-rc)    EDIT_RC=0 ;;
        --card-only) FETCH=0; EDIT_RC=0 ;;
        -h|--help)  sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) printf 'install.sh: unknown option %s\n' "$1" >&2; exit 2 ;;
    esac
    shift
done

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
ok()   { printf '    \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '    \033[33m!\033[0m %s\n' "$*"; }
die()  { printf '\n\033[31mFAILED\033[0m %s\n' "$*" >&2; exit 1; }

# ------------------------------------------------------------------ 0. can we even run
step "Checking what this machine already has"
for c in curl tar; do command -v "$c" >/dev/null 2>&1 || die "$c is required but missing"; done
case "$(uname -s)" in
    Linux)  OS=linux ;;
    Darwin) OS=darwin ;;
    *) die "unsupported OS $(uname -s) — install the Infisical CLI by hand, then re-run" ;;
esac
case "$(uname -m)" in
    x86_64|amd64) ARCH=amd64 ;;
    arm64|aarch64) ARCH=arm64 ;;
    *) die "unsupported CPU $(uname -m)" ;;
esac
ok "$OS/$ARCH"

# ------------------------------------------------------------------ 1. the CLI
step "Installing the Infisical CLI"
have_cli() { command -v infisical >/dev/null 2>&1 || [ -x "$BIN/infisical" ]; }
if have_cli; then
    ok "already installed: $("${BIN}/infisical" --version 2>/dev/null || infisical --version)"
else
    mkdir -p "$BIN"
    # mktemp obeys TMPDIR, and a stale TMPDIR pointing at a directory that no longer
    # exists is common on boxes whose scratch disk is recreated. Failing here would look
    # like "the download broke" rather than "your TMPDIR is gone", so drop it instead.
    [ -n "${TMPDIR:-}" ] && [ ! -d "$TMPDIR" ] && { warn "TMPDIR=$TMPDIR does not exist; using /tmp"; unset TMPDIR; }
    tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
    url="https://github.com/Infisical/cli/releases/download/v${CLI_VERSION}/cli_${CLI_VERSION}_${OS}_${ARCH}.tar.gz"
    printf '    downloading %s … (~56 MB)\n' "cli_${CLI_VERSION}_${OS}_${ARCH}.tar.gz"
    curl -fsSL -o "$tmp/cli.tgz" "$url" || die "download failed: $url"
    tar xzf "$tmp/cli.tgz" -C "$tmp" infisical || die "tarball has no infisical binary"
    install -m 755 "$tmp/infisical" "$BIN/infisical"
    ok "$BIN/infisical  ($("$BIN/infisical" --version))"
fi
case ":$PATH:" in *":$BIN:"*) ;; *) PATH="$BIN:$PATH"; warn "$BIN was not on PATH; added for this run and in your shell rc" ;; esac

# ------------------------------------------------------------------ 2. the card
step "Storing your credential"
# Accept it three ways, in this order: already in the environment (for scripted installs),
# a single `id:secret` string, or a prompt. The prompt reads /dev/tty on purpose — this
# script is normally piped into bash, so stdin is the script itself, not the keyboard.
if [ -n "${INFISICAL_CLIENT_ID:-}" ] && [ -n "${INFISICAL_CLIENT_SECRET:-}" ]; then
    CID="$INFISICAL_CLIENT_ID"; CSEC="$INFISICAL_CLIENT_SECRET"
    ok "taken from the environment"
elif [ -n "${TEAM_KEY:-}" ]; then
    CID="${TEAM_KEY%%:*}"; CSEC="${TEAM_KEY#*:}"
    ok "taken from \$TEAM_KEY"
elif [ -r "$CARD" ] && grep -q CLIENT_SECRET "$CARD"; then
    ok "reusing the card already at $CARD"
    # shellcheck disable=SC1090
    . "$CARD"; CID="${INFISICAL_CLIENT_ID:-}"; CSEC="${INFISICAL_CLIENT_SECRET:-}"
else
    [ -r /dev/tty ] || die "no credential given and no terminal to ask on — re-run with TEAM_KEY=<id>:<secret>"
    printf '\n    Paste the credential you were handed (it looks like <uuid>:<long string>).\n'
    printf '    Nothing will appear as you type or paste. Press Enter when done.\n\n'
    printf '    credential: '
    IFS= read -rs TEAM_KEY < /dev/tty || true
    printf '\n'
    [ -n "${TEAM_KEY:-}" ] || die "nothing pasted"
    case "$TEAM_KEY" in
        *:*) CID="${TEAM_KEY%%:*}"; CSEC="${TEAM_KEY#*:}" ;;
        *)   die "that does not look like <id>:<secret> — it should have a colon in it" ;;
    esac
fi
[ -n "${CID:-}" ] && [ -n "${CSEC:-}" ] || die "credential is incomplete"
# Report shape only. Printing a length is enough to catch a truncated paste, and it is
# the most that may ever be printed about a live secret.
ok "client id ${#CID} chars, secret ${#CSEC} chars"

# ------------------------------------------------------------------ 3. does it work
step "Checking the credential against Infisical"
TOKEN="$(infisical login --method=universal-auth --client-id="$CID" \
         --client-secret="$CSEC" --plain --silent 2>/dev/null || true)"
[ -n "$TOKEN" ] || die "Infisical rejected it. Most likely: a truncated paste, or the
credential has been revoked or expired. Ask for a fresh link — they are single-view, so
a link someone already opened cannot be reused."
ok "accepted; got a session token of ${#TOKEN} chars (it expires in 2 hours)"

install -d -m 700 "$(dirname "$CARD")"
umask 077
cat > "$CARD" <<EOF
# This team's Infisical door card. NOT an API key — it buys a 2h token that fetches the
# real keys. Written by install.sh on $(date -u +%Y-%m-%dT%H:%M:%SZ).
# Never commit this file. Never paste these two lines into a chat, an issue, or an AI tool.
export INFISICAL_CLIENT_ID="$CID"
export INFISICAL_CLIENT_SECRET="$CSEC"
EOF
chmod 600 "$CARD"
ok "$CARD  (mode $(stat -c %a "$CARD" 2>/dev/null || stat -f %Lp "$CARD"))"

# ------------------------------------------------------------------ 4. the loader
step "Installing the \`keys\` loader"
install -d -m 755 "$SHARE"
curl -fsSL -o "$SHARE/keys.sh.new" "$RAW/keys.sh" || die "could not fetch $RAW/keys.sh"
grep -q '^keys()' "$SHARE/keys.sh.new" || die "downloaded keys.sh looks wrong (a captive portal?)"
mv -f "$SHARE/keys.sh.new" "$SHARE/keys.sh"
ok "$SHARE/keys.sh"

if [ "$EDIT_RC" -eq 1 ]; then
    # Write the path with a literal $HOME where possible, so the line keeps working if the
    # home directory is ever remounted somewhere else (containers do this routinely).
    case "$SHARE" in "$HOME"/*) RC_SHARE="\$HOME/${SHARE#"$HOME"/}" ;; *) RC_SHARE="$SHARE" ;; esac
    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
        [ -e "$rc" ] || { [ "$rc" = "$HOME/.bashrc" ] || continue; : > "$rc"; }
        # Replace our own block rather than appending a second copy.
        if grep -q '# >>> team-keys >>>' "$rc" 2>/dev/null; then
            sed -i.team-keys-bak '/# >>> team-keys >>>/,/# <<< team-keys <<</d' "$rc"
        fi
        cat >> "$rc" <<EOF
# >>> team-keys >>>   (managed by when2buy/dev-setup install.sh — edit KEYS_AUTO freely)
case ":\$PATH:" in *":\$HOME/.local/bin:"*) ;; *) PATH="\$HOME/.local/bin:\$PATH" ;; esac
export KEYS_AUTO="$PROFILES"
[ -r "$RC_SHARE/keys.sh" ] && . "$RC_SHARE/keys.sh"
# <<< team-keys <<<
EOF
        ok "$rc  →  KEYS_AUTO=\"$PROFILES\""
    done
    warn "the rc line loads from a local cache only, never the network — a new shell can
      never hang waiting on Infisical, and works offline once the cache is warm"
fi

# ------------------------------------------------------------------ 5. prove it
if [ "$FETCH" -eq 1 ]; then
    step "Fetching for real"
    # shellcheck disable=SC1090
    . "$SHARE/keys.sh"
    for p in $PROFILES; do
        keys --refresh "$p" || die "fetch failed for profile '$p' — see the message above"
    done
    keys --status $PROFILES
fi

cat <<EOF

$(printf '\033[32m\033[1mDone.\033[0m')  Open a new shell and the keys are simply there.

    keys --list          which key sets exist and where they live
    keys aitist          add another set to THIS shell
    keys --status        what is loaded (names and lengths, never values)

Two things worth knowing:
  · Your card is personal. It is logged, revocable on its own, and revoking it disturbs
    nobody else. So do not forward it — a new person gets their own.
  · Keys are not on your disk in plain form, and they are not in git. If you ever find
    yourself pasting one into a file, ask first; there is almost always a better way.
EOF
