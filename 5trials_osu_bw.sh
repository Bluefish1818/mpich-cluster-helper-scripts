#!/bin/bash
cmd=(
    mpiexec
    -n 2
    -f machinefile_cross_2n_x_1p
    -iface eno1
    /mirror/mpiu/osu_bw_shortcut
)

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

"${cmd[@]}" 2>&1 | tee "$tmpdir/raw_sizes"
awk '/^[0-9]/ {print $1}' "$tmpdir/raw_sizes" > "$tmpdir/sizes"

files=("$tmpdir/sizes")

for i in {1..5}; do
    "${cmd[@]}" 2>&1 | tee "$tmpdir/raw_run$i"
    awk '/^[0-9]/ {print $2}' "$tmpdir/raw_run$i" > "$tmpdir/run$i"

    files+=("$tmpdir/run$i")
done

output="osu_bw_results.tsv"
paste "${files[@]}" | tee "$output"
echo "Results saved to: $(pwd)/$output"
