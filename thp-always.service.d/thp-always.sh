#!/bin/bash

# Never fail mmap to reserve a virtual memory region. Fail when running out of RAM page frames only.
echo 1 > /proc/sys/vm/overcommit_memory

# Use transparent hugepages always, whenever possible.
echo always > /sys/kernel/mm/transparent_hugepage/enabled

# Allocate and defrag transparent hugepages immediately.
echo always > /sys/kernel/mm/transparent_hugepage/defrag

# Default settings take ~23 hours for khugepaged to scan 128GB of VMAs.
# Make khugepaged scan 8GB blocks every 79 seconds -- takes ~21 minutes to scan 128GB of VMAs.
echo 79000 > /sys/kernel/mm/transparent_hugepage/khugepaged/scan_sleep_millisecs
echo 2097152 > /sys/kernel/mm/transparent_hugepage/khugepaged/pages_to_scan

# Minimize waste of RAM page frames.

# Only collapse regions where at most 64 of 512 pages are unallocated
echo 64 > /sys/kernel/mm/transparent_hugepage/khugepaged/max_ptes_none

# Only collapse regions where at most 64 of 512 pages are shared
echo 64 > /sys/kernel/mm/transparent_hugepage/khugepaged/max_ptes_shared

# Never allocate extra page frames if that requires any swapping out.
echo 0 > /sys/kernel/mm/transparent_hugepage/khugepaged/max_ptes_swap
