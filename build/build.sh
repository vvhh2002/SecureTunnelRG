#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: bash build/build.sh [--target <triple>]

Without --target, build the Rust host target for local CLI development.
Static application packaging targets for Debian runtime images:
  x86_64-unknown-linux-musl
  aarch64-unknown-linux-musl

Install the Rust target and configure its linker before building.
Static musl builds require readelf or llvm-readelf for ELF verification.
EOF
}

requested_target=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      if [[ $# -lt 2 || -z "$2" || "$2" == -* || -n "$requested_target" ]]; then
        echo "--target requires one target triple and may only appear once." >&2
        exit 2
      fi
      requested_target="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

gateway_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_dir="$(cd "$gateway_dir/.." && pwd)/SecureTunnelAPP"
if [[ ! -f "$app_dir/Cargo.toml" ]]; then
  echo "Missing shared APP: place SecureTunnelAPP beside SecureTunnelRG." >&2
  exit 1
fi

host="$(rustc -vV | sed -n 's/^host: //p')"
if [[ -z "$host" ]]; then
  echo "Cannot determine the Rust host target." >&2
  exit 1
fi
target="${requested_target:-$host}"
case "$target" in
  "$host"|x86_64-unknown-linux-musl|aarch64-unknown-linux-musl) ;;
  *)
    echo "Unsupported target: $target. Use the Rust host ($host) or a documented static musl target." >&2
    exit 2
    ;;
esac

binary="securetunnel-rg"
stage="$gateway_dir/dist/$target/stage"
stage_marker="$binary:$target:scaffold-v1"
# Refuse to overwrite foreign stage content. Every permitted file is regenerated.
if [[ -e "$stage" || -L "$stage" ]]; then
  if [[ ! -d "$stage" || -L "$stage" || ! -f "$stage/.securetunnel-build-stage" || -L "$stage/.securetunnel-build-stage" ]]; then
    echo "Refusing unowned stage directory: $stage" >&2
    exit 1
  fi
  if [[ "$(cat "$stage/.securetunnel-build-stage")" != "$stage_marker" ]]; then
    echo "Stage ownership marker does not match this build: $stage" >&2
    exit 1
  fi
  while IFS= read -r entry; do
    case "$entry" in
      "$stage/bin")
        [[ -d "$entry" && ! -L "$entry" ]] || { echo "Invalid stage directory: $entry" >&2; exit 1; }
        ;;
      "$stage/.securetunnel-build-stage"|"$stage/bin/$binary"|"$stage/README.md"|"$stage/LICENSE"|"$stage/BUILD-INFO.txt")
        [[ -f "$entry" && ! -L "$entry" ]] || { echo "Invalid stage file: $entry" >&2; exit 1; }
        ;;
      *)
        echo "Refusing unexpected stage content; move it elsewhere first: $entry" >&2
        exit 1
        ;;
    esac
  done < <(find "$stage" -mindepth 1 -print)
fi

elf_reader=""
libc="host-platform"
static_elf_verification="not-requested"
runtime_packaging="ineligible-development-only"
case "$target" in
  *-linux-musl*)
    libc="musl"
    if command -v readelf >/dev/null 2>&1; then
      elf_reader="$(command -v readelf)"
    elif command -v llvm-readelf >/dev/null 2>&1; then
      elf_reader="$(command -v llvm-readelf)"
    else
      echo "musl builds require readelf (binutils) or llvm-readelf to verify static ELF output." >&2
      exit 1
    fi
    ;;
  *-linux-gnu*) libc="glibc" ;;
  *-apple-darwin) libc="libSystem" ;;
esac

cd "$gateway_dir"
export CARGO_TARGET_DIR="$gateway_dir/target"
cargo build --manifest-path "$app_dir/Cargo.toml" --package securetunnel-app --bin "$binary" --locked --release --target "$target"
binary_path="$CARGO_TARGET_DIR/$target/release/$binary"

if [[ -n "$elf_reader" ]]; then
  # Successful parsing also rejects non-ELF output. No target-name-only static claim.
  elf_header="$(LC_ALL=C "$elf_reader" --file-header "$binary_path" | LC_ALL=C tr '[:upper:]' '[:lower:]')"
  elf_class="$(printf '%s\n' "$elf_header" | sed -n 's/^[[:space:]]*class:[[:space:]]*//p' | tr -d '[:space:]')"
  elf_machine="$(printf '%s\n' "$elf_header" | sed -n 's/^[[:space:]]*machine:[[:space:]]*//p' | tr -d '[:space:]')"
  case "$target" in
    x86_64-unknown-linux-musl) expected_machine="advancedmicrodevicesx86-64" ;;
    aarch64-unknown-linux-musl) expected_machine="aarch64" ;;
    *) expected_machine="" ;;
  esac
  if [[ -n "$expected_machine" && ( "$elf_class" != "elf64" || "$elf_machine" != "$expected_machine" ) ]]; then
    echo "Rejecting ELF class/machine mismatch for $target: class=$elf_class machine=$elf_machine" >&2
    exit 1
  fi
  elf_program_headers="$(LC_ALL=C "$elf_reader" --program-headers --wide "$binary_path")"
  elf_dynamic_section="$(LC_ALL=C "$elf_reader" --dynamic --wide "$binary_path")"
  if [[ "$elf_program_headers" == *INTERP* || "$elf_dynamic_section" == *"(NEEDED)"* ]]; then
    echo "Rejecting musl artifact with an ELF interpreter or shared-library dependency: $binary_path" >&2
    exit 1
  fi
  static_elf_verification="passed-no-INTERP-no-NEEDED"
  case "$target" in
    x86_64-unknown-linux-musl|aarch64-unknown-linux-musl)
      runtime_packaging="eligible-static-musl"
      ;;
  esac
fi

target_arch="${target%%-*}"
if [[ "$target" == "$host" || ( "$host" == "$target_arch"-*-linux-* && "$target" == *-linux-musl ) ]]; then
  "$binary_path" --version
  smoke_test="passed-native-execution"
else
  smoke_test="skipped-cross-target"
  echo "Skipping --version execution: target $target cannot run natively on Rust host $host."
fi

mkdir -p "$stage/bin"
printf '%s\n' "$stage_marker" > "$stage/.securetunnel-build-stage"
install -m 755 "$binary_path" "$stage/bin/$binary"
install -m 644 README.md "$stage/README.md"
install -m 644 LICENSE "$stage/LICENSE"

revision() {
  local source_dir="$1"
  # Do not mistake an enclosing integration repository for the APP repository.
  if [[ -e "$source_dir/.git" ]] && git -C "$source_dir" rev-parse HEAD >/dev/null 2>&1; then
    git -C "$source_dir" rev-parse HEAD
    if [[ -n "$(git -C "$source_dir" status --porcelain --untracked-files=normal)" ]]; then
      echo "working_tree=dirty"
    else
      echo "working_tree=clean"
    fi
  else
    echo "unversioned-local-source"
  fi
}

{
  echo "stage=scaffold"
  echo "gateway=SecureTunnelRG"
  echo "app_package=securetunnel-app"
  echo "app_binary=$binary"
  echo "application_source=SecureTunnelAPP"
  echo "reference_role=D"
  echo "target=$target"
  echo "host=$host"
  echo "libc=$libc"
  echo "static_elf_verification=$static_elf_verification"
  echo "runtime_packaging=$runtime_packaging"
  echo "runtime_distribution=debian"
  echo "runtime_suite=trixie"
  echo "runtime_base_image=debian:trixie-slim"
  echo "smoke_test=$smoke_test"
  echo "gateway_source:"
  revision "$gateway_dir"
  echo "app_source:"
  revision "$app_dir"
  echo "rustc:"
  rustc -vV
} > "$stage/BUILD-INFO.txt"

archive="$gateway_dir/dist/$binary-$target-scaffold.tar.gz"
tar -czf "$archive" -C "$stage" .
echo "Built scaffold: $archive"
if [[ "$runtime_packaging" != "eligible-static-musl" ]]; then
  echo "Development artifact only: this target does not satisfy the runtime image's static musl artifact contract."
fi
