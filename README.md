# thp-usage
The project provides utilities to report Linux transparent huge pages usage. The information is read from multiple sources, joined/merged/aggregated and formatted into a report.

Along with THP settings to minimize run-time of compute-heavy workloads.

## Utilities

* `thp-meminfo` reports accurate totals of physical RAM page frames usage by the entire system including huge page usage.
* `thp-usage` reports what processes use how many transparent huge page frames of RAM.

## THP settings
Linux defaults and many distro/cloud tunings prioritize avoiding regressions in databases and tail-latency-sensitive services -- often at the cost of leaving most other workloads with suboptimal THP performance.

### The "THP = bad" narrative is heavily database-centric

The overwhelming majority of public warnings, kernel documentation footnotes, distro tuning guides, and forum threads that say "disable THP" or "set defrag=never/madvise" come from exactly one cluster of applications:

* Redis
* PostgreSQL
* MySQL / MariaDB
* MongoDB
* Oracle DB
* some key-value stores / caches (Memcached, Aerospike, etc.)
* certain JVM-based services when running latency-sensitive workloads

These are the voices that have been loudest for ~10–15 years on this topic. Their tuning recommendations (often "never" or "defer+madvise") have been copied into countless blog posts, Ansible roles, cloud provider defaults, and even some kernel config fragments. That creates a strong impression that THP is broadly problematic.

Only databases (and similar tail-latency-sensitive services) are consistently hurt by aggressive THP. Almost all documented regressions from `defrag=always` / `enabled=always` fall into two categories:
* Synchronous compaction stalls hurting per-request or per-operation latency (databases, web servers with dynamic allocations, some game servers).
* Fork latency during background snapshots / persistence (Redis BGSAVE, PostgreSQL checkpoints, MongoDB WiredTiger snapshots) — because fork needs to split huge pages, which can be slow under high memory pressure.

While the ground reality is different:
* These databases are not default-installed software on desktop or workstation Linux distributions.
* The vast majority of Linux users (developers, data scientists, quant researchers, gamers, home servers, etc.) never run any of them.
* For the large class of batch/ML/quant/HPC workloads, aggressive THP (`always + defrag=always + tuned khugepaged`) is not only reasonable - it's often one of the highest-ROI single tuning knobs available on modern Linux (especially on recent kernels with improved compaction heuristics).
* The database-centric "disable THP" advice is actively harmful when blindly applied to throughput-oriented code.

### THP settings for compute-heavy workloads

This configuration is the opposite extreme of the default Linux THP settings, which trade most of THP performance benefits for compatibility with niche use-cases involving databases and tail-latency-sensitive services. These default "conservative" Linux THP settings for database compatibility cripple THP performance benefits badly for compute-heavy batch workloads like the ones targeted here.

The goal of this THP configuration is to minimize run-time of compute-heavy workloads with multi-GB datasets in multi-CPU systems with plenty of RAM, no NUMA and no swap disks. With datasets accessed in sequential fashion using aligned AVX2 or wider load and store instructions, with loads and stores being the main bottleneck. THP reduces data TLB misses for these large sequential access patterns, keeping the AVX2 pipeline fed.

TLB cache misses have to load/walk the page table of a process to resolve the virtual address to physical. Page tables of a process are accessed less frequently than anything else and aren't expected to remain unevicted in any level of CPU cache hierarchy by the time of the next page table walk in compute-heavy workloads. The page table walks make TLB cache misses most expensive and most detrimental to performance of compute-heavy workloads. THP is intended to minimize both TLB cache misses and the cost of page table walks by replacing a level of 512 page table entries with one 512× larger huge-page at the next higher level of page table hierarchy.

On x86-64, the 4-level page table hierarchy (or 5-level on some systems) collapses with huge pages: a 2MB PMD entry replaces 512×4kB PTEs (level 1), and a 1GB PUD entry replaces 512×2MB PMDs (level 2).

Linux distro default THP configuration is sub-optimal for compute-heavy workloads because:

* It disables the synchronous compaction, which postpones and delegates allocating huge pages to `khugepaged` kernel thread sometime in the future, when there are no huge pages immediately available to fulfil an allocation request. No huge pages available is the default and expected state.
* One sole low priority `khugepaged` kernel thread scans virtual memory areas (VMAs) of processes, scanning up to 16MB of eligible VMAs every 10 seconds, by default. Takes ~23 hours for `khugepaged` to scan 128GB of VMAs to collapse contiguous regions of 4kB pages into 2MB huge pages. One `khugepaged` kernel thread collapsing VMAs of multiple processes running simultaneously in other CPU cores is a text-book single-producer-multiple-consumers bottleneck, when adding more consumers/CPUs only makes consumers bottleneck more.
* Synchronous compaction disabled by default effectively makes THP unavailable for most processes, except long-running ones. THP speed-ups without synchronous compaction are only measurable in long-running processes (like ANN training), on a good day.

This THP configuration, on the other hand, improves and maximises performance benefits of THP with immediate effect for compute-heavy workloads. It specifically seeks to undo or change any THP settings conflicting with the stated goal. Such as settings designed to limit memory allocation latency spikes or CPU bursts for databases. It enables synchronous compaction precisely to minimize run-time of compute-heavy workloads with multi-GB datasets.

In addition to minimizing the run-time of compute-heavy workloads, the effect of this THP configuration is also immediately noticeable and measurable as at least 5% shorter run-time in all existing timed runs of relatively short-lived processes completing within seconds, such as benchmarks, parallel builds and unit-tests. This immediate performance improvement for any/all processes comes from enabling synchronous compaction, otherwise unavailable to achieve with any of `transparent_hugepage/enabled` and/or `madvise` parameters.

(Exact before and after timings are going to be published after benchmarking this updated THP configuration.)

The two key extra configuration changes, in addition to enabling THP always:

* Always allocate transparent huge pages immediately upon kernel memory allocation syscalls. When no huge pages are available for allocation, defragment RAM into huge pages on the spot -- the synchronous compaction.
* `khugepaged` scans up to 8GB of eligible VMAs every 79 seconds. Which takes ~21 minutes for `khugepaged` to scan 128GB of VMAs. But now `khugepaged` collapses only any remaining memory regions which weren't collapsed during allocation.

## Setup

### Enable transparent huge pages on your system
The provided [THP settings](thp-always.service.d/thp-always.sh) minimize run-time of compute-heavy workloads. Feel free to adjust them for your particular use-cases and workloads.

All the settings cannot be set in the kernel command line and/or in sysctl configuration.

To apply the settings immediately run:
```bash
sudo ./thp-always.service.d/thp-always.sh
```

To apply the settings earliest while booting-up, install the systemd service (`WantedBy=basic.target` systemd target) with:
```bash
sudo ./install-thp-always.sh
```

## Using thp-meminfo
thp-meminfo reports accurate totals of physical RAM page frames used by the entire system.

### thp-meminfo example output
```bash
./thp-meminfo.sh
                  max_ptes_none:          64
                max_ptes_shared:          64
                  max_ptes_swap:           0
           scan_sleep_millisecs:      79,000
                  pages_to_scan:   2,097,152
                     full_scans:       5,377
                pages_collapsed:      18,832

                       MemTotal: 131,820,396 kB
                        MemFree:   6,306,408 kB
                   MemAvailable:  96,734,056 kB
                  AnonHugePages:   2,072,576 kB
                 ShmemHugePages:      55,296 kB
                 ShmemPmdMapped:       2,048 kB
                  FileHugePages:           0 kB
                  FilePmdMapped:           0 kB

             nr_shmem_hugepages:          27
              nr_file_hugepages:           0
  nr_anon_transparent_hugepages:       1,012
            pgdemote_khugepaged:           0
             pgsteal_khugepaged:       6,230
              pgscan_khugepaged:       6,230
          numa_huge_pte_updates:       1,068
          thp_migration_success:      10,574
             thp_migration_fail:           0
            thp_migration_split:           0
                thp_fault_alloc:     455,942
             thp_fault_fallback:           0
      thp_fault_fallback_charge:           0
             thp_collapse_alloc:      16,558
      thp_collapse_alloc_failed:           2
                 thp_file_alloc:          33
              thp_file_fallback:           0
       thp_file_fallback_charge:           0
                thp_file_mapped:         120
                 thp_split_page:           0
          thp_split_page_failed:           0
        thp_deferred_split_page:      15,666
                  thp_split_pmd:      21,132
       thp_scan_exceed_none_pte:   1,673,921
       thp_scan_exceed_swap_pte:           0
      thp_scan_exceed_share_pte:      10,614
                  thp_split_pud:           0
            thp_zero_page_alloc:           1
     thp_zero_page_alloc_failed:           0
                     thp_swpout:           0
            thp_swpout_fallback:           0
```

`thp_fault_alloc` counts immediately allocated THP.

`thp_fault_fallback` counts failures to allocate THP immediately.

`thp_collapse_alloc` counts THP collapsed by ``khugepaged`` at some later indeterminate time.

The ideal is to maximize `thp_fault_alloc` and minimize `thp_collapse_alloc`.

The extreme ideal is for `thp_fault_fallback` to stay at 0. It means that synchronous compaction enabled by `defrag=always` has never failed to produce a huge page at allocation time. Which is strong empirical evidence that `defrag=always` works well in your environment.

In the above output, non-zero `thp_file_alloc` and `thp_file_mapped` come from `tmpfs` mounted into `/tmp` with extra `huge=within_size` mount option added into `/etc/fstab` for `/tmp` mount point.

## Using thp-usage
thp-usage reports what processes use how many transparent huge page frames of RAM. Reading these metrics from /proc/*/smaps of all processes is what requires the root privilege.

The totals row is a simple sum of per-process metrics. Same THP page frames of RAM shared by multiple processes get summed more than once.

### thp-usage example output
My use case is machine learning using Ray Tune and PyTorch on CPU, and above change results in 5-15% faster machine learning with no code changes. Your results may differ, benchmark your application before and after applying the above change.


```bash
sudo ./thp-usage.py
    pid	   pages	          MB	cmdline
 712676	   1,268	       2,536	ray::ImplicitFunc.train_buffered()
 711989	   1,070	       2,140	ray::ImplicitFunc.train_buffered()
 714214	   1,068	       2,136	ray::ImplicitFunc.train_buffered()
 712422	   1,064	       2,128	ray::ImplicitFunc.train_buffered()
 713737	   1,064	       2,128	ray::ImplicitFunc.train_buffered()
 711327	     864	       1,728	ray::ImplicitFunc.train_buffered()
 713076	     863	       1,726	ray::ImplicitFunc.train_buffered()
 713122	     863	       1,726	ray::ImplicitFunc.train_buffered()
 713498	     863	       1,726	ray::ImplicitFunc.train_buffered()
 714082	     863	       1,726	ray::ImplicitFunc.train_buffered()
 714235	     863	       1,726	ray::ImplicitFunc.train_buffered()
 712584	     862	       1,724	ray::ImplicitFunc.train_buffered()
 713152	     862	       1,724	ray::ImplicitFunc.train_buffered()
 710998	     861	       1,722	ray::ImplicitFunc.train_buffered()
 712577	     861	       1,722	ray::ImplicitFunc.train_buffered()
 711860	     860	       1,720	ray::ImplicitFunc.train_buffered()
 712579	     860	       1,720	ray::ImplicitFunc.train_buffered()
 713716	     858	       1,716	ray::ImplicitFunc.train_buffered()
 712313	     857	       1,714	ray::ImplicitFunc.train_buffered()
 711680	     854	       1,708	ray::ImplicitFunc.train_buffered()
 713125	     811	       1,622	ray::ImplicitFunc.train_buffered()
 714329	     663	       1,326	ray::ImplicitFunc.train_buffered()
 712401	     661	       1,322	ray::ImplicitFunc.train_buffered()
 713097	     659	       1,318	ray::ImplicitFunc.train_buffered()
 710780	     635	       1,270	ray::ImplicitFunc.train_buffered()
 711244	     568	       1,136	ray::ImplicitFunc.train_buffered()
 713823	     460	         920	ray::ImplicitFunc.train_buffered()
 711992	     459	         918	ray::ImplicitFunc.train_buffered()
 712697	     360	         720	ray::ImplicitFunc.train_buffered()
 713819	     228	         456	ray::ImplicitFunc.train_buffered()
   3412	     197	         394	/usr/bin/influxd
 712180	     192	         384	ray::ImplicitFunc.train_buffered()
 712712	     192	         384	ray::ImplicitFunc.train_buffered()
 670968	     148	         296	python3 -m es.tune4 --samples 3000
   4128	      54	         108	/usr/bin/plasmashell
   4026	      35	          70	/usr/bin/kwin_x11
 670976	      22	          44	/home/max/anaconda3/envs/torch/lib/python3.8/site-packages/ray/core/src/ray/thirdparty/redis/src/redis-server ...
 670981	      19	          38	/home/max/anaconda3/envs/torch/lib/python3.8/site-packages/ray/core/src/ray/thirdparty/redis/src/redis-server ...
 670967	      18	          36	xz --best --stdout
   2219	      16	          32	/usr/lib/xorg/Xorg -nolisten tcp ...
 671000	       7	          14	/home/max/anaconda3/envs/torch/bin/python3 ...
 671065	       6	          12	/home/max/anaconda3/envs/torch/bin/python3 ...
 671027	       5	          10	/home/max/anaconda3/envs/torch/bin/python3 ...
 670988	       4	           8	/home/max/anaconda3/envs/torch/bin/python3 ...
   1335	       3	           6	/opt/piavpn/bin/pia-daemon
   4311	       3	           6	/usr/bin/konsole
 670986	       2	           4	/home/max/anaconda3/envs/torch/lib/python3.8/site-packages/ray/core/src/ray/gcs/gcs_server ...
   1261	       1	           2	/usr/sbin/rsyslogd -n -iNONE
   1298	       1	           2	/usr/lib/udisks2/udisksd
   4108	       1	           2	/usr/lib/x86_64-linux-gnu/libexec/kactivitymanagerd
   4136	       1	           2	/usr/bin/xembedsniproxy
   4168	       1	           2	/usr/lib/x86_64-linux-gnu/libexec/DiscoverNotifier
   4186	       1	           2	/usr/libexec/at-spi-bus-launcher --launch-immediately
 668856	       1	           2	/usr/libexec/xdg-desktop-portal
 671026	       1	           2	/home/max/anaconda3/envs/torch/lib/python3.8/site-packages/ray/core/src/ray/raylet/raylet ...
 704865	       1	           2	emacs
      0	  24,884	      49,768	<total>
```

## List VMAs using THP of a process

To find out what huge pages are used for in a process, the following command can be used:

```bash
grep -A10 -B13 "^AnonHugePages:[[:space:]]*[1-9]" /proc/670988/smaps
55c49328c000-55c493f05000 rw-p 00000000 00:00 0                          [heap]
Size:              12772 kB
KernelPageSize:        4 kB
MMUPageSize:           4 kB
Rss:               11508 kB
Pss:               11508 kB
Shared_Clean:          0 kB
Shared_Dirty:          0 kB
Private_Clean:         0 kB
Private_Dirty:     11508 kB
Referenced:        11508 kB
Anonymous:         11508 kB
LazyFree:              0 kB
AnonHugePages:      8192 kB
ShmemPmdMapped:        0 kB
FilePmdMapped:         0 kB
Shared_Hugetlb:        0 kB
Private_Hugetlb:       0 kB
Swap:                  0 kB
SwapPss:               0 kB
Locked:                0 kB
THPeligible:           1
ProtectionKey:         0
VmFlags: rd wr mr mw me ac sd
```

In the above command, `-A` and `-B` parameters match `smaps` format of Linux-5.10. If the format is different on your system, you may like to adjust these parameters appropriately.

## Profile TLB hits and misses of a process

THP currently apply to VMAs of anonymous mappings of a process, such as bss, heap, stack segments of a process.

JIT-compiled machine code can be placed into anonymous mappings of a process to be eligible for THP. AOT-compiled executable _sections_ of ELF files get mapped into read-only executable _segments_/VMAs of a process by [ld.so][3] run-time linker. THP for read-only executable VMAs of file mappings is supported by any of:

* [`tmpfs` mounted with `huge=` option][2].
* Any filesystem in kernels compiled with (non-default) `CONFIG_READ_ONLY_THP_FOR_FS=y` option.

Hence, THP reduce _data_ TLB (dTLB) misses and that requires no code changes.

_Instruction_ TLB (iTLB) misses in AOT-compiled machine code remain unaffected. Reducing iTLB misses requires extra efforts and changes to place machine code into huge pages.

`perf stat` command can be used to report performance metrics along with TLB misses of one or multiple running processes.

In the following example, running processes are filtered with `pgrep` by looking for "strat2" sub-string match in their full command lines, and, next, their metrics are collected for 60,000 milliseconds (1 minute). It filters 16 compute-heavy worker sub-processes doing linear algebra over subsets of one same 6GB dataset. The worker sub-processes bottleneck on loads missing the CPU caches and having to load from RAM, with `dTLB-load-misses` aggravating the cost of missing the CPU caches manyfold.

```bash
perf stat --timeout 60000 -dd -p $(pgrep -d, -f strat2)

 Performance counter stats for process id '6165,6166,...':

        960,943.86 msec task-clock                       #   16.000 CPUs utilized
               946      context-switches                 #    0.984 /sec
                36      cpu-migrations                   #    0.037 /sec
                 0      page-faults                      #    0.000 /sec
 4,132,571,611,917      cycles                           #    4.301 GHz                         (38.46%)
    52,053,252,274      stalled-cycles-frontend          #    1.26% frontend cycles idle        (38.46%)
18,602,539,243,885      instructions                     #    4.50  insn per cycle
 2,265,833,208,700      branches                         #    2.358 G/sec                       (38.46%)
     6,187,519,466      branch-misses                    #    0.27% of all branches             (38.46%)
 1,423,935,779,373      L1-dcache-loads                  #    1.482 G/sec                       (38.46%)
   244,214,713,841      L1-dcache-load-misses            #   17.15% of all L1-dcache accesses   (38.46%)
    14,774,880,613      L1-icache-loads                  #   15.375 M/sec                       (38.46%)
       149,276,068      L1-icache-load-misses            #    1.01% of all L1-icache accesses   (38.46%)
     1,033,452,910      dTLB-loads                       #    1.075 M/sec                       (38.46%)
        46,814,645      dTLB-load-misses                 #    4.53% of all dTLB cache accesses  (38.46%)
       387,890,751      iTLB-loads                       #  403.656 K/sec                       (38.46%)
         9,423,811      iTLB-load-misses                 #    2.43% of all iTLB cache accesses  (38.46%)
```

THP reduce the rate of `dTLB-load-misses`.

---

Copyright (c) 2021 Maxim Egorushkin. MIT License. See the full licence in file LICENSE.

[1]: https://docs.kernel.org/admin-guide/mm/transhuge.html
[2]: https://docs.kernel.org/admin-guide/mm/transhuge.html#hugepages-in-tmpfs-shmem
[3]: https://www.man7.org/linux/man-pages/man8/ld.so.8.html
