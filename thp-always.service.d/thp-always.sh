#!/bin/bash

# for f in /sys/kernel/mm/transparent_hugepage/{enabled,defrag,khugepaged/defrag,khugepaged/max_ptes_none} /proc/sys/vm/overcommit_memory; do
#     echo -n "$f: "
#     cat $f
# done

echo always > /sys/kernel/mm/transparent_hugepage/enabled
echo defer+madvise > /sys/kernel/mm/transparent_hugepage/defrag
echo 0 > /sys/kernel/mm/transparent_hugepage/khugepaged/max_ptes_none
echo 1 > /proc/sys/vm/overcommit_memory

readonly max_ptes_shared_original=/run/max_ptes_shared.original.txt
if [[ ! -f $max_ptes_shared_original ]]; then
    readonly max_ptes_shared=/sys/kernel/mm/transparent_hugepage/khugepaged/max_ptes_shared
    declare -ri original_value=$(cat $max_ptes_shared)
    echo "$((original_value * 2 - 1))" > $max_ptes_shared
    echo "$original_value" > $max_ptes_shared_original
fi
