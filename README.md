# thp-usage
A script to show processes that use transparent huge pages on Linux.

## Setup
### Enable transparent huge pages on your system
```
$ sudo ./install-thp-always.sh
```

### Make Python always use transparent huge pages for memory allocations by using huge page aware [tcmalloc][1]
```
$ sudo apt-get --yes install libgoogle-perftools-dev patchelf
$ sudo cp --preserve=all $(readlink -f $(which python)){,.$(date +%Y%m%dT%H%M%S)~}
$ sudo patchelf --add-needed /usr/lib/x86_64-linux-gnu/libtcmalloc_minimal.so $(readlink -f $(which python))
```

My use case is machine learning using Ray Tune and PyTorch on CPU, and above change results in 5-15% faster machine learning with no code changes. Your results may differ, benchmark your application before and after applying the above change.

## Example output

```
$ sudo ./thp-usage.py
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

---

Copyright (c) 2021 Maxim Egorushkin. MIT License. See the full licence in file LICENSE.

[1]: https://google.github.io/tcmalloc/temeraire.html
