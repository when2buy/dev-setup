# shellcheck shell=bash
# keys — load this org's Infisical secrets into the current shell. Project ids baked in.
#
# MUST be sourced, not executed. A child process cannot set its parent's environment, so
# `./keys.sh` would fetch everything and then throw it away.
#
#   . /path/to/keys.sh          # defines `keys` (put this line in ~/.bashrc)
#   keys paper                  # 15 Alpaca paper keys into THIS shell
#   keys paper aitist           # more than one profile at a time
#   keys --list                 # what profiles exist
#   keys --status               # what is loaded (names + lengths, never values)
#   keys --refresh paper        # ignore the cache, fetch now
#   keys --daemon paper         # background refresher: this box always has fresh keys
#   keys --stop paper
#
# Requires ONE file, placed once by a human: ~/.secrets/infisical.env holding
#     export INFISICAL_CLIENT_ID=...
#     export INFISICAL_CLIENT_SECRET=...
# That pair is a door card, not a key. To place it on a new machine, one command:
#   curl -fsSL https://raw.githubusercontent.com/when2buy/dev-setup/main/install.sh | bash
# Background: docs/infisical/setup-new-box.md.
#
# Why a cache file instead of fetching on every shell: a round trip to app.infisical.com
# from a cloud box measures ~240 ms, versus ~0.1 ms to source a local file — below bash's
# own 2.8 ms startup. Paying 240 ms per shell would tax every tmux pane, every `bash -c`
# and every agent tool call, and would make a new shell fail to open whenever the network
# or the credential is down. So: interactive shells read the cache and NEVER touch the
# network; the network is only reached on --refresh, on a cold cache, or by the daemon.
#
# Never prints a secret value. --status prints names and lengths only.
# (Engine folded in from the tested scripts/keyload.sh, which this file replaces.)

# ------------------------------------------------------------------ baked-in ids
# Not secrets: an id identifies a room, it does not open it. Safe to commit.
_KEYS_NONPROD=90faa2df-86fe-449a-b46c-e4c4a490f082   # team-nonprod   dev + staging
_KEYS_TEAMPROD=43a3a1e5-8a75-41bb-8d60-0f9f88192e60  # team-prod      prod
_KEYS_W2BPROD=5047aef4-5244-4ecc-9297-846cd4bcfd50   # when2buy-prod  prod, LIVE money

# profile -> "<project id> <env> <path>"
_keys_profile() {
    case "$1" in
        paper)       echo "$_KEYS_NONPROD  dev  /when2buy"  ;;
        aitist)      echo "$_KEYS_NONPROD  dev  /Aitist"    ;;
        airacle)     echo "$_KEYS_NONPROD  dev  /Airacle"   ;;
        zhongtian)   echo "$_KEYS_NONPROD  dev  /Zhongtian" ;;
        steve)       echo "$_KEYS_NONPROD  dev  /Steve"     ;;
        aitist-prod) echo "$_KEYS_TEAMPROD prod /Aitist"    ;;
        steve-prod)  echo "$_KEYS_TEAMPROD prod /Steve"     ;;
        live)        echo "$_KEYS_W2BPROD  prod /shared"    ;;   # real broker credentials
        *)           return 1 ;;
    esac
}
_KEYS_ALL="paper aitist airacle zhongtian steve aitist-prod steve-prod live"

_KEYS_CARD="${KEYS_CARD:-$HOME/.secrets/infisical.env}"
_KEYS_CACHE_DIR="${KEYS_CACHE_DIR:-$HOME/.cache/infisical}"
_KEYS_MAX_AGE="${KEYS_MAX_AGE:-43200}"               # 12h before a cold `keys` re-fetches
# Absolute path to this file, so --daemon and --help can find it again. zsh has no
# BASH_SOURCE; its equivalent is ${(%):-%x}, which bash cannot even parse, hence the eval.
if [ -n "${BASH_SOURCE:-}" ]; then _keys_src="${BASH_SOURCE[0]}"
elif [ -n "${ZSH_VERSION:-}" ]; then _keys_src="$(eval 'printf %s "${(%):-%x}"')"
else _keys_src="$0"; fi
_KEYS_SELF="$(cd "$(dirname "$_keys_src")" >/dev/null 2>&1 && pwd)/$(basename "$_keys_src")"
unset _keys_src

keys() {
    local force=0 quiet=0 action=load profiles=() p
    while [ $# -gt 0 ]; do
        case "$1" in
            -r|--refresh) force=1 ;;
            -q|--quiet)   quiet=1 ;;
            -l|--list)    action=list ;;
            -s|--status)  action=status ;;
            --daemon)     action=daemon ;;
            --stop)       action=stop ;;
            -h|--help)    action=help ;;
            -*) printf 'keys: unknown option %s (try --help)\n' "$1" >&2; return 2 ;;
            *)  profiles+=("$1") ;;
        esac
        shift
    done

    case "$action" in
    help) sed -n '3,17p' "$_KEYS_SELF" | sed 's/^# \{0,1\}//'; return 0 ;;
    list)
        printf '  %-12s %-14s %-6s %s\n' PROFILE PROJECT ENV PATH
        for p in $_KEYS_ALL; do
            # shellcheck disable=SC2046
            set -- $(_keys_profile "$p")
            printf '  %-12s %-14s %-6s %s\n' "$p" "${1:0:8}…" "$2" "$3"
        done
        printf '\n  live = real broker credentials. Needs a when2buy-prod card,\n'
        printf '  which no machine currently has (403 "not a member" is expected).\n'
        return 0 ;;
    status)
        [ ${#profiles[@]} -eq 0 ] && profiles=($_KEYS_ALL)
        for p in "${profiles[@]}"; do
            local f="$_KEYS_CACHE_DIR/$p.env"
            [ -r "$f" ] || continue
            printf '  %s  (cached %ss ago)\n' "$p" "$(( $(date +%s) - $(_keys_mtime "$f") ))"
            local k v
            while read -r k; do
                v="$(_keys_val "$k")"
                if [ -n "$v" ]; then printf '    %-46s len=%s\n' "$k" "${#v}"
                else printf '    %-46s NOT in this shell (run `keys %s`)\n' "$k" "$p"; fi
            done < <(sed -n 's/^export \([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p' "$f")
        done
        return 0 ;;
    daemon|stop)
        [ ${#profiles[@]} -gt 0 ] || { printf 'keys: --%s needs a profile\n' "$action" >&2; return 2; }
        for p in "${profiles[@]}"; do _keys_daemon "$action" "$p" || return 1; done
        return 0 ;;
    esac

    # ---------------------------------------------------------------- load
    [ ${#profiles[@]} -gt 0 ] || { printf 'keys: which profile? (keys --list)\n' >&2; return 2; }
    for p in "${profiles[@]}"; do _keys_load "$p" "$force" "$quiet" || return 1; done
}

_keys_mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }

# Value of the variable NAMED by $1. bash spells it ${!name}, zsh spells it ${(P)name},
# and neither shell can parse the other's form — so branch, and eval to hide the syntax.
_keys_val() {
    if [ -n "${ZSH_VERSION:-}" ]; then eval 'printf %s "${(P)1}"'
    else eval 'printf %s "${!1}"'; fi
}

_keys_token() {
    # Exchange the card for a short-lived token (2h TTL). Cached for this shell only.
    [ -n "${_KEYS_TOKEN:-}" ] && { printf '%s' "$_KEYS_TOKEN"; return 0; }
    [ -r "$_KEYS_CARD" ] || {
        printf 'keys: no card at %s. To get one:\n' "$_KEYS_CARD" >&2
        printf '  curl -fsSL https://raw.githubusercontent.com/when2buy/dev-setup/main/install.sh | bash\n' >&2
        return 1; }
    # shellcheck disable=SC1090
    . "$_KEYS_CARD"
    [ -n "${INFISICAL_CLIENT_ID:-}" ] && [ -n "${INFISICAL_CLIENT_SECRET:-}" ] || {
        printf 'keys: %s has no INFISICAL_CLIENT_ID/SECRET\n' "$_KEYS_CARD" >&2; return 1; }
    command -v infisical >/dev/null 2>&1 || {
        printf 'keys: infisical CLI not installed (npm i -g @infisical/cli)\n' >&2; return 1; }
    _KEYS_TOKEN="$(infisical login --method=universal-auth \
        --client-id="$INFISICAL_CLIENT_ID" --client-secret="$INFISICAL_CLIENT_SECRET" \
        --plain --silent 2>/dev/null)" || _KEYS_TOKEN=""
    [ -n "$_KEYS_TOKEN" ] || {
        printf 'keys: login failed — card revoked/expired, or no network\n' >&2; return 1; }
    printf '%s' "$_KEYS_TOKEN"
}

_keys_fetch() {
    # $1 profile. Writes the cache atomically; leaves a good cache alone on failure.
    local p="$1" pid env path tmp rc
    # shellcheck disable=SC2046
    set -- $(_keys_profile "$p") || return 1
    pid="$1" env="$2" path="$3"
    local cache="$_KEYS_CACHE_DIR/$p.env" tok
    tok="$(_keys_token)" || return 1
    install -d -m 700 "$_KEYS_CACHE_DIR" 2>/dev/null
    tmp="$(umask 077 && mktemp "$cache.XXXXXX")" || return 1
    INFISICAL_TOKEN="$tok" infisical export --format=dotenv-export --silent \
        --projectId="$pid" --env="$env" --path="$path" >"$tmp" 2>"$tmp.err"; rc=$?
    # A cache we cannot parse is worse than a stale one: swap it in only if the fetch
    # succeeded AND produced at least one export line.
    if [ "$rc" -eq 0 ] && grep -qE '^export [A-Za-z_][A-Za-z0-9_]*=' "$tmp"; then
        chmod 600 "$tmp" && mv -f "$tmp" "$cache"; rm -f "$tmp.err"
        return 0
    fi
    # rc=0 with no export lines is not a failure at all: the folder exists and is empty,
    # i.e. nobody has put a secret in it yet. Saying "FAILED" there sends the reader off
    # to debug their credential, which is fine, and their network, which is fine.
    if [ "$rc" -eq 0 ]; then
        printf 'keys: %s is empty — the folder %s exists but holds no secrets yet\n' "$p" "$path" >&2
        rm -f "$tmp" "$tmp.err"
        [ -r "$cache" ]
        return
    fi
    printf 'keys: %s fetch FAILED (rc=%s) — %s\n' "$p" "$rc" \
        "$([ -r "$cache" ] && echo 'keeping the existing cache' || echo 'no cache to fall back on')" >&2
    # The CLI prints the request URL first and the actual reason fourth, so echoing the
    # first two lines shows a URL and HIDES "403 — you are not a member of this project",
    # which is the entire answer (and, for the `live` profile, the expected one). Prefer
    # the lines that say something; fall back to the head only if the shape ever changes.
    if grep -qE '^(Response Code|Message):' "$tmp.err" 2>/dev/null; then
        grep -E '^(Response Code|Message):' "$tmp.err" | cut -c1-200 | sed 's/^/  /' >&2
    else
        sed -n '1,2p' "$tmp.err" >&2 2>/dev/null
    fi
    rm -f "$tmp" "$tmp.err"
    [ -r "$cache" ]
}

_keys_load() {
    local p="$1" force="$2" quiet="$3"
    _keys_profile "$p" >/dev/null || {
        printf 'keys: no such profile %s (keys --list)\n' "$p" >&2; return 1; }
    local cache="$_KEYS_CACHE_DIR/$p.env" need=0
    if [ "$force" -eq 1 ] || [ ! -r "$cache" ]; then need=1
    elif [ "$(( $(date +%s) - $(_keys_mtime "$cache") ))" -gt "$_KEYS_MAX_AGE" ]; then need=1; fi
    [ "$need" -eq 1 ] && { _keys_fetch "$p" || return 1; }

    # Refuse a world- or group-readable secret file.
    local mode; mode="$(stat -c %a "$cache" 2>/dev/null || stat -f %Lp "$cache" 2>/dev/null)"
    case "$mode" in 600|400) ;; *)
        printf 'keys: %s has mode %s, expected 600 — refusing\n' "$cache" "$mode" >&2; return 1 ;;
    esac
    set -a; . "$cache"; set +a
    [ "$quiet" -eq 1 ] || printf 'keys: %s — %s key(s) in this shell\n' \
        "$p" "$(grep -cE '^export ' "$cache")" >&2
    [ "$p" = live ] && printf 'keys: ⚠️  LIVE broker credentials are now in this shell; every child process inherits them\n' >&2
    return 0
}

_keys_daemon() {
    # Keep the cache warm so this box always has fresh keys, even across a rotation.
    # ⚠️ Already-running processes do NOT see a new value: env vars are a copy taken at
    # spawn time. A rotated key reaches a service only when the service restarts.
    local action="$1" p="$2" s="infisical-keys-$p"
    command -v tmux >/dev/null 2>&1 || { printf 'keys: tmux not installed\n' >&2; return 1; }
    if [ "$action" = stop ]; then
        tmux kill-session -t "$s" 2>/dev/null && printf 'keys: stopped %s\n' "$s" || \
            printf 'keys: %s was not running\n' "$s"
        return 0
    fi
    _keys_profile "$p" >/dev/null || { printf 'keys: no such profile %s\n' "$p" >&2; return 1; }
    if tmux has-session -t "$s" 2>/dev/null; then
        printf 'keys: %s already running\n' "$s"; return 0
    fi
    tmux new -d -s "$s" "bash -c '. \"$_KEYS_SELF\"; while :; do keys --refresh --quiet $p; sleep ${KEYS_REFRESH_EVERY:-600}; done'" \
        && printf 'keys: %s refreshing %s every %ss (tmux kill-session -t %s to stop)\n' \
           "$s" "$p" "${KEYS_REFRESH_EVERY:-600}" "$s"
}

# Auto-load from the cache ONLY — never reach the network on the login path, or a flaky
# network makes new shells hang. Set KEYS_AUTO to the profiles you want in every shell;
# opt out entirely with KEYS_AUTO=none.
#
# This deliberately does NOT test for an interactive shell. It used to, on the theory that
# a login-path cost should only be paid by a human at a terminal — but the cost is a single
# read of a local file (~0.1 ms, below bash's own 2.8 ms startup), while the shells that
# were being skipped are the ones that matter most: `ssh box 'python app.py'`, cron, CI,
# and a coding agent's shell tool are all non-interactive. Skipping them meant a terminal
# on the box had the keys and an ssh one-liner on the same box silently did not.
for _kp in ${KEYS_AUTO:-none}; do
    [ "$_kp" = none ] && break
    [ -r "$_KEYS_CACHE_DIR/$_kp.env" ] && KEYS_MAX_AGE=99999999 keys --quiet "$_kp"
done
unset _kp
