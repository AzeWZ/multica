#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.selfhost.yml}"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"
MULTICA_BIN="${MULTICA_BIN:-$ROOT_DIR/server/bin/multica}"
BUILD_CLI_SCRIPT="${BUILD_CLI_SCRIPT:-$ROOT_DIR/scripts/build-cli-docker.sh}"
LOGIN_TOKEN="${MULTICA_LOGIN_TOKEN:-${MULTICA_TOKEN:-}}"
PROFILE="${MULTICA_PROFILE:-}"

read_env_value() {
	local key="$1"
	local file="$2"
	if [ ! -f "$file" ]; then
		return 1
	fi
	grep -E "^${key}=" "$file" | tail -n 1 | cut -d= -f2- | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//"
}

require_cmd() {
	if ! command -v "$1" >/dev/null 2>&1; then
		echo "$1 is required." >&2
		exit 1
	fi
}

wait_for_app() {
	local app_url="$1"
	local deadline=$((SECONDS + 120))
	local url="${app_url%/}/api/config"

	echo "Waiting for Multica web/API at $url..."
	while [ "$SECONDS" -lt "$deadline" ]; do
		if curl -fsS "$url" >/dev/null 2>&1; then
			echo "Multica is ready."
			return 0
		fi
		sleep 2
	done

	echo "Timed out waiting for $url" >&2
	return 1
}

ensure_cli_auth() {
	if "$MULTICA_BIN" "${PROFILE_ARGS[@]}" auth status >/dev/null 2>&1; then
		echo "CLI is already authenticated."
		return 0
	fi

	if [ -z "$LOGIN_TOKEN" ]; then
		echo "CLI is not authenticated. Set MULTICA_LOGIN_TOKEN=mul_... and rerun." >&2
		return 1
	fi

	echo "CLI is not authenticated; logging in with MULTICA_LOGIN_TOKEN."
	printf '%s\n' "$LOGIN_TOKEN" | "$MULTICA_BIN" "${PROFILE_ARGS[@]}" login --token
}

cd "$ROOT_DIR"

require_cmd docker
require_cmd curl

PROFILE_ARGS=()
if [ -n "$PROFILE" ]; then
	PROFILE_ARGS=(--profile "$PROFILE")
fi

if [ ! -x "$BUILD_CLI_SCRIPT" ]; then
	echo "CLI build script not found or not executable: $BUILD_CLI_SCRIPT" >&2
	exit 1
fi

frontend_origin="${FRONTEND_ORIGIN:-$(read_env_value FRONTEND_ORIGIN "$ENV_FILE" || true)}"
frontend_port="${FRONTEND_PORT:-$(read_env_value FRONTEND_PORT "$ENV_FILE" || true)}"
app_url="${MULTICA_APP_URL:-$(read_env_value MULTICA_APP_URL "$ENV_FILE" || true)}"
if [ -z "$app_url" ]; then
	if [ -n "$frontend_origin" ]; then
		app_url="$frontend_origin"
	else
		app_url="http://127.0.0.1:${frontend_port:-3000}"
	fi
fi

echo "Redeploying self-hosted Docker Compose stack..."
docker compose -f "$COMPOSE_FILE" up -d --pull always --remove-orphans --force-recreate
wait_for_app "$app_url"

echo "Rebuilding local multica CLI..."
"$BUILD_CLI_SCRIPT"

if [ ! -x "$MULTICA_BIN" ]; then
	echo "CLI binary was not built: $MULTICA_BIN" >&2
	exit 1
fi

cli_server_url="${MULTICA_CLI_SERVER_URL:-$app_url}"
cli_app_url="${MULTICA_CLI_APP_URL:-$app_url}"
echo "Configuring CLI for $cli_server_url..."
"$MULTICA_BIN" "${PROFILE_ARGS[@]}" config set server_url "$cli_server_url"
"$MULTICA_BIN" "${PROFILE_ARGS[@]}" config set app_url "$cli_app_url"

ensure_cli_auth

echo "Restarting daemon so it uses the rebuilt CLI..."
"$MULTICA_BIN" "${PROFILE_ARGS[@]}" daemon restart

echo "Done."
