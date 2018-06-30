
.if ${MK_BSNMP} == "no"
OPTIONAL_DIRS+= usr/share/snmp/mibs
OPTIONAL_DIRS+= usr/share/snmp/defs
OPTIONAL_DIRS+= usr/share/snmp
OPTIONAL_DIRS+= usr/include/bsnmp
.endif

.if ${MK_FREEBSD_UPDATE} == "no"
OPTIONAL_DIRS+= var/db/freebsd-update
.endif

.if ${MK_GAMES} == "no"
OPTIONAL_DIRS+= usr/shares/games/fortune
OPTIONAL_DIRS+= usr/shares/games
OPTIONAL_DIRS+= usr/games
.endif

.if ${MK_HYPERV} == "no"
OPTIONAL_DIRS+= var/db/hyperv
OPTIONAL_DIRS+= usr/libexec/hyperv
.endif

.if ${MK_IPFILTER} == "no"
OPTIONAL_DIRS+= var/db/ipf
OPTIONAL_DIRS+= usr/share/examples/ipfilter
.endif

.if ${MK_IPFW} == "no"
OPTIONAL_DIRS+= usr/share/examples/ipfw
.endif

.if ${MK_JAIL} == "no"
OPTIONAL_DIRS+= usr/share/examples/jails
.endif

.if ${MK_LIB32} == "no"
OPTIONAL_DIRS+= usr/lib32/private
OPTIONAL_DIRS+= usr/lib32/i18n
OPTIONAL_DIRS+= usr/lib32/dtrace
OPTIONAL_DIRS+= usr/lib32
.endif

.if ${MK_LPR} == "no"
OPTIONAL_DIRS+= var/spool/output/lpd
OPTIONAL_DIRS+= var/spool/output
OPTIONAL_DIRS+= var/spool/lpd
OPTIONAL_DIRS+= usr/libexec/lpr/ru
OPTIONAL_DIRS+= usr/libexec/lpr
.endif

.if ${MK_MAIL} == "no"
OPTIONAL_DIRS+= var/spool/mqueue
OPTIONAL_DIRS+= var/msgs
OPTIONAL_DIRS+= etc/mail
.endif

.if ${MK_NIS} == "no"
OPTIONAL_DIRS+= var/yp
.endif

.if ${MK_PF} == "no"
OPTIONAL_DIRS+= usr/share/examples/pf
.endif

.if ${MK_PPP} == "no"
OPTIONAL_DIRS+= var/run/ppp
OPTIONAL_DIRS+= etc/ppp
.endif

.if ${MK_SENDMAIL} == "no"
OPTIONAL_DIRS+= usr/share/sendmail
OPTIONAL_DIRS+= usr/libexec/sm.bin
OPTIONAL_DIRS+= usr/libexec/sendmail
.endif

.if ${MK_UNBOUND} == "no"
OPTIONAL_DIRS+= var/unbound/conf.d
OPTIONAL_DIRS+= var/unbound
.endif

.if ${MK_ZFS} == "no"
OPTIONAL_DIRS+= etc/zfs/compatibility.d
OPTIONAL_DIRS+= etc/zfs
# OPTIONAL_DIRS+= boot/zfs    # keep, otherwise loader freezes when doing cdboot
.endif
