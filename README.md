# log-exporter

1. log-exporter.sh
 - export all log and information about linux system
 - linux system log
   - dmesg
   - journalctl
   - xorg
 - installed package list
 - kernel driver in use
 - device info
 - user library

2. how to use
 - just execute script as root
```bash
$ ./log-exporter.sh
```
 - check tarball in /tmp/sysinfo.XXXXXXX


3. reference
 - https://github.com/linuxwacom/wacom-hid-descriptors/blob/master/scripts/sysinfo.sh
