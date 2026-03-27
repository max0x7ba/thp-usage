#!/bin/bash

# Ubuntu 24.04 defaults.
echo madvise > /sys/kernel/mm/transparent_hugepage/enabled
echo defer+madvise > /sys/kernel/mm/transparent_hugepage/defrag
echo 511 > /sys/kernel/mm/transparent_hugepage/khugepaged/max_ptes_none
echo 256 > /sys/kernel/mm/transparent_hugepage/khugepaged/max_ptes_shared
echo 0 > /sys/kernel/mm/transparent_hugepage/khugepaged/max_ptes_swap
echo 4096 > /sys/kernel/mm/transparent_hugepage/khugepaged/pages_to_scan
echo 10000 > /sys/kernel/mm/transparent_hugepage/khugepaged/scan_sleep_millisecs
