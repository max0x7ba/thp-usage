# thp-usage
The project provides utilities to report Linux transparent huge pages usage. The information is read from multiple sources, joined/merged/aggregated and formatted into a report.

Along with THP settings to minimize run-time of compute-heavy workloads.

## Table of Contents

- [Utilities](#utilities)
- [THP settings](#thp-settings)
  - [The "THP = bad" narrative is heavily database-centric](#the-thp--bad-narrative-is-heavily-database-centric)
  - [THP settings for compute-heavy workloads](#thp-settings-for-compute-heavy-workloads)
- [Setup](#setup)
- [Using thp-meminfo](#using-thp-meminfo)
- [Using thp-usage](#using-thp-usage)
- [Using thp-benchmark](#using-thp-benchmark)
- [Tips](#tips)
  - [List VMAs using THP of a process](#list-vmas-using-thp-of-a-process)
  - [Profile TLB hits and misses of a process](#profile-tlb-hits-and-misses-of-a-process)

## Utilities

* `thp-meminfo` reports accurate totals of physical RAM page frames usage by the entire system including huge page usage.
* `thp-usage` reports what processes use how many transparent huge page frames of RAM.
* `thp-benchmark` runs stress-ng memory-bound benchmarks of default vs compute-heavy workload THP settings and reports benchmark timings side-by-side.

## THP settings
Linux defaults and many distro/cloud tunings prioritize avoiding regressions in databases and tail-latency-sensitive services -- often at the cost of leaving most other workloads with suboptimal [THP][1] performance.

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

The two key extra configuration changes, in addition to enabling THP always:

* Always allocate transparent huge pages immediately upon kernel memory allocation syscalls. When no huge pages are available for allocation, defragment RAM into huge pages on the spot -- the synchronous compaction.
* `khugepaged` scans up to 8GB of eligible VMAs every 79 seconds. Which takes ~21 minutes for `khugepaged` to scan 128GB of VMAs. But now `khugepaged` collapses only any remaining memory regions which weren't collapsed during allocation.

In addition to minimizing the run-time of compute-heavy workloads, the effect of this THP configuration is also immediately noticeable and measurable as at least 5% shorter run-time in all existing timed runs of relatively short-lived processes completing within seconds, such as benchmarks, parallel builds and unit-tests. This immediate performance improvement for any/all processes comes from enabling synchronous compaction, otherwise unavailable to achieve with any of `transparent_hugepage/enabled` and/or `madvise` parameters.

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

`thp_collapse_alloc` counts THP collapsed by `khugepaged` at some later indeterminate time.

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

## Using thp-benchmark

The provided benchmark compares timings of benchmark runs using default THP settings vs compute-heavy THP settings.

The benchmark requires (Ubuntu) packages `coreutils`, `sed`, `stress-ng`, `icdiff` to have been installed:
```
sudo apt install coreutils sed stress-ng icdiff
```

With the default settings, it times running 2,000 iterations of `stress-ng --matrix` memory-bound methods `copy` `negate`, `mult`, `add`, `mean` on `double[1024][1024]` (8MiB array) matrices using 1 CPU. Benchmarking using more than 1 CPU introduces noise of CPU contention delays into timings. For this reason, the benchmark defaults to using 1 CPU.

Takes ~3 seconds to run the benchmark with its default settings.

Enabling the compute-heavy THP settings should result in orders of magnitude reduction in "Cache DTLB Read Miss" metric relative to default THP settings.

### thp-benchmark example output

On AMD Ryzen 5825U (25W laptop CPU) running with `mitigations=off` kernel option, enabling the compute-heavy THP settings does reduce "Cache DTLB Read Miss" count by orders of magnitude, as expected. Which improves the run-time ("bogo ops/s (real time)" metric) of the benchmark method by 5-45%:

* `copy` does one load followed by one store, +11% speedup.
* `negate` does one load followed by negation (`xor` instruction flips the sign bit) and one store, +8% speedup. (The negation instruction normally loads.)
* `mult` does one load followed by multiplication and one store, +5% speedup. (The multiplication instruction normally loads.)
* `add` does two loads followed by addition and one store, +39% speedup. (The addition instruction normally loads.)
* `mean` does two loads followed by averaging and one store, +45% speedup.

Full output:
```bash
./thp-benchmark.sh

2026-03-25 08:33:00 Benchmark default THP settings with 1 CPUs (0) for 2000 operations.
echo madvise > /sys/kernel/mm/transparent_hugepage/enabled
echo madvise > /sys/kernel/mm/transparent_hugepage/defrag
echo 511 > /sys/kernel/mm/transparent_hugepage/khugepaged/max_ptes_none
echo 256 > /sys/kernel/mm/transparent_hugepage/khugepaged/max_ptes_shared
echo 0 > /sys/kernel/mm/transparent_hugepage/khugepaged/max_ptes_swap
echo 4096 > /sys/kernel/mm/transparent_hugepage/khugepaged/pages_to_scan
echo 10000 > /sys/kernel/mm/transparent_hugepage/khugepaged/scan_sleep_millisecs

2026-03-25 08:33:00 chrt --fifo 10 stress-ng --matrix 1 --taskset 0 --matrix-method copy --matrix-ops 2000 --matrix-size 1024 --no-madvise --seed 0 --metrics-brief --perf
2026-03-25 08:33:00 chrt --fifo 10 stress-ng --matrix 1 --taskset 0 --matrix-method negate --matrix-ops 2000 --matrix-size 1024 --no-madvise --seed 0 --metrics-brief --perf
2026-03-25 08:33:00 chrt --fifo 10 stress-ng --matrix 1 --taskset 0 --matrix-method mult --matrix-ops 2000 --matrix-size 1024 --no-madvise --seed 0 --metrics-brief --perf
2026-03-25 08:33:00 chrt --fifo 10 stress-ng --matrix 1 --taskset 0 --matrix-method add --matrix-ops 2000 --matrix-size 1024 --no-madvise --seed 0 --metrics-brief --perf
2026-03-25 08:33:01 chrt --fifo 10 stress-ng --matrix 1 --taskset 0 --matrix-method mean --matrix-ops 2000 --matrix-size 1024 --no-madvise --seed 0 --metrics-brief --perf

2026-03-25 08:33:01 Benchmark always THP settings with 1 CPUs (0) for 2000 operations.
echo 1 > /proc/sys/vm/overcommit_memory
echo always > /sys/kernel/mm/transparent_hugepage/enabled
echo always > /sys/kernel/mm/transparent_hugepage/defrag
echo 79000 > /sys/kernel/mm/transparent_hugepage/khugepaged/scan_sleep_millisecs
echo 2097152 > /sys/kernel/mm/transparent_hugepage/khugepaged/pages_to_scan
echo 64 > /sys/kernel/mm/transparent_hugepage/khugepaged/max_ptes_none
echo 64 > /sys/kernel/mm/transparent_hugepage/khugepaged/max_ptes_shared
echo 0 > /sys/kernel/mm/transparent_hugepage/khugepaged/max_ptes_swap

2026-03-25 08:33:01 chrt --fifo 10 stress-ng --matrix 1 --taskset 0 --matrix-method copy --matrix-ops 2000 --matrix-size 1024 --no-madvise --seed 0 --metrics-brief --perf
2026-03-25 08:33:01 chrt --fifo 10 stress-ng --matrix 1 --taskset 0 --matrix-method negate --matrix-ops 2000 --matrix-size 1024 --no-madvise --seed 0 --metrics-brief --perf
2026-03-25 08:33:01 chrt --fifo 10 stress-ng --matrix 1 --taskset 0 --matrix-method mult --matrix-ops 2000 --matrix-size 1024 --no-madvise --seed 0 --metrics-brief --perf
2026-03-25 08:33:02 chrt --fifo 10 stress-ng --matrix 1 --taskset 0 --matrix-method add --matrix-ops 2000 --matrix-size 1024 --no-madvise --seed 0 --metrics-brief --perf
2026-03-25 08:33:02 chrt --fifo 10 stress-ng --matrix 1 --taskset 0 --matrix-method mean --matrix-ops 2000 --matrix-size 1024 --no-madvise --seed 0 --metrics-brief --perf

2026-03-25 08:33:02 Compare benchmark results.

/tmp/thp-benchmark/default.copy.log                                                                 /tmp/thp-benchmark/always.copy.log
defaulting to a 1 day, 0 secs run per stressor                                                      defaulting to a 1 day, 0 secs run per stressor
dispatching hogs: 1 matrix                                                                          dispatching hogs: 1 matrix
stressor       bogo ops real time  usr time  sys time   bogo ops/s     bogo ops/s                   stressor       bogo ops real time  usr time  sys time   bogo ops/s     bogo ops/s
                          (secs)    (secs)    (secs)   (real time) (usr+sys time)                                             (secs)    (secs)    (secs)   (real time) (usr+sys time)
matrix             2000      0.19      0.18      0.00     10671.02       10617.57                   matrix             2000      0.17      0.17      0.00     11944.33       11868.52
matrix:                                                                                             matrix:
               823,348,728 CPU Cycles                     4.107 B/sec                                              643,626,721 CPU Cycles                     3.502 B/sec
               122,451,891 Instructions                   0.611 B/sec (0.149 instr. per cycle)                      96,049,538 Instructions                   0.523 B/sec (0.149 instr. per cycle)
                30,406,011 Branch Instructions            0.152 B/sec                                               26,782,007 Branch Instructions            0.146 B/sec
                    17,109 Branch Misses                 85.344 K/sec ( 0.056%)                                         13,815 Branch Misses                 75.157 K/sec ( 0.052%)
                 6,842,152 Stalled Cycles Frontend       34.131 M/sec                                                8,194,683 Stalled Cycles Frontend       44.581 M/sec
               500,546,990 Cache References               2.497 B/sec                                              511,017,959 Cache References               2.780 B/sec
                68,566,410 Cache Misses                   0.342 B/sec (13.698%)                                      4,728,541 Cache Misses                  25.725 M/sec ( 0.925%)
               556,390,848 Cache L1D Read                 2.775 B/sec                                              547,242,071 Cache L1D Read                 2.977 B/sec
               252,843,782 Cache L1D Read Miss            1.261 B/sec (45.444%)                                    253,477,697 Cache L1D Read Miss            1.379 B/sec (46.319%)
                 5,870,842 Cache L1D Prefetch            29.285 M/sec                                                5,787,101 Cache L1D Prefetch            31.483 M/sec
                 1,982,954 Cache L1I Read                 9.892 M/sec                                                2,029,147 Cache L1I Read                11.039 M/sec
                    46,006 Cache L1I Read Miss            0.229 M/sec                                                   59,353 Cache L1I Read Miss            0.323 M/sec
                 4,206,594 Cache DTLB Read               20.984 M/sec                                                    6,187 Cache DTLB Read               33.659 K/sec
                   387,330 Cache DTLB Read Miss           1.932 M/sec ( 9.208%)                                            479 Cache DTLB Read Miss           2.606 K/sec ( 7.742%)
                         0 Cache ITLB Read                0.000 /sec                                                         0 Cache ITLB Read                0.000 /sec
                       329 Cache ITLB Read Miss           1.641 K/sec                                                      178 Cache ITLB Read Miss         968.370 /sec
                23,827,098 Cache BPU Read                 0.119 B/sec                                               23,961,196 Cache BPU Read                 0.130 B/sec
                     4,505 Cache BPU Read Miss           22.472 K/sec ( 0.019%)                                          3,841 Cache BPU Read Miss           20.896 K/sec ( 0.016%)
               187,275,578 CPU Clock                      0.934 B/sec                                              167,389,647 CPU Clock                      0.911 B/sec
               187,217,046 Task Clock                     0.934 B/sec                                              167,315,812 Task Clock                     0.910 B/sec
                         9 Page Faults Total             44.895 /sec                                                         9 Page Faults Total             48.963 /sec
                         9 Page Faults Minor             44.895 /sec                                                         9 Page Faults Minor             48.963 /sec
                         0 Page Faults Major              0.000 /sec                                                         0 Page Faults Major              0.000 /sec
                         1 Context Switches               4.988 /sec                                                         1 Context Switches               5.440 /sec
                         1 Cgroup Switches                4.988 /sec                                                         1 Cgroup Switches                5.440 /sec
                         0 CPU Migrations                 0.000 /sec                                                         0 CPU Migrations                 0.000 /sec
                         0 Alignment Faults               0.000 /sec                                                         0 Alignment Faults               0.000 /sec
                         0 Emulation Faults               0.000 /sec                                                         0 Emulation Faults               0.000 /sec
                         1 Cgroup Switches                4.988 /sec                                                         1 Cgroup Switches                5.440 /sec
successful run completed in 0.20 secs                                                               successful run completed in 0.18 secs

/tmp/thp-benchmark/default.negate.log                                                               /tmp/thp-benchmark/always.negate.log
defaulting to a 1 day, 0 secs run per stressor                                                      defaulting to a 1 day, 0 secs run per stressor
dispatching hogs: 1 matrix                                                                          dispatching hogs: 1 matrix
stressor       bogo ops real time  usr time  sys time   bogo ops/s     bogo ops/s                   stressor       bogo ops real time  usr time  sys time   bogo ops/s     bogo ops/s
                          (secs)    (secs)    (secs)   (real time) (usr+sys time)                                             (secs)    (secs)    (secs)   (real time) (usr+sys time)
matrix             2000      0.17      0.17      0.00     11434.40       11393.48                   matrix             2000      0.16      0.16      0.00     12359.96       12306.56
matrix:                                                                                             matrix:
               760,223,035 CPU Cycles                     4.292 B/sec                                              613,148,993 CPU Cycles                     3.733 B/sec
               759,818,410 Instructions                   4.290 B/sec (0.999 instr. per cycle)                     738,495,191 Instructions                   4.497 B/sec (1.204 instr. per cycle)
                47,258,456 Branch Instructions            0.267 B/sec                                               45,798,347 Branch Instructions            0.279 B/sec
                    16,409 Branch Misses                 92.642 K/sec ( 0.035%)                                         17,655 Branch Misses                  0.108 M/sec ( 0.039%)
                15,786,849 Stalled Cycles Frontend       89.129 M/sec                                               14,929,936 Stalled Cycles Frontend       90.908 M/sec
               465,544,692 Cache References               2.628 B/sec                                              498,296,364 Cache References               3.034 B/sec
                82,636,752 Cache Misses                   0.467 B/sec (17.751%)                                      2,304,035 Cache Misses                  14.029 M/sec ( 0.462%)
               550,045,687 Cache L1D Read                 3.105 B/sec                                              536,613,884 Cache L1D Read                 3.267 B/sec
               253,632,967 Cache L1D Read Miss            1.432 B/sec (46.111%)                                    251,744,784 Cache L1D Read Miss            1.533 B/sec (46.914%)
                 4,254,596 Cache L1D Prefetch            24.020 M/sec                                                3,580,807 Cache L1D Prefetch            21.803 M/sec
                 4,998,811 Cache L1I Read                28.222 M/sec                                                5,216,213 Cache L1I Read                31.761 M/sec
                    59,029 Cache L1I Read Miss            0.333 M/sec                                                   78,070 Cache L1I Read Miss            0.475 M/sec
                 4,212,685 Cache DTLB Read               23.784 M/sec                                                    5,824 Cache DTLB Read               35.462 K/sec
                   294,998 Cache DTLB Read Miss           1.665 M/sec ( 7.003%)                                            341 Cache DTLB Read Miss           2.076 K/sec ( 5.855%)
                        25 Cache ITLB Read              141.144 /sec                                                         0 Cache ITLB Read                0.000 /sec
                       530 Cache ITLB Read Miss           2.992 K/sec (2120.000%)                                          355 Cache ITLB Read Miss           2.162 K/sec
                45,820,150 Cache BPU Read                 0.259 B/sec                                               43,327,517 Cache BPU Read                 0.264 B/sec
                     8,887 Cache BPU Read Miss           50.174 K/sec ( 0.019%)                                          8,582 Cache BPU Read Miss           52.255 K/sec ( 0.020%)
               174,761,027 CPU Clock                      0.987 B/sec                                              161,539,975 CPU Clock                      0.984 B/sec
               174,729,907 Task Clock                     0.986 B/sec                                              161,504,847 Task Clock                     0.983 B/sec
                         9 Page Faults Total             50.812 /sec                                                         9 Page Faults Total             54.801 /sec
                         9 Page Faults Minor             50.812 /sec                                                         9 Page Faults Minor             54.801 /sec
                         0 Page Faults Major              0.000 /sec                                                         0 Page Faults Major              0.000 /sec
                         1 Context Switches               5.646 /sec                                                         1 Context Switches               6.089 /sec
                         1 Cgroup Switches                5.646 /sec                                                         1 Cgroup Switches                6.089 /sec
                         0 CPU Migrations                 0.000 /sec                                                         0 CPU Migrations                 0.000 /sec
                         0 Alignment Faults               0.000 /sec                                                         0 Alignment Faults               0.000 /sec
                         0 Emulation Faults               0.000 /sec                                                         0 Emulation Faults               0.000 /sec
                         1 Cgroup Switches                5.646 /sec                                                         1 Cgroup Switches                6.089 /sec
successful run completed in 0.18 secs                                                               successful run completed in 0.16 secs

/tmp/thp-benchmark/default.mult.log                                                                 /tmp/thp-benchmark/always.mult.log
defaulting to a 1 day, 0 secs run per stressor                                                      defaulting to a 1 day, 0 secs run per stressor
dispatching hogs: 1 matrix                                                                          dispatching hogs: 1 matrix
stressor       bogo ops real time  usr time  sys time   bogo ops/s     bogo ops/s                   stressor       bogo ops real time  usr time  sys time   bogo ops/s     bogo ops/s
                          (secs)    (secs)    (secs)   (real time) (usr+sys time)                                             (secs)    (secs)    (secs)   (real time) (usr+sys time)
matrix             2000      0.17      0.17      0.00     11508.63       11464.73                   matrix             2000      0.16      0.16      0.00     12189.29       12136.73
matrix:                                                                                             matrix:
               756,008,322 CPU Cycles                     4.295 B/sec                                              618,858,770 CPU Cycles                     3.717 B/sec
               779,629,331 Instructions                   4.430 B/sec (1.031 instr. per cycle)                     745,965,969 Instructions                   4.480 B/sec (1.205 instr. per cycle)
                52,412,832 Branch Instructions            0.298 B/sec                                               44,772,019 Branch Instructions            0.269 B/sec
                    20,759 Branch Misses                  0.118 M/sec ( 0.040%)                                         21,008 Branch Misses                  0.126 M/sec ( 0.047%)
                15,849,361 Stalled Cycles Frontend       90.050 M/sec                                               14,266,243 Stalled Cycles Frontend       85.677 M/sec
               466,794,728 Cache References               2.652 B/sec                                              501,381,449 Cache References               3.011 B/sec
                83,995,065 Cache Misses                   0.477 B/sec (17.994%)                                      2,635,017 Cache Misses                  15.825 M/sec ( 0.526%)
               550,113,506 Cache L1D Read                 3.126 B/sec                                              537,992,635 Cache L1D Read                 3.231 B/sec
               256,232,366 Cache L1D Read Miss            1.456 B/sec (46.578%)                                    250,006,113 Cache L1D Read Miss            1.501 B/sec (46.470%)
                 5,937,931 Cache L1D Prefetch            33.737 M/sec                                                3,174,334 Cache L1D Prefetch            19.064 M/sec
                 5,018,020 Cache L1I Read                28.510 M/sec                                                4,604,782 Cache L1I Read                27.654 M/sec
                    48,765 Cache L1I Read Miss            0.277 M/sec                                                   70,139 Cache L1I Read Miss            0.421 M/sec
                 4,234,595 Cache DTLB Read               24.059 M/sec                                                    5,612 Cache DTLB Read               33.703 K/sec
                   292,604 Cache DTLB Read Miss           1.662 M/sec ( 6.910%)                                            377 Cache DTLB Read Miss           2.264 K/sec ( 6.718%)
                        48 Cache ITLB Read              272.718 /sec                                                         0 Cache ITLB Read                0.000 /sec
                       897 Cache ITLB Read Miss           5.096 K/sec (1868.750%)                                          221 Cache ITLB Read Miss           1.327 K/sec
                43,483,403 Cache BPU Read                 0.247 B/sec                                               43,571,918 Cache BPU Read                 0.262 B/sec
                     9,138 Cache BPU Read Miss           51.919 K/sec ( 0.021%)                                         10,841 Cache BPU Read Miss           65.106 K/sec ( 0.025%)
               173,593,272 CPU Clock                      0.986 B/sec                                              163,392,443 CPU Clock                      0.981 B/sec
               173,562,042 Task Clock                     0.986 B/sec                                              163,357,853 Task Clock                     0.981 B/sec
                         8 Page Faults Total             45.453 /sec                                                         8 Page Faults Total             48.045 /sec
                         8 Page Faults Minor             45.453 /sec                                                         8 Page Faults Minor             48.045 /sec
                         0 Page Faults Major              0.000 /sec                                                         0 Page Faults Major              0.000 /sec
                         1 Context Switches               5.682 /sec                                                         1 Context Switches               6.006 /sec
                         1 Cgroup Switches                5.682 /sec                                                         1 Cgroup Switches                6.006 /sec
                         0 CPU Migrations                 0.000 /sec                                                         0 CPU Migrations                 0.000 /sec
                         0 Alignment Faults               0.000 /sec                                                         0 Alignment Faults               0.000 /sec
                         0 Emulation Faults               0.000 /sec                                                         0 Emulation Faults               0.000 /sec
                         1 Cgroup Switches                5.682 /sec                                                         1 Cgroup Switches                6.006 /sec
successful run completed in 0.18 secs                                                               successful run completed in 0.17 secs

/tmp/thp-benchmark/default.add.log                                                                  /tmp/thp-benchmark/always.add.log
defaulting to a 1 day, 0 secs run per stressor                                                      defaulting to a 1 day, 0 secs run per stressor
dispatching hogs: 1 matrix                                                                          dispatching hogs: 1 matrix
stressor       bogo ops real time  usr time  sys time   bogo ops/s     bogo ops/s                   stressor       bogo ops real time  usr time  sys time   bogo ops/s     bogo ops/s
                          (secs)    (secs)    (secs)   (real time) (usr+sys time)                                             (secs)    (secs)    (secs)   (real time) (usr+sys time)
matrix             2000      0.33      0.32      0.00      6117.34        6105.47                   matrix             2000      0.24      0.23      0.00      8485.85        8459.41
matrix:                                                                                             matrix:
             1,414,286,688 CPU Cycles                     4.297 B/sec                                              902,395,704 CPU Cycles                     3.791 B/sec
             1,032,623,382 Instructions                   3.137 B/sec (0.730 instr. per cycle)                   1,008,319,220 Instructions                   4.236 B/sec (1.117 instr. per cycle)
                51,510,542 Branch Instructions            0.156 B/sec                                               46,170,926 Branch Instructions            0.194 B/sec
                    25,676 Branch Misses                 78.008 K/sec ( 0.050%)                                         18,360 Branch Misses                 77.134 K/sec ( 0.040%)
                19,773,730 Stalled Cycles Frontend       60.076 M/sec                                               21,489,587 Stalled Cycles Frontend       90.282 M/sec
               744,004,297 Cache References               2.260 B/sec                                              754,420,341 Cache References               3.169 B/sec
                59,604,544 Cache Misses                   0.181 B/sec ( 8.011%)                                      8,779,806 Cache Misses                  36.886 M/sec ( 1.164%)
               827,397,355 Cache L1D Read                 2.514 B/sec                                              794,298,669 Cache L1D Read                 3.337 B/sec
               388,454,816 Cache L1D Read Miss            1.180 B/sec (46.949%)                                    379,985,605 Cache L1D Read Miss            1.596 B/sec (47.839%)
                17,698,614 Cache L1D Prefetch            53.771 M/sec                                                4,503,622 Cache L1D Prefetch            18.921 M/sec
                 7,482,894 Cache L1I Read                22.734 M/sec                                                7,477,330 Cache L1I Read                31.414 M/sec
                    85,789 Cache L1I Read Miss            0.261 M/sec                                                   69,912 Cache L1I Read Miss            0.294 M/sec
                 6,303,215 Cache DTLB Read               19.150 M/sec                                                    9,824 Cache DTLB Read               41.273 K/sec
                 6,336,875 Cache DTLB Read Miss          19.252 M/sec (100.534%)                                           572 Cache DTLB Read Miss           2.403 K/sec ( 5.822%)
                         0 Cache ITLB Read                0.000 /sec                                                         0 Cache ITLB Read                0.000 /sec
                       667 Cache ITLB Read Miss           2.026 K/sec                                                      373 Cache ITLB Read Miss           1.567 K/sec
                42,314,490 Cache BPU Read                 0.129 B/sec                                               42,909,556 Cache BPU Read                 0.180 B/sec
                     9,369 Cache BPU Read Miss           28.464 K/sec ( 0.022%)                                          7,128 Cache BPU Read Miss           29.946 K/sec ( 0.017%)
               326,734,284 CPU Clock                      0.993 B/sec                                              235,575,375 CPU Clock                      0.990 B/sec
               326,704,218 Task Clock                     0.993 B/sec                                              235,539,952 Task Clock                     0.990 B/sec
                         9 Page Faults Total             27.343 /sec                                                         9 Page Faults Total             37.811 /sec
                         9 Page Faults Minor             27.343 /sec                                                         9 Page Faults Minor             37.811 /sec
                         0 Page Faults Major              0.000 /sec                                                         0 Page Faults Major              0.000 /sec
                         1 Context Switches               3.038 /sec                                                         1 Context Switches               4.201 /sec
                         1 Cgroup Switches                3.038 /sec                                                         1 Cgroup Switches                4.201 /sec
                         0 CPU Migrations                 0.000 /sec                                                         0 CPU Migrations                 0.000 /sec
                         0 Alignment Faults               0.000 /sec                                                         0 Alignment Faults               0.000 /sec
                         0 Emulation Faults               0.000 /sec                                                         0 Emulation Faults               0.000 /sec
                         1 Cgroup Switches                3.038 /sec                                                         1 Cgroup Switches                4.201 /sec
successful run completed in 0.33 secs                                                               successful run completed in 0.24 secs

/tmp/thp-benchmark/default.mean.log                                                                 /tmp/thp-benchmark/always.mean.log
defaulting to a 1 day, 0 secs run per stressor                                                      defaulting to a 1 day, 0 secs run per stressor
dispatching hogs: 1 matrix                                                                          dispatching hogs: 1 matrix
stressor       bogo ops real time  usr time  sys time   bogo ops/s     bogo ops/s                   stressor       bogo ops real time  usr time  sys time   bogo ops/s     bogo ops/s
                          (secs)    (secs)    (secs)   (real time) (usr+sys time)                                             (secs)    (secs)    (secs)   (real time) (usr+sys time)
matrix             2000      0.35      0.34      0.00      5754.79        5743.89                   matrix             2000      0.24      0.24      0.00      8380.62        8357.81
matrix:                                                                                             matrix:
             1,431,307,220 CPU Cycles                     4.092 B/sec                                              904,417,850 CPU Cycles                     3.755 B/sec
             1,293,282,688 Instructions                   3.698 B/sec (0.904 instr. per cycle)                   1,264,157,397 Instructions                   5.248 B/sec (1.398 instr. per cycle)
                48,625,452 Branch Instructions            0.139 B/sec                                               45,135,635 Branch Instructions            0.187 B/sec
                    23,358 Branch Misses                 66.786 K/sec ( 0.048%)                                         22,246 Branch Misses                 92.350 K/sec ( 0.049%)
                21,518,269 Stalled Cycles Frontend       61.526 M/sec                                               23,237,257 Stalled Cycles Frontend       96.466 M/sec
               756,685,466 Cache References               2.164 B/sec                                              758,384,617 Cache References               3.148 B/sec
                64,719,099 Cache Misses                   0.185 B/sec ( 8.553%)                                      2,843,806 Cache Misses                  11.806 M/sec ( 0.375%)
               830,333,320 Cache L1D Read                 2.374 B/sec                                              800,650,234 Cache L1D Read                 3.324 B/sec
               388,531,043 Cache L1D Read Miss            1.111 B/sec (46.792%)                                    381,909,096 Cache L1D Read Miss            1.585 B/sec (47.700%)
                15,333,682 Cache L1D Prefetch            43.843 M/sec                                                5,066,281 Cache L1D Prefetch            21.032 M/sec
                 8,022,012 Cache L1I Read                22.937 M/sec                                                8,541,661 Cache L1I Read                35.459 M/sec
                    77,183 Cache L1I Read Miss            0.221 M/sec                                                   81,899 Cache L1I Read Miss            0.340 M/sec
                 6,167,840 Cache DTLB Read               17.635 M/sec                                                    9,621 Cache DTLB Read               39.940 K/sec
                 6,205,337 Cache DTLB Read Miss          17.743 M/sec (100.608%)                                           546 Cache DTLB Read Miss           2.267 K/sec ( 5.675%)
                         0 Cache ITLB Read                0.000 /sec                                                         0 Cache ITLB Read                0.000 /sec
                       621 Cache ITLB Read Miss           1.776 K/sec                                                      304 Cache ITLB Read Miss           1.262 K/sec
                42,319,505 Cache BPU Read                 0.121 B/sec                                               42,843,584 Cache BPU Read                 0.178 B/sec
                    13,090 Cache BPU Read Miss           37.427 K/sec ( 0.031%)                                         14,483 Cache BPU Read Miss           60.124 K/sec ( 0.034%)
               347,354,974 CPU Clock                      0.993 B/sec                                              238,459,840 CPU Clock                      0.990 B/sec
               347,321,825 Task Clock                     0.993 B/sec                                              238,425,214 Task Clock                     0.990 B/sec
                         9 Page Faults Total             25.733 /sec                                                         9 Page Faults Total             37.362 /sec
                         9 Page Faults Minor             25.733 /sec                                                         9 Page Faults Minor             37.362 /sec
                         0 Page Faults Major              0.000 /sec                                                         0 Page Faults Major              0.000 /sec
                         1 Context Switches               2.859 /sec                                                         1 Context Switches               4.151 /sec
                         1 Cgroup Switches                2.859 /sec                                                         1 Cgroup Switches                4.151 /sec
                         0 CPU Migrations                 0.000 /sec                                                         0 CPU Migrations                 0.000 /sec
                         0 Alignment Faults               0.000 /sec                                                         0 Alignment Faults               0.000 /sec
                         0 Emulation Faults               0.000 /sec                                                         0 Emulation Faults               0.000 /sec
                         1 Cgroup Switches                2.859 /sec                                                         1 Cgroup Switches                4.151 /sec
successful run completed in 0.35 secs                                                               successful run completed in 0.24 secs
```


## Tips

### List VMAs using THP of a process

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

### Profile TLB hits and misses of a process

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
