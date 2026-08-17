#!/usr/bin/env bash
# Run lightweight host checks. Target DMA validation still requires the board.
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT

cd "$repo_dir"
git diff --check
empty_tree=$(git hash-object -t tree /dev/null)
git diff --check "$empty_tree" HEAD

while IFS= read -r -d '' script; do
    bash -n "$script"
done < <(find buildroot-external -type f -name '*.sh' -print0)

cc_bin=${CC:-cc}
common_flags=(-std=c11 -Wall -Wextra -Werror -Iinclude/uapi)
"$cc_bin" "${common_flags[@]}" linux_app/fft_dma_test.c \
    -o "$temp_dir/fft_dma_test"
"$cc_bin" "${common_flags[@]}" linux_app/fft_ethernet_server.c \
    -o "$temp_dir/fft_ethernet_server"
"$cc_bin" "${common_flags[@]}" linux_app/fft_dma_bench.c \
    -o "$temp_dir/fft_dma_bench"

printf '%s\n' 'Repository checks passed.'
