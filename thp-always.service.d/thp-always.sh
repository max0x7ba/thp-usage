#!/bin/bash

# for f in /sys/kernel/mm/transparent_hugepage/{enabled,defrag,khugepaged/defrag,khugepaged/max_ptes_none} /proc/sys/vm/overcommit_memory; do
#     echo -n "$f: "
#     cat $f
# done

echo 1 > /proc/sys/vm/overcommit_memory

echo always > /sys/kernel/mm/transparent_hugepage/enabled
echo always > /sys/kernel/mm/transparent_hugepage/defrag

echo 64 > /sys/kernel/mm/transparent_hugepage/khugepaged/max_ptes_none
echo 64 > /sys/kernel/mm/transparent_hugepage/khugepaged/max_ptes_shared
echo 0 > /sys/kernel/mm/transparent_hugepage/khugepaged/max_ptes_swap
