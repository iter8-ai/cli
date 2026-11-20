#!/bin/sh
# Installs the Reiterate CLI from the latest public release.
#   curl -fsSL https://raw.githubusercontent.com/iter8-ai/cli/main/install.sh | sh
# Settings: REITERATE_INSTALL_DIR (default ~/.local/bin), REITERATE_VERSION (default latest, e.g. 0.1.0)
set -eu

repo="iter8-ai/cli"
dir="${REITERATE_INSTALL_DIR:-$HOME/.local/bin}"
version="${REITERATE_VERSION:-latest}"

case "$(uname -s)" in
  Darwin) os=darwin ;;
  Linux) os=linux ;;
  MINGW*|MSYS*|CYGWIN*)
    echo "reiterate: on Windows, run in PowerShell: irm https://raw.githubusercontent.com/iter8-ai/cli/main/install.ps1 | iex" >&2
    exit 1 ;;
  *) echo "reiterate: unsupported system $(uname -s); use macOS, Linux or Windows (install.ps1)" >&2; exit 1 ;;
esac
case "$(uname -m)" in
  arm64|aarch64) arch=arm64 ;;
  x86_64|amd64) arch=amd64 ;;
  *) echo "reiterate: unsupported architecture $(uname -m)" >&2; exit 1 ;;
esac

file="reiterate-$os-$arch"
tmp="$(mktemp -d)"
staging="$dir/.reiterate.$$"
trap 'rm -f "$staging"; rm -rf "$tmp"' EXIT INT TERM

if [ "$version" = latest ]; then
  curl -fsSL --proto '=https' --tlsv1.2 -o "$tmp/manifest.json" "https://github.com/$repo/releases/latest/download/manifest.json"
  version="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^" ]*\)".*/\1/p' "$tmp/manifest.json")"
  version_error='reiterate: could not resolve the latest release version'
else
  version="${version#v}"
  version_error="reiterate: invalid release version '$version'"
fi
if ! printf '%s\n' "$version" | awk 'END {exit !(NR == 1 && $0 ~ /^[0-9]+\.[0-9]+\.[0-9]+$/)}'; then
  echo "$version_error" >&2
  exit 1
fi
base="https://github.com/$repo/releases/download/v$version"

curl -fsSL --proto '=https' --tlsv1.2 -o "$tmp/$file" "$base/$file"
curl -fsSL --proto '=https' --tlsv1.2 -o "$tmp/checksums.txt" "$base/checksums.txt"

want="$(awk -v f="$file" '$2 == f {print $1}' "$tmp/checksums.txt")"
if command -v sha256sum >/dev/null 2>&1; then
  got="$(sha256sum "$tmp/$file" | awk '{print $1}')"
else
  got="$(shasum -a 256 "$tmp/$file" | awk '{print $1}')"
fi
if [ -z "$want" ] || [ "$want" != "$got" ]; then
  echo "reiterate: checksum mismatch for $file; nothing installed" >&2
  exit 1
fi

mkdir -p "$dir"
cp "$tmp/$file" "$staging"
chmod 755 "$staging"
mv -f "$staging" "$dir/reiterate"

echo "Installed $("$dir/reiterate" version) to $dir/reiterate"
case ":$PATH:" in
  *":$dir:"*) ;;
  *) echo "Add $dir to your PATH:  export PATH=\"$dir:\$PATH\"" ;;
esac
if [ "$os" = linux ]; then
  echo "Linux has no Keychain. Before logging in run:  reiterate configure set token_store file"
fi
echo "Next:  reiterate login"
