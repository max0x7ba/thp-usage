# thp-usage
Provides utilities to help observing and measuring effects of Linux transparent huge pages.

Along with THP settings to minimize run-time of compute-heavy workloads.

## Utilities

* `thp-meminfo` reports accurate totals of physical RAM page frames usage by the entire system including huge page usage.
* `thp-usage` reports what processes use how many transparent huge page frames of RAM.

## THP settings
Linux default THP configuration cripples THP performance badly for all applications other than databases.

This is a global perversion hurting every Linux user to comfort the few corporations selling the databases and associated services.

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

Despite the reality:
* These databases are not default-installed software on desktop or workstation Linux distributions.
* The vast majority of Linux users (developers, data scientists, quant researchers, gamers, home servers, etc.) never run any of them.
* For the large class of batch/ML/quant/HPC workloads, aggressive THP (`always + defrag=always + tuned khugepaged`) is not only reasonable - it's often one of the highest-ROI single tuning knobs available on modern Linux (especially on recent kernels with improved compaction heuristics).
* The database-centric "disable THP" advice is actively harmful when blindly applied to throughput-oriented code.

### THP settings for compute-heavy workloads

This configuration is the opposite extreme of the conservative settings recommended for databases and tail-latency-sensitive services. Those recommendations cripple THP benefits for compute-heavy batch workloads like the ones targeted here.

The goal of this THP configuration is to minimize run-time of compute-heavy workloads with multi-MB datasets in multi-CPU systems with plenty of RAM, no NUMA and no swap disks. With datasets accessed in sequential fashion using aligned avx2 or wider load and store instructions, with loads and stores being the main bottleneck.

Linux distro default THP configuration is sub-optimal for compute-heavy workloads because:

* It postpones and delegates allocating huge pages to `khugepaged` kernel thread sometime in the future, when there are no huge pages immediately available to fulfil an allocation request. No huge pages available is the default and expected state.
* One sole low priority `khugepaged` kernel thread scans virtual memory areas (VMAs) of processes, scanning up to 16MB of eligible VMAs every 10 seconds, by default. Takes ~23 hours for `khugepaged` to scan 128GB of VMAs to collapse contiguous regions of 4kB pages into 2MB huge pages.
* Its THP speed-ups are only measurable in long-running processes (like ANN training), but not in quick/micro benchmarks.

This THP configuration, on the other hand, improves and maximises performance benefits of THP with immediate effect for compute-heavy workloads. It specifically seeks to undo or change any THP settings conflicting with the stated goal. Such as settings designed to limit memory allocation latency spikes or CPU bursts for databases or general-purpose software. It enables synchronous compaction precisely to minimize run-time of compute-heavy workloads with multi-MB datasets.

In addition to minimizing the run-time of compute-heavy workloads, the effect of this THP configuration is also immediately noticeable and measurable as at least 5% shorter run-time in all existing timed runs of relatively short-lived processes completing within seconds, such as benchmarks, parallel builds and unit-tests. Unaffected by always enabled THP in the kernel command line alone.

The two key extra configuration changes, in addition to enabling THP always:

* Always allocate transparent huge pages immediately upon kernel memory allocation syscalls. When no huge pages are available for allocation, defragment RAM into huge pages on the spot.
* `khugepaged` scans up to 8GB of eligible VMAs every 79 seconds. Which takes ~21 minutes for `khugepaged` to scan 128GB of VMAs. But now `khugepaged` collapses only any remaining memory regions which weren't collapsed during allocation.

# Setup

## Enable transparent huge pages on your system
The provided [THP settings](thp-always.service.d/thp-always.sh) minimize run-time of compute-heavy workloads. Feel free to adjust them for your particular use-cases and workloads.

All the settings cannot be set in the kernel command line and/or in sysctl configuration.

To apply the settings immediately run:
```
sudo ./thp-always.service.d/thp-always.sh
```

To apply the settings earliest while booting-up, install the systemd service (`WantedBy=basic.target` systemd target) with:
```
sudo ./install-thp-always.sh
```

# Using thp-meminfo
thp-meminfo reports accurate totals of physical RAM page frames used by the entire system.

## thp-meminfo example output
```
./thp-meminfo.sh
                  max_ptes_none:          64
                max_ptes_shared:          64
                  max_ptes_swap:           0
           scan_sleep_millisecs:      10,000
                  pages_to_scan:       4,096
                     full_scans:           2
                pages_collapsed:         793

                       MemTotal: 131,820,388 kB
                        MemFree: 117,469,332 kB
                   MemAvailable: 124,435,856 kB
                  AnonHugePages:   1,517,568 kB
                 ShmemHugePages:       2,048 kB
                 ShmemPmdMapped:           0 kB
                  FileHugePages:           0 kB
                  FilePmdMapped:           0 kB

             nr_shmem_hugepages:           1
              nr_file_hugepages:           0
  nr_anon_transparent_hugepages:         741
            pgdemote_`khugepaged`:           0
             pgsteal_`khugepaged`:           0
              pgscan_`khugepaged`:           0
          numa_huge_pte_updates:          31
          thp_migration_success:           0
             thp_migration_fail:           0
            thp_migration_split:           0
                thp_fault_alloc:       8,837
             thp_fault_fallback:           0
      thp_fault_fallback_charge:           0
             thp_collapse_alloc:         793
      thp_collapse_alloc_failed:           0
                 thp_file_alloc:           1
              thp_file_fallback:           0
       thp_file_fallback_charge:           0
                thp_file_mapped:           0
                 thp_split_page:           0
          thp_split_page_failed:           0
        thp_deferred_split_page:         698
                  thp_split_pmd:       1,014
       thp_scan_exceed_none_pte:       1,383
       thp_scan_exceed_swap_pte:           0
      thp_scan_exceed_share_pte:           0
                  thp_split_pud:           0
            thp_zero_page_alloc:           1
     thp_zero_page_alloc_failed:           0
                     thp_swpout:           0
            thp_swpout_fallback:           0
```

`thp_fault_alloc` counts immediately allocated THP.

`thp_collapse_alloc` counts THP collapsed by ``khugepaged`` at some later indeterminate time.

The ideal is to maximize `thp_fault_alloc` and minimize `thp_collapse_alloc`.

# Using thp-usage
thp-usage reports what processes use how many transparent huge page frames of RAM. Reading these metrics from /proc/*/smaps of all processes is what requires the root privilege.

The totals row is a simple sum of per-process metrics. Same THP page frames of RAM shared by multiple processes get summed more than once.

## thp-usage example output
My use case is machine learning using Ray Tune and PyTorch on CPU, and above change results in 5-15% faster machine learning with no code changes. Your results may differ, benchmark your application before and after applying the above change.


```
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

To find out what huges pages are used for in a process, the following command can be used:

```
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
THPeligible:    1
ProtectionKey:         0
VmFlags: rd wr mr mw me ac sd
```

In the above command, `-A` and `-B` parameters match `smaps` format of Linux-5.10. If the format is different on your system, you may like to adjust these parameters appropriately.

---

Copyright (c) 2021 Maxim Egorushkin. MIT License. See the full licence in file LICENSE.
