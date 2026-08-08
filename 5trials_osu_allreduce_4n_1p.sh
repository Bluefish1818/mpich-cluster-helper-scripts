#!/bin/bash
cmd=(
    mpiexec
    -n 4
    -f machinefile_cross_4n_x_1p
    -iface eno1
    /mirror/mpiu/osu_allreduce_shortcut
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

output="osu_allreduce_4n_1p_results.tsv"
paste "${files[@]}" | tee "$output"
echo "Results saved to: $(pwd)/$output"
