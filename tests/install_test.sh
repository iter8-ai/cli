#!/bin/sh
# Run with: sh tests/install_test.sh
set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT INT TERM
mkdir -p "$test_root/bin" "$test_root/fixtures"
export TEST_ROOT="$test_root"
REAL_MV=$(command -v mv)
export REAL_MV
cat > "$test_root/fixtures/reiterate-linux-amd64" <<'BINARY'
#!/bin/sh
printf 'reiterate 9.8.7\n'
BINARY
if command -v sha256sum >/dev/null 2>&1; then
    hash=$(sha256sum "$test_root/fixtures/reiterate-linux-amd64" | awk '{print $1}')
else
    hash=$(shasum -a 256 "$test_root/fixtures/reiterate-linux-amd64" | awk '{print $1}')
fi
printf '%s  reiterate-linux-amd64\n' "$hash" > "$test_root/fixtures/checksums.txt"
cat > "$test_root/bin/uname" <<'STUB'
#!/bin/sh
case "$1" in
    -s) echo Linux ;;
    -m) echo x86_64 ;;
esac
STUB
cat > "$test_root/bin/curl" <<'STUB'
#!/bin/sh
set -eu
out=''
uri=''
while [ "$#" -gt 0 ]; do
    case "$1" in
        -o) shift; out=$1 ;;
        https://*) uri=$1 ;;
    esac
    shift
done
printf '%s\n' "$uri" >> "$TEST_ROOT/urls"
if [ "${uri##*/}" = manifest.json ] && [ "${INVALID_MANIFEST:-0}" = 1 ]; then
    printf '{\n  "version": "not-a-version"\n}\n' > "$out"
else
    cp "$TEST_ROOT/fixtures/${uri##*/}" "$out"
fi
STUB
cat > "$test_root/bin/mv" <<'STUB'
#!/bin/sh
set -eu
[ "$1" != '-f' ] || shift
printf '%s\n%s\n' "$1" "$2" >> "$TEST_ROOT/moves"
[ "${FAIL_MOVE:-0}" != 1 ] || exit 1
exec "$REAL_MV" "$@"
STUB
chmod 755 "$test_root/bin/"*
PATH="$test_root/bin:$PATH"
export PATH
REITERATE_INSTALL_DIR="$test_root/install dir"
REITERATE_VERSION=1.2.3
export REITERATE_INSTALL_DIR REITERATE_VERSION

sh "$root/install.sh" > "$test_root/output" 2>&1
source_path=$(sed -n '1p' "$test_root/moves")
if [ "$(dirname "$source_path")" != "$REITERATE_INSTALL_DIR" ]; then
    echo 'FAIL: final mv source must be inside REITERATE_INSTALL_DIR' >&2
    exit 1
fi
[ -x "$REITERATE_INSTALL_DIR/reiterate" ]
cmp "$test_root/fixtures/reiterate-linux-amd64" "$REITERATE_INSTALL_DIR/reiterate"
[ ! -e "$source_path" ]

REITERATE_INSTALL_DIR="$test_root/failed install"
export REITERATE_INSTALL_DIR
if FAIL_MOVE=1 sh "$root/install.sh" > "$test_root/output" 2>&1; then
    echo 'FAIL: simulated mv failure was accepted' >&2
    exit 1
fi
source_path=$(sed -n '3p' "$test_root/moves")
[ ! -e "$source_path" ]
[ ! -e "$REITERATE_INSTALL_DIR/reiterate" ]
echo 'PASS: same-directory shell staging, installed executable content and failure cleanup'

# Resolve latest once, then fetch both assets from that immutable release.
printf '{\n  "version": "9.8.7",\n  "files": []\n}\n' > "$test_root/fixtures/manifest.json"
REITERATE_INSTALL_DIR="$test_root/latest install"
REITERATE_VERSION=latest
export REITERATE_INSTALL_DIR REITERATE_VERSION
: > "$test_root/urls"
sh "$root/install.sh" > "$test_root/output" 2>&1
cat > "$test_root/expected-urls" <<'URLS'
https://github.com/iter8-ai/cli/releases/latest/download/manifest.json
https://github.com/iter8-ai/cli/releases/download/v9.8.7/reiterate-linux-amd64
https://github.com/iter8-ai/cli/releases/download/v9.8.7/checksums.txt
URLS
if ! cmp -s "$test_root/expected-urls" "$test_root/urls"; then
    echo 'FAIL: latest must resolve one manifest and pin both assets to v9.8.7' >&2
    cat "$test_root/urls" >&2
    exit 1
fi
REITERATE_INSTALL_DIR="$test_root/invalid latest"
export REITERATE_INSTALL_DIR
: > "$test_root/urls"
if INVALID_MANIFEST=1 sh "$root/install.sh" > "$test_root/output" 2>&1; then
    echo 'FAIL: invalid manifest version was accepted' >&2
    exit 1
fi
grep -q 'reiterate: could not resolve the latest release version' "$test_root/output"
[ ! -e "$REITERATE_INSTALL_DIR/reiterate" ]
[ "$(wc -l < "$test_root/urls" | tr -d ' ')" = 1 ]
for REITERATE_VERSION in 9.8.7 v9.8.7 invalid vv9.8.7; do
    export REITERATE_VERSION
    : > "$test_root/urls"
    case "$REITERATE_VERSION" in
        9.8.7|v9.8.7)
            sh "$root/install.sh" > "$test_root/output" 2>&1
            tail -n 2 "$test_root/expected-urls" > "$test_root/expected-pinned"
            cmp "$test_root/expected-pinned" "$test_root/urls" ;;
        *)
            if sh "$root/install.sh" > "$test_root/output" 2>&1; then
                echo 'FAIL: invalid explicit version was accepted' >&2
                exit 1
            fi
            [ ! -s "$test_root/urls" ] ;;
    esac
done
echo 'PASS: shell latest resolution pins both assets and validates manifest/explicit versions'
