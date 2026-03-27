#!/bin/bash

# Required Ubuntu packages:
# sudo apt install coreutils sed awk stress-ng icdiff

set -e

readonly repo_dir="$(dirname "$(realpath "$BASH_ARGV0")")"
cd "$repo_dir"

readonly cR="\e[31m" cG="\e[32m" cY="\e[33m" cB="\e[34m" cM="\e[35m" cC="\e[36m" cD="\e[0m"
function log {
    printf "%(%F %T)T %b${cD}\n" -1 "$1";
}

readonly thp_cfg_default=thp-always.service.d/thp-default.sh
readonly thp_cfg_always=thp-always.service.d/thp-always.sh

function load-thp-option-value {
    IFS= read value < "$thp_opt_path"
    if [[ "$value" =~ .*\[([[:alnum:]]+)\].* ]]; then
        value=${BASH_REMATCH[1]}
    fi
}

function load-thp-cfg {
    local thp_parameter_dir=/sys/kernel/mm/transparent_hugepage
    local value thp_opt_path thp_opt
    for thp_opt in enabled defrag khugepaged/{max_ptes_none,max_ptes_shared,max_ptes_swap,pages_to_scan,scan_sleep_millisecs}; do
        thp_opt_path="$thp_parameter_dir/$thp_opt"
        load-thp-option-value
        printf "echo %8s > $thp_opt_path\n" "$value"
    done
}

function bogo-ops-speedup {
    awk -f- "$@" <<"EOF"
/^matrix([[:space:]]+[[:digit:].]+)+/ && NF==9 {
    bogo_ops[file_idx++]=$6
}
END {
    bogo_ops_speedup_pct = ((bogo_ops[1] - bogo_ops[0]) / bogo_ops[0]) * 100
    printf "%+6.1f%% (before %10.2f, after %10.2f)\n", bogo_ops_speedup_pct, bogo_ops[0], bogo_ops[1]
}
EOF
}

function get-best-sched-opts {
    local -n opts=$1
    opts="chrt --fifo 10"
    $opts true || opts="sudo $opts"
    $opts true || opts="chrt --batch 0 nice -n-20"
    $opts true || opts="nice -n-20"
    $opts true || opts=""
}

function exit-on-signal {
    trap "log \"${cR}received $1, terminating.\"; exit 1" $1
}

# ~/src/thp-usage/thp-benchmark.sh
# v=1 n_cpus=2 n_ops=100 ~/src/thp-usage/thp-benchmark.sh
function thp-benchmark {(
    local -i n_cpus=${n_cpus:-1}
    local -i n_ops=${n_ops:-1000}
    local -i size=${size:-2048}
    local -i v=${v:-0}

    local log_dir=${log_dir:-/tmp/thp-benchmark}
    mkdir -p $log_dir

    local -i cpu_step=${cpu_step:-2}
    local cpu_list=${cpu_list:-"$(seq --separator=, 0 $cpu_step $((n_cpus * cpu_step - 1)))"}

    local sched_opts
    get-best-sched-opts sched_opts

    # --seed 0 makes the test reproducible.
    # --no-madvise disables the random advise options.
    local args="--matrix $n_cpus --taskset $cpu_list --matrix-ops $n_ops --matrix-size $size --no-madvise --seed 0 --metrics --perf"

    # stress-ng doesn't fail on signals.
    exit-on-signal SIGINT
    exit-on-signal SIGTERM

    local methods="copy negate mult add mean"
    for thp_cfg in default always; do
        local -n cfg_path=thp_cfg_${thp_cfg}
        log "${cY}Apply ${cG}${thp_cfg}${cY} THP settings."
        sed -E '/^echo/!d; s/ +/ /g' ${cfg_path}
        echo
        sudo bash -c "source ${cfg_path}"

        log "${cY}Benchmark with ${cG}${thp_cfg}${cY} THP settings."
        for method in $methods; do
            printf -v cmd "%s stress-ng --matrix-method %-6s %s" "$sched_opts" $method "$args"
            log "$cmd"
            $cmd > $log_dir/${thp_cfg}.${method}.log
        done
        echo
    done

    # Strip off stress-ng log line prefixes with pids.
    for method in $methods; do
        sed -i.orig.log -E 's/^[^]]+\] //; /^(skipped|passed|failed|metrics untrustworthy):/d' $log_dir/{default,always}.${method}.log
    done

    log "${cY}Benchmark results summary, bogo ops/s:"
    for method in $methods; do
        printf "%-6s: %s\n" $method "$(bogo-ops-speedup $log_dir/{default,always}.${method}.log)"
    done
    echo

    if((v>=1)); then
        log "${cY}Benchmark metrics comparison."
        for method in $methods; do
            icdiff --cols 200 --no-bold --show-no-spaces $log_dir/{default,always}.${method}.log | tee $log_dir/result.${method}.txt
            echo
        done
    fi
)}

# Save default THP configuration, if missing.
[[ -s $thp_cfg_default ]] || { load-thp-cfg > $thp_cfg_default; }

thp-benchmark
