#!/usr/bin/env bash
# Deploys the website (getfifteen.de) to the VPS straight from this Mac, without GitHub Actions.
# The same steps as .github/workflows/deploy-website.yml:
#   build check → rsync website/ to the server → docker compose up --build → wait for /health
#
# One-time setup: create scripts/.env.deploy (gitignored by the `.env.*` rule) with the values the
# workflow keeps in its secrets:
#   DEPLOY_HOST=your.server.example
#   DEPLOY_USER=deploy
#   DEPLOY_PORT=22                      # optional, defaults to 22
#   DEPLOY_KEY=~/.ssh/id_ed25519        # optional; leave it out to use the key in 1Password
# Any of them can also be passed as environment variables, which win over the file.
#
# Usage:
#   scripts/deploy-website.sh               # build check, sync, rebuild, health check
#   scripts/deploy-website.sh --skip-build  # skip the local npm build check
#   scripts/deploy-website.sh --dry-run     # show what rsync would change, touch nothing
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="fifteen-website"
SITE="https://getfifteen.de"
BUILD=1
DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --skip-build) BUILD=0 ;;
    --dry-run) DRY_RUN=1 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

# Environment variables override the file.
env_host=${DEPLOY_HOST-}; env_user=${DEPLOY_USER-}; env_port=${DEPLOY_PORT-}; env_key=${DEPLOY_KEY-}
if [[ -f scripts/.env.deploy ]]; then
  set -a; source scripts/.env.deploy; set +a
fi
DEPLOY_HOST=${env_host:-${DEPLOY_HOST-}}
DEPLOY_USER=${env_user:-${DEPLOY_USER-}}
DEPLOY_PORT=${env_port:-${DEPLOY_PORT:-22}}
DEPLOY_KEY=${env_key:-${DEPLOY_KEY-}}

if [[ -z "$DEPLOY_HOST" || -z "$DEPLOY_USER" ]]; then
  echo "Set DEPLOY_HOST and DEPLOY_USER in scripts/.env.deploy (see the top of this script)." >&2
  exit 1
fi

# Keys come from the 1Password SSH agent unless DEPLOY_KEY names a key file. 1Password asks to
# approve the key when the script first connects.
OP_AGENT="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
if [[ -z "$DEPLOY_KEY" && -S "$OP_AGENT" ]]; then
  export SSH_AUTH_SOCK="$OP_AGENT"
fi

# One shared connection for every step, so the key is approved once, not three times.
control_dir=$(mktemp -d)
control="$control_dir/ssh"
ssh_opts=(-p "$DEPLOY_PORT" -o ControlMaster=auto -o "ControlPath=$control" -o ControlPersist=120)
if [[ -n "$DEPLOY_KEY" ]]; then
  ssh_opts+=(-i "${DEPLOY_KEY/#\~/$HOME}")
fi
remote="$DEPLOY_USER@$DEPLOY_HOST"
cleanup() {
  local status=$?
  ssh -o "ControlPath=$control" -O exit "$remote" 2>/dev/null || true
  rm -rf "$control_dir"
  exit "$status"
}
trap cleanup EXIT
remote_dir="~/docker/apps/$APP_NAME"

if [[ -n "$(git status --porcelain -- website)" ]]; then
  echo "▸ Note: website/ has uncommitted changes; they're deployed as they are."
fi

if [[ $BUILD == 1 ]]; then
  echo "▸ Build check…"
  (cd website && npm ci --silent && npm run build --silent)
fi

rsync_flags=(-az --delete-after)
if [[ $DRY_RUN == 1 ]]; then rsync_flags+=(--dry-run --itemize-changes); else rsync_flags+=(--stats); fi

echo "▸ Syncing website/ to ${DEPLOY_HOST}…"
ssh "${ssh_opts[@]}" "$remote" "mkdir -p $remote_dir"
rsync "${rsync_flags[@]}" \
  --filter="- node_modules/" \
  --filter="- dist/" \
  --filter="+ .env.example" \
  --filter="- .env" \
  --filter="- .env.*" \
  --filter="- .DS_Store" \
  -e "ssh ${ssh_opts[*]}" \
  ./website/ "$remote:$remote_dir/"

if [[ $DRY_RUN == 1 ]]; then
  echo "▸ Dry run: nothing changed on the server."
  exit 0
fi

echo "▸ Rebuilding and restarting the container…"
ssh "${ssh_opts[@]}" "$remote" \
  "cd $remote_dir && DOCKER_BUILDKIT=1 docker compose up -d --build --remove-orphans && docker image prune -f"

echo "▸ Waiting for $SITE/health…"
for _ in $(seq 1 30); do
  if curl -fsS "$SITE/health" >/dev/null 2>&1; then
    echo "✓ $SITE is up"
    curl -fsSI "$SITE/download/mac" | grep -i '^location:' || true
    exit 0
  fi
  sleep 4
done
echo "✗ $SITE did not answer on /health" >&2
exit 1
