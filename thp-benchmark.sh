#!/bin/bash

# Required Ubuntu packages:
# sudo apt install coreutils sed stress-ng icdiff

set -e

readonly repo_dir="$(dirname "$(realpath "$BASH_ARGV0")")"
cd "$repo_dir"

readonly cR="\e[31m" cG="\e[32m" cY="\e[33m" cB="\e[34m" cM="\e[35m" cC="\e[36m" cD="\e[0m"
function log { printf "%(%F %T)T %b${cD}\n" -1 "$1"; }
function log2 { printf "\n%(%F %T)T %b${cD}\n" -1 "$1"; }

readonly thp_cfg_dir=/sys/kernel/mm/transparent_hugepage

readonly thp_cfg_default=thp-always.service.d/thp-default.sh
readonly thp_cfg_always=thp-always.service.d/thp-always.sh

function load-thp-option-value {
    IFS= read value < "$thp_opt_path"
    if [[ "$value" =~ .*\[([[:alnum:]]+)\].* ]]; then
        value=${BASH_REMATCH[1]}
    fi
}

function load-thp-cfg {
    local value thp_opt_path thp_opt
    for thp_opt in enabled defrag khugepaged/{max_ptes_none,max_ptes_shared,max_ptes_swap,pages_to_scan,scan_sleep_millisecs}; do
        thp_opt_path="$thp_cfg_dir/$thp_opt"
        load-thp-option-value
        printf "echo %8s > $thp_opt_path\n" "$value"
    done
}

# ~/src/thp-usage/thp-benchmark.sh
# n_cpus=2 n_ops=100 ~/src/thp-usage/thp-benchmark.sh
function thp-benchmark {(
    local -i n_cpus=${n_cpus:-1}
    local -i n_ops=${n_ops:-2000}

    local log_dir=${log_dir:-/tmp/thp-benchmark}
    mkdir -p $log_dir

    local -i cpu_step=${cpu_step:-2}
    local cpu_list=${cpu_list:-"$(seq --separator=, 0 $cpu_step $((n_cpus * cpu_step - 1)))"}

    local sched_opts="chrt --fifo 10"
    $sched_opts true || sched_opts="sudo $sched_opts"
    $sched_opts true || sched_opts="chrt --batch 0 nice -n-20"
    $sched_opts true || sched_opts="nice -n-20"
    $sched_opts true || sched_opts=""

    local methods="mean copy add"
    for thp_cfg in default always; do
        local -n cfg_path=thp_cfg_${thp_cfg}
        log2 "${cY}Benchmark ${cG}${thp_cfg}${cY} THP settings with $n_cpus CPUs ($cpu_list) for $n_ops operations."
        sed -E '/^echo/!d; s/ +/ /g' ${cfg_path}
        sudo --shell source ${cfg_path}
        echo

        for method in $methods; do
            cmd="${sched_opts} stress-ng --matrix $n_cpus --taskset $cpu_list --matrix-method $method --matrix-ops $n_ops --matrix-size 1024 --no-madvise --seed 0 --metrics-brief --perf"
            log "$cmd"
            $cmd > $log_dir/${thp_cfg}.${method}.log
        done
    done

    log2 "${cY}Compare benchmark results."
    for method in $methods; do
        sed -i.orig.log -E 's/^[^]]+\] //; /^(skipped|passed|failed|metrics untrustworthy):/d' $log_dir/{default,always}.${method}.log
        echo; icdiff --cols 200 --no-bold --show-no-spaces $log_dir/{default,always}.${method}.log | tee $log_dir/result.${method}.txt
    done
)}

# Save default TCP configuration.
[[ -s $thp_cfg_default ]] || { load-thp-cfg > $thp_cfg_default; }

thp-benchmark
