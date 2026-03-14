#!/bin/bash

function thp-meminfo {
    local name unit count

    for name in max_ptes_none max_ptes_shared max_ptes_swap scan_sleep_millisecs pages_to_scan full_scans pages_collapsed; do
        printf "%31s: %'11d\n" "$name" "$(cat /sys/kernel/mm/transparent_hugepage/khugepaged/$name)"
    done
    echo

    while read name count unit; do
        if [[ "$name" =~ ^Mem|([[:alpha:]](Pmd|Huge)) ]]; then
            printf "%32s %'11d %s\n" "$name" $count $unit
        fi
    done </proc/meminfo
    echo

    while read name count; do
        if [[ "$name" =~ thp|huge ]]; then
            printf "%31s: %'11d\n" "$name" $count
        fi
    done </proc/vmstat
    echo
}

# ~/src/thp-usage/thp-meminfo.sh
thp-meminfo
