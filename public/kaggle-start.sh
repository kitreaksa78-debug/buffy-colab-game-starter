#!/bin/sh
# kaggle-start.sh — បើកហ្គេមក្នុង browser ពី Google Colab ឬ Kaggle ដោយបន្ទាត់តែមួយ។
#
# ក្នុង Colab cell មួយ (Runtime → Change runtime type → យ៉ាងហោចណាស់ CPU ក៏បាន):
#
#   !curl -fsSL https://raw.githubusercontent.com/hengfb361-design/buffy-ai/main/kaggle-start.sh | GAME_URL="https://…/game.zip" sh
#
# ឬដាក់ zip ក្នុង /content ជាមុន រួចរត់ត្រឹម៖
#
#   !curl -fsSL https://raw.githubusercontent.com/hengfb361-design/buffy-ai/main/kaggle-start.sh | sh
#
# វាធ្វើអ្វី៖ ទាញ/ពន្លា zip ហ្គេម → រក index.html → បើក web server →
# បើក Cloudflare tunnel → បោះ link https មួយឲ្យចុចលេងពីទូរស័ព្ទ។
#
# ⚠️ ហ្គេមត្រូវជា **HTML5 / WebAssembly** (zip មាន index.html, ដូចហ្គេមលើ itch.io
# ដែលមានប៊ូតុង "Run in browser")។ ហ្គេម PC ធម្មតា (.exe / .rar ដំឡើង Windows,
# DirectX, 10+ GB) ដូចជា Sleeping Dogs, GTA V ជាដើម **លេងក្នុង browser មិនបានទេ** —
# មិនថានៅ Colab ឬម៉ាស៊ីនណាទេ។ ស្គ្រីបនេះនឹងប្រាប់ច្បាស់បើ zip មិនមាន index.html។
#
# environment (ស្រេចចិត្ត):
#   GAME_URL     link ទាញយកផ្ទាល់ (ត្រូវជា direct link — គ្មាន login, គ្មាន turnstile)
#   GAME_ZIP     path ក្នុងម៉ាស៊ីន (ឧ. /content/mygame.zip)
#   PORT         default 8000
#   COI=1        បើក COOP/COEP (សម្រាប់ហ្គេមដែលត្រូវការ SharedArrayBuffer)
#   SKIP_TUNNEL=1  បើក server ក្នុងម៉ាស៊ីនតែប៉ុណ្ណោះ
#   TUNNEL       cloudflared | pinggy | lhr (default: សាកតាមលំដាប់នេះ)
#   STOP=1       បិទ server + tunnel ដែលស្គ្រីបនេះបើក រួចចេញ
#
# tunnel មាន ៣ ផ្លូវ ព្រោះបណ្តាញមួយចំនួន (ឧ. Wi-Fi សាលា) បិទ port 7844 របស់
# Cloudflare — ពេលនោះវាប្តូរទៅ pinggy/localhost.run ដែលរត់លើ SSH 443/22 វិញ។

set -u

PORT="${PORT:-8000}"
GAME_URL="${GAME_URL:-}"
GAME_ZIP="${GAME_ZIP:-}"

# /content = Colab, /kaggle/working = Kaggle, ផ្សេងទៀត = ក្បែរកន្លែងដែលរត់។
if [ -d /content ] && [ -w /content ]; then
  ROOT="${WORK:-/content}"
elif [ -d /kaggle/working ] && [ -w /kaggle/working ]; then
  ROOT="${WORK:-/kaggle/working}"
else
  ROOT="${WORK:-$PWD}"
fi
WORK="$ROOT/game-web"
SITE="$WORK/site"
mkdir -p "$WORK" || exit 1

say() { printf '%s\n' "$*"; }
step() { printf '\n==> %s\n' "$*"; }
die() {
  printf '\n!! %s\n' "$*" >&2
  exit 1
}

# បិទតែ process ដែលស្គ្រីបនេះចាប់ផ្តើម (កត់ PID ទុក) — មិនប៉ះអ្វីផ្សេងទេ។
kill_pidfile() {
  [ -f "$1" ] || return 0
  P=$(cat "$1" 2>/dev/null)
  if [ -n "${P:-}" ]; then
    pkill -P "$P" >/dev/null 2>&1 || true
    kill "$P" >/dev/null 2>&1 || true
  fi
  rm -f "$1"
}

# បើ tunnel មួយបរាជ័យ ត្រូវបិទតែ tunnel — web server ត្រូវរស់នៅឲ្យ provider បន្ទាប់ប្រើ។
stop_tunnel() { kill_pidfile "$WORK/tunnel.pid"; }
stop_all() {
  stop_tunnel
  kill_pidfile "$WORK/server.pid"
}

if [ "${STOP:-0}" = "1" ]; then
  stop_all
  say "បានបិទ server និង tunnel។"
  exit 0
fi

command -v python3 >/dev/null 2>&1 || die "រកមិនឃើញ python3 — សូមប្រើ Colab ឬ Kaggle។"
command -v curl >/dev/null 2>&1 || die "រកមិនឃើញ curl។"

stop_all
sleep 1

# ------------------------------------------------------------------ 1. ហ្គេម
step "1/4 រកឯកសារហ្គេម"

if [ -f "$SITE/index.html" ]; then
  say "ហ្គេមពន្លារួចហើយ — រំលងការទាញយក ($SITE)"
else
  ZIP="$WORK/game.zip"
  if [ -n "$GAME_URL" ]; then
    say "ទាញយក: $GAME_URL"
    # -C - = បន្តបើដាច់កណ្តាល (zip ធំៗងាយដាច់)
    curl -fL --retry 3 --retry-delay 3 -C - -o "$ZIP" "$GAME_URL" ||
      die "ទាញយកបរាជ័យ។ ពិនិត្យថា link ជា direct link (បើកក្នុង browser បានភ្លាម គ្មាន captcha)។
     បើជា link របស់ ankergames/ហាងហ្គេម PC នោះវាមិនមែន zip ហ្គេម browser ទេ។"
  elif [ -n "$GAME_ZIP" ]; then
    [ -f "$GAME_ZIP" ] || die "រកមិនឃើញ $GAME_ZIP"
    cp "$GAME_ZIP" "$ZIP" || die "ចម្លង $GAME_ZIP បរាជ័យ"
  else
    FOUND=$(ls -1 "$ROOT"/*.zip 2>/dev/null | head -1)
    [ -n "$FOUND" ] || die "មិនមាន zip ហ្គេម។
     ដាក់ឯកសារក្នុង $ROOT (ឧ. $ROOT/game.zip) ឬប្រើ GAME_URL=… ក្នុងបន្ទាត់បញ្ជា។"
    cp "$FOUND" "$ZIP" || die "ចម្លង $FOUND បរាជ័យ"
  fi

  step "2/4 ពន្លា zip"
  rm -rf "$SITE"
  mkdir -p "$SITE"
  python3 - "$ZIP" "$SITE" <<'PY' || die "ពន្លា zip បរាជ័យ — ឯកសារប្រហែលខូច ឬមិនមែន zip"
import sys, zipfile
zpath, dest = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(zpath) as z:
    z.extractall(dest)
PY
  say "ពន្លារួច → $SITE"
fi

# zip ភាគច្រើនមាន folder មួយនៅខាងក្នុង (game/index.html): ចុះទៅរក index.html
# ខ្លីបំផុត រួចប្រើ folder នោះជា root របស់វេបសាយ។
ENTRY=$(cd "$SITE" && find . -name index.html -type f 2>/dev/null |
  awk '{ print length($0), $0 }' | sort -n | head -1 | cut -d' ' -f2-)
if [ -z "${ENTRY:-}" ]; then
  printf '\n!! ក្នុង zip គ្មាន index.html ទេ — ដូច្នេះមិនមែនហ្គេម browser ទេ។\n' >&2
  printf '   ឯកសារដែលមានក្នុង zip (១៥ ដំបូង):\n' >&2
  (cd "$SITE" && find . -maxdepth 3 -type f | head -15 | sed 's/^/     /') >&2
  printf '   ហ្គេម browser (HTML5/WASM) ត្រូវមាន index.html នៅក្នុង zip។\n' >&2
  printf '   ហ្គេម PC (.exe, .iso, repack 10+ GB) លេងក្នុង browser មិនបានទេ។\n' >&2
  exit 1
fi
SITE_DIR=$(cd "$SITE" && cd "$(dirname "$ENTRY")" && pwd)
say "ទំព័រចាប់ផ្តើម: $ENTRY"

# --------------------------------------------------------------- 3. web server
step "3/4 បើក web server នៅ port $PORT"
cat >"$WORK/serve.py" <<'PY'
import functools, http.server, os, sys

root, port = sys.argv[1], int(sys.argv[2])
coi = os.environ.get("COI") == "1"

EXTRA = {
    ".wasm": "application/wasm", ".mjs": "text/javascript", ".js": "text/javascript",
    ".json": "application/json", ".data": "application/octet-stream",
    ".unityweb": "application/octet-stream", ".pck": "application/octet-stream",
    ".mem": "application/octet-stream", ".br": "application/octet-stream",
    ".gz": "application/gzip", ".wasm.gz": "application/wasm",
    ".svg": "image/svg+xml", ".woff2": "font/woff2", ".woff": "font/woff",
    ".mp3": "audio/mpeg", ".ogg": "audio/ogg", ".wav": "audio/wav",
    ".mp4": "video/mp4", ".webp": "image/webp", ".webmanifest": "application/manifest+json",
}


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map, **EXTRA}

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        if coi:
            self.send_header("Cross-Origin-Opener-Policy", "same-origin")
            self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
            self.send_header("Cross-Origin-Resource-Policy", "cross-origin")
        super().end_headers()

    def log_message(self, *args):
        pass


http.server.ThreadingHTTPServer(("0.0.0.0", port), functools.partial(Handler, directory=root)).serve_forever()
PY

COI="${COI:-0}" nohup python3 "$WORK/serve.py" "$SITE_DIR" "$PORT" \
  </dev/null >"$WORK/server.log" 2>&1 &
echo $! >"$WORK/server.pid"

READY=0
i=0
while [ "$i" -lt 20 ]; do
  if curl -fsS "http://127.0.0.1:$PORT/index.html" >/dev/null 2>&1; then
    READY=1
    break
  fi
  i=$((i + 1))
  sleep 1
done
[ "$READY" = "1" ] || {
  tail -10 "$WORK/server.log" 2>/dev/null | sed 's/^/    /' >&2
  die "web server មិនឆ្លើយនៅ port $PORT"
}
say "server ឆ្លើយរួច (http://127.0.0.1:$PORT)"

# ------------------------------------------------------------------ 4. tunnel
PUBLIC=""
if [ "${SKIP_TUNNEL:-0}" = "1" ]; then
  step "4/4 រំលង tunnel (SKIP_TUNNEL=1)"
else
  step "4/4 បើក tunnel"

  # $1 = log file; tunnel ត្រូវសរសេរ PID របស់ខ្លួនទៅ $WORK/tunnel.pid
  tunnel_cloudflared() {
    BIN_DIR="$WORK/bin"
    mkdir -p "$BIN_DIR"
    if command -v cloudflared >/dev/null 2>&1; then
      CF=$(command -v cloudflared)
    elif [ -x "$BIN_DIR/cloudflared" ]; then
      CF="$BIN_DIR/cloudflared"
    else
      case "$(uname -m)" in
        aarch64 | arm64) ARCH=arm64 ;;
        *) ARCH=amd64 ;;
      esac
      say "ទាញ cloudflared ($ARCH) ..."
      curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$ARCH" \
        -o "$BIN_DIR/cloudflared" || return 1
      chmod +x "$BIN_DIR/cloudflared"
      CF="$BIN_DIR/cloudflared"
    fi
    : >"$1"
    nohup "$CF" tunnel --no-autoupdate --url "http://localhost:$PORT" \
      </dev/null >"$1" 2>&1 &
    echo $! >"$WORK/tunnel.pid"
  }

  # pinggy / localhost.run ជា SSH tunnel លើ port 443 / 22 — ឆ្លងកាត់បណ្តាញ
  # ដែលបិទ 7844។ ទាំងពីរបោះ https URL ចេញក្នុង log។
  tunnel_ssh() {
    command -v ssh >/dev/null 2>&1 || return 1
    : >"$1"
    if [ "$2" = "pinggy" ]; then
      nohup ssh -T -p 443 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o ServerAliveInterval=30 -o ExitOnForwardFailure=yes \
        -R0:localhost:"$PORT" a.pinggy.io </dev/null >"$1" 2>&1 &
    else
      nohup ssh -T -p 22 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o ServerAliveInterval=30 -o ExitOnForwardFailure=yes \
        -R 80:localhost:"$PORT" nokey@localhost.run </dev/null >"$1" 2>&1 &
    fi
    echo $! >"$WORK/tunnel.pid"
  }

  # យក URL ចេញពី log របស់ provider, រួចសាកបើកវាពិតៗ — URL ដែលមានតែឈ្មោះ
  # តែមិនឆ្លើយ មិនរាប់ថាបានទេ។
  try_provider() {
    LOG="$WORK/tunnel-$1.log"
    say "សាក tunnel: $1"
    case "$1" in
      cloudflared) tunnel_cloudflared "$LOG" || return 1 ;;
      *) tunnel_ssh "$LOG" "$1" || return 1 ;;
    esac
    CAND=""
    i=0
    while [ "$i" -lt 25 ]; do
      CAND=$(grep -Eo 'https://[A-Za-z0-9._-]+\.(trycloudflare\.com|pinggy-free\.link|free\.pinggy\.net|lhr\.life)' \
        "$LOG" 2>/dev/null | head -1)
      [ -n "$CAND" ] && break
      i=$((i + 1))
      sleep 2
    done
    [ -n "$CAND" ] || return 1
    # tunnel ត្រូវការពេលបន្តិចទើប route មកដល់
    i=0
    while [ "$i" -lt 20 ]; do
      CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 12 "$CAND/" 2>/dev/null)
      case "$CODE" in 2* | 3*) PUBLIC="$CAND" ; break ;; esac
      i=$((i + 1))
      sleep 2
    done
    [ -n "$PUBLIC" ] && return 0
    stop_tunnel
    return 1
  }

  for PROVIDER in ${TUNNEL:-cloudflared pinggy lhr}; do
    try_provider "$PROVIDER" && break
    say "$PROVIDER មិនដំណើរការ — បន្តទៅផ្លូវបន្ទាប់"
  done
  [ -n "$PUBLIC" ] || die "គ្មាន tunnel ណាភ្ជាប់បាន (បណ្តាញបិទទាំង 7844 និង SSH)។
     ក្នុង Colab សាកប្រើ cell ថ្មីមួយ:
       from google.colab.output import eval_js; print(eval_js('google.colab.kernel.proxyPort($PORT)'))
     រួចបើក link នោះ (server នៅរត់ក្នុងម៉ាស៊ីនរួចហើយ)។"
fi

printf '\n============================================================\n'
printf '  ចុច link ខាងក្រោមដើម្បីលេង (ហ្គេមរត់នៅម៉ាស៊ីននេះ)\n'
printf '============================================================\n'
if [ -n "$PUBLIC" ]; then
  printf 'លេង   : %s\n' "$PUBLIC"
  printf 'ស្ថានភាព : រួចរាល់ — link ឆ្លើយតបរួចហើយ\n'
else
  printf 'ក្នុងម៉ាស៊ីន : http://127.0.0.1:%s (តែម៉ាស៊ីននេះឃើញ)\n' "$PORT"
fi
printf 'ឯកសារ : %s\n' "$SITE_DIR"
printf '============================================================\n'
say "• ទុក tab នេះបើកចុះ — បិទ tab ឬ idle ~៩០ នាទី = session ដាច់ link ស្លាប់។"
say "• បញ្ឈប់: រត់បន្ទាត់ដដែលម្តងទៀតជាមួយ STOP=1"
say "• log: $WORK/server.log · $WORK/tunnel-*.log"
