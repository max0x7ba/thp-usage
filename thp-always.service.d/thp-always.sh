#!/bin/bash

# Default Linux distro THP settings maximize compatibility rather than performance.
# To avoid regressing Linux distro benchmarks of several popular databases failing to adopt THP and taking a massive performance hit when THP is always enabled.
# Few Linux users ever care, install or run.these popular databases.
# The default THP settings for legacy compatibility cripple THP performance benefits for every user. These default settings delay the effects of THP till sometime later.
# Making it difficult to benchmark and assess the impact of THP because the effects of THP don't kick-in sometime later, depending on the total sum of allocated virtual memory regions. Many benchmarks of THP are oblivious to these datails, and, hence, produce wrong measurements and make wrong conclusions.

# The default THP settings crippling THP performance should ever be enabled for specific applications only.
# The following settings uncripple and maximize the positive effects of THP on performance.
# These should have been the default THP settings for everyone.

# Never fail mmap to reserve a virtual memory region. Fail when running out of RAM page frames only.
echo 1 > /proc/sys/vm/overcommit_memory

# Use transparent hugepages always, whenever possible.
echo always > /sys/kernel/mm/transparent_hugepage/enabled
# Allocate transparent hugepages immediately, whenever possible.
# Unlocks immediate maximum benefit of transparent hugepages, and makes khugepaged scanning and collapsing almost worthless.
echo always > /sys/kernel/mm/transparent_hugepage/defrag

# With defrag=always khugepaged becomes unnecessary and only marginally useful.
# The following settings apply to khugepaged only.

# khugepaged default configuration scans 4096 pages (16MB) every 10 seconds -- takes ~22 minutes to scan 128GB of virtual memory.
# 4kB pages at edges of the 16MB scan blocks cannot be collapsed into huge pages.
# The fragmentation introduced by the scan block size cripples THP positive effects.
# Reduce fragmentation caused by the default khugepaged scan block size by a factor of 512.
# Make khugepaged scan 8GB blocks every 79 seconds -- takes ~21 minutes to scan 128GB of virtual memory.
echo 79000 > /sys/kernel/mm/transparent_hugepage/khugepaged/scan_sleep_millisecs
echo 2097152 > /sys/kernel/mm/transparent_hugepage/khugepaged/pages_to_scan

# Minimize khugepaged waste of RAM.page frames.
# Don't collapse shorter regions of 4kB pages into a huge page if that requires allocating extra 64 page frames of RAM or more.
# Never allocate extra page frames if that requires any swapping out.
echo 64 > /sys/kernel/mm/transparent_hugepage/khugepaged/max_ptes_none
echo 64 > /sys/kernel/mm/transparent_hugepage/khugepaged/max_ptes_shared
echo 0 > /sys/kernel/mm/transparent_hugepage/khugepaged/max_ptes_swap
