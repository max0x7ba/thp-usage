#!/usr/bin/env python3

# Copyright (c) 2021 Maxim Egorushkin. MIT License. See the full licence in file LICENSE.

from pathlib import Path
import re
import sys


def find_thp_users():
    re_huge = re.compile(rb'AnonHugePages:\s*(\d+)\s*kB\s*')
    for smap in Path('/proc').glob('*/smaps'):
        try:
            huge_kb = 0
            for line in open(smap, 'rb'):
                if m := re_huge.match(line):
                    huge_kb += int(m[1])
            if huge_kb:
                p = smap.parent
                pid = int(p.name)
                cmdline = open(p.joinpath('cmdline'), 'r').read().replace('\0', ' ').strip()
                yield pid, huge_kb, cmdline
        except OSError as e:
            print(e, file=sys.stderr)


def get_huge_page_size():
    re_huge_page_size = re.compile(rb'Hugepagesize:\s*(\d+)\s*kB\s*')
    for line in open('/proc/meminfo', 'rb'):
        if m := re_huge_page_size.match(line):
            return int(m[1])
    raise RuntimeError('/proc/meminfo: no Hugepagesize line.')


def main():
    row_fmt = '{:>7}\t{:>8}\t{:>12}\t{}'.format
    n_fmt = '{:,d}'.format
    print(row_fmt('pid', 'pages', 'MB', 'cmdline'))

    hps_kb = get_huge_page_size()
    total_huge_kb = 0
    for pid, huge_kb, cmdline in sorted(find_thp_users(), reverse=True, key=lambda u: u[1]):
        total_huge_kb += huge_kb
        print(row_fmt(pid, n_fmt(huge_kb // hps_kb), n_fmt(huge_kb // 1024), cmdline))

    print(row_fmt(0, n_fmt(total_huge_kb // hps_kb), n_fmt(total_huge_kb // 1024), '<total>'))


if __name__ == "__main__":
    main()


# Local Variables:
# python-indent-offset: 4
# tab-width: 4
# indent-tabs-mode: nil
# coding: utf-8
# End:
