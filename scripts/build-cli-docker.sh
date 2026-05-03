#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER_DIR="$ROOT_DIR/server"

GO_IMAGE="${GO_IMAGE:-golang:1.26.1-bookworm}"
TARGET_OS="${TARGET_OS:-}"
TARGET_ARCH="${TARGET_ARCH:-}"
OUTPUT="${OUTPUT:-}"
VERSION="${VERSION:-$(git -C "$ROOT_DIR" describe --tags --always --dirty 2>/dev/null || echo dev)}"
COMMIT="${COMMIT:-$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)}"
DATE="${DATE:-$(date -u "+%Y-%m-%dT%H:%M:%SZ")}"

if ! command -v docker >/dev/null 2>&1; then
	echo "docker is required to build the CLI without a local Go toolchain." >&2
	exit 1
fi

if [ -z "$TARGET_OS" ]; then
	case "$(uname -s)" in
		Darwin) TARGET_OS="darwin" ;;
		Linux) TARGET_OS="linux" ;;
		MINGW*|MSYS*|CYGWIN*) TARGET_OS="windows" ;;
		*)
			echo "unsupported host OS: $(uname -s). Set TARGET_OS manually." >&2
			exit 1
			;;
	esac
fi

if [ -z "$TARGET_ARCH" ]; then
	case "$(uname -m)" in
		x86_64|amd64) TARGET_ARCH="amd64" ;;
		arm64|aarch64) TARGET_ARCH="arm64" ;;
		*)
			echo "unsupported host architecture: $(uname -m). Set TARGET_ARCH manually." >&2
			exit 1
			;;
	esac
fi

if [ -z "$OUTPUT" ]; then
	if [ "$TARGET_OS" = "windows" ]; then
		OUTPUT="bin/multica.exe"
	else
		OUTPUT="bin/multica"
	fi
fi

mkdir -p "$SERVER_DIR/bin" "$ROOT_DIR/.cache/go-build" "$ROOT_DIR/.cache/go-mod"

echo "Building multica CLI for $TARGET_OS/$TARGET_ARCH with $GO_IMAGE..."
echo "Version: $VERSION ($COMMIT, $DATE)"
echo "Output: server/$OUTPUT"

docker run --rm \
	-v "$ROOT_DIR":/src \
	-w /src/server \
	-u "$(id -u):$(id -g)" \
	-e CGO_ENABLED=0 \
	-e GOOS="$TARGET_OS" \
	-e GOARCH="$TARGET_ARCH" \
	-e OUTPUT="$OUTPUT" \
	-e VERSION="$VERSION" \
	-e COMMIT="$COMMIT" \
	-e DATE="$DATE" \
	-e GOCACHE=/src/.cache/go-build \
	-e GOMODCACHE=/src/.cache/go-mod \
	"$GO_IMAGE" \
	sh -lc '
		export PATH="/usr/local/go/bin:$PATH"
		go build -buildvcs=false -ldflags "-X main.version=$VERSION -X main.commit=$COMMIT -X main.date=$DATE" -o "$OUTPUT" ./cmd/multica
	'

if [ "$TARGET_OS" != "windows" ]; then
	chmod +x "$SERVER_DIR/$OUTPUT"
fi

echo "Built $SERVER_DIR/$OUTPUT"
