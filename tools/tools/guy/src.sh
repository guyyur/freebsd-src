#!/bin/sh

if [ "`id -u`" != "0" ]; then
  echo "sorry, this must be done as root." 1>&2
  exit 1
fi

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin

# target_archs="aarch64 amd64"
target_aarch64="arm64"
target_amd64="amd64"
kernconf_aarch64="MYFULLHW"
kernconf_amd64="MYFULLHW"
without_debug_files="WITHOUT_DEBUG_FILES="
# without_debug_files=""
# makeobjdirprefix=/usr/obj/fbsd-head

# export MAKEOBJDIRPREFIX=${makeobjdirprefix}


usage()
{
  cat 1>&2 <<EOF
usage: src.sh command [options]

Commands:
  clean ARCH [ARCH ...]
  build ARCH [ARCH ...]
  package ARCH [ARCH ...]
  packages ARCH [ARCH ...]
  update-kernel
  cleanup-kernel
  update-world
  cleanup-world
  update-loader
  install-chroot-native-xtools
  update-chroot

Options for build:
  -jN
EOF
}


clean()
{
  local target_archs
  
  # check for -z "$@" doesn't work correctly, expands to separate words
  if [ -z "$1" ]; then
    usage
    exit 1
  fi
  
  target_archs=$@
  
  local machine_arch target_arch target kernconf
  machine_arch="$(uname -p)"
  for target_arch in ${target_archs}; do
    eval target=\${target_${target_arch}}
    if [ -z "${target}" ]; then
      echo "empty target for ${target_arch}" 1>&2
      exit 1
    fi
    eval kernconf=\${kernconf_${target_arch}}
    if [ -z "${kernconf}" ]; then
      echo "empty kernconf for ${target_arch}" 1>&2
      exit 1
    fi
    
    export TARGET=${target} TARGET_ARCH=${target_arch}
    make ${j_option} cleanworld
    make ${j_option} cleankernel KERNCONF="${kernconf}"
    unset TARGET TARGET_ARCH
  done
}


build()
{
  local j_option target_archs
  j_option="-j4"
  
  # check for -z "$@" doesn't work correctly, expands to separate words
  if [ -z "$1" ]; then
    usage
    exit 1
  fi
  
  for arg in $@; do
    case $arg in
      -j*)
        j_option=$arg
        ;;
      -*)
        echo "unknown option: $arg" 1>&2
        usage
        exit 1
        ;;
      *)
        target_archs="${target_archs} $arg"
        ;;
    esac
  done
  target_archs="${target_archs# }"
  
  local machine_arch target_arch target kernconf
  machine_arch="$(uname -p)"
  for target_arch in ${target_archs}; do
    eval target=\${target_${target_arch}}
    if [ -z "${target}" ]; then
      echo "empty target for ${target_arch}" 1>&2
      exit 1
    fi
    eval kernconf=\${kernconf_${target_arch}}
    if [ -z "${kernconf}" ]; then
      echo "empty kernconf for ${target_arch}" 1>&2
      exit 1
    fi
    
    export TARGET=${target} TARGET_ARCH=${target_arch}
    make ${j_option} -DNO_CLEAN buildworld
    make ${j_option} buildkernel KERNCONF="${kernconf}"
    if [ "${machine_arch}" != "${target_arch}" ]; then
      make ${j_option} native-xtools
    fi
    unset TARGET TARGET_ARCH
  done
}


package()
{
  local target_archs
  
  # check for -z "$@" doesn't work correctly, expands to separate words
  if [ -z "$1" ]; then
    usage
    exit 1
  fi
  
  target_archs=$@
  
  local revision branch git_revision timestamp workdir packagedir_prefix
  revision="$(awk -F= '/^REVISION/ { gsub("\"",""); print $2 }' sys/conf/newvers.sh)"
  branch="$(awk -F= '/^BRANCH/ { sub("\\${BRANCH_OVERRIDE:-",""); sub("}",""); gsub("\"",""); print $2 }' sys/conf/newvers.sh)"
  git_revision="$(git rev-parse --verify --short HEAD 2>/dev/null)"
  timestamp=$(date +%Y%m%d)
  workdir="/usr/wrkdir_tmp/src-dist"
  packagedir_prefix="/usr/wrkdir_tmp/${revision}"
  version_id="${revision}-${branch}-${timestamp}-${git_revision}.txt"
  
  if [ -e "${workdir}" ]; then
    chflags -R noschg "${workdir}"
    rm -Rf "${workdir}"
  fi
  
  local machine_arch
  machine_arch="$(uname -p)"
  
  local target_arch target kernconf packagedir
  for target_arch in ${target_archs}; do
    eval target=\${target_${target_arch}}
    if [ -z "${target}" ]; then
      echo "empty target for ${target_arch}" 1>&2
      exit 1
    fi
    eval kernconf=\${kernconf_${target_arch}}
    if [ -z "${kernconf}" ]; then
      echo "empty kernconf for ${target_arch}" 1>&2
      exit 1
    fi
    
    packagedir="${packagedir_prefix}-${target_arch}"
    if [ -e "${packagedir}" ]; then
      rm -Rf "${packagedir}"
    fi
    mkdir "${packagedir}"
    touch "${packagedir}/${version_id}"
    
    export TARGET=${target} TARGET_ARCH=${target_arch}
    
    mkdir "${workdir}"
    
    env DISTDIR="${workdir}" make -DNO_ROOT distributeworld
    cd tools/tools/guy
    env DESTDIR="${workdir}"/base make -DNO_ROOT -m $(realpath ../../../share/mk) delete-optional
    env DESTDIR="${workdir}"/base ./unused.sh delete
    env DESTDIR="${workdir}"/base ./fix_rc_scripts.sh
    cd ../../..
    env DISTDIR="${workdir}" make packageworld ${without_debug_files}
    mv "${workdir}"/*.txz "${packagedir}/"
    chflags -R noschg "${workdir}"/base
    
    # clean up unnecessary files before installing kernels
    rm -Rf "${workdir}"/base/usr/lib/debug
    
    # -D for DESTDIR is not documented for build command but works
    usr.sbin/etcupdate/etcupdate.sh build -B \
        -D "${workdir}"/base -M "TARGET_ARCH=${TARGET_ARCH} TARGET=${TARGET}" \
        "${packagedir}/etcupdate.tar.bz2"
    
    for kern in ${kernconf}; do
      env DISTDIR="${workdir}"/base make -DNO_ROOT distributekernel KERNCONF="${kern}"
      tar -cvJ -f "${packagedir}/kernel-${kern}.txz" -C "${workdir}"/base/kernel .
      rm -Rf "${workdir}"/base/kernel
    done
    
    rm -Rf "${workdir}"
    
    unset TARGET TARGET_ARCH
  done
}


packages()
{
  local target_archs
  
  if [ -z "$@" ]; then
    usage
    exit 1
  fi
  
  target_archs=$@
  
  local revision branch git_revision timestamp workdir distdir
  revision="$(awk -F= '/^REVISION/ { gsub("\"",""); print $2 }' sys/conf/newvers.sh)"
  branch="$(awk -F= '/^BRANCH/ { sub("\\${BRANCH_OVERRIDE:-",""); sub("}",""); gsub("\"",""); print $2 }' sys/conf/newvers.sh)"
  git_revision="$(git rev-parse --verify --short HEAD 2>/dev/null)"
  timestamp=$(date +%Y%m%d)
  wstagedir_prefix="/usr/wrkdir_tmp/wstage"
  kstagedir_prefix="/usr/wrkdir_tmp/kstage"
  sstagedir_prefix="/usr/wrkdir_tmp/sstage"
  repodir_prefix="/usr/wrkdir_tmp/${revision}"
  version_id="${revision}-${branch}-${timestamp}-${git_revision}.txt"
  
  local machine_arch
  machine_arch="$(uname -p)"
  
  local target_arch target kernconf wstagedir kstagedir sstagedir repodir
  for target_arch in ${target_archs}; do
    eval target=\${target_${target_arch}}
    if [ -z "${target}" ]; then
      echo "empty target for ${target_arch}" 1>&2
      exit 1
    fi
    eval kernconf=\${kernconf_${target_arch}}
    if [ -z "${kernconf}" ]; then
      echo "empty kernconf for ${target_arch}" 1>&2
      exit 1
    fi
    
    wstagedir="${wstagedir_prefix}-${target_arch}"
    kstagedir="${kstagedir_prefix}-${target_arch}"
    sstagedir="${sstagedir_prefix}-${target_arch}"
    repodir="${repodir_prefix}-${target_arch}"
    
    export TARGET=${target} TARGET_ARCH=${target_arch}
    
    make -DNO_ROOT packages ${without_debug_files} \
      WSTAGEDIR="${wstagedir}" \
      KSTAGEDIR="${kstagedir}" \
      SSTAGEDIR="${sstagedir}" \
      REPODIR="${repodir}" \
      KERNCONF="${kernconf}"
    
    unset TARGET TARGET_ARCH
  done
}


update_kernel()
{
  if [ -n "$1" ]; then
    usage
    exit 1
  fi
  
  make installkernel
}


cleanup_kernel()
{
  if [ -n "$1" ]; then
    usage
    exit 1
  fi
  
  chflags -R noschg /boot/kernel.old /usr/lib/debug/boot/kernel.old
  rm -Rf /boot/kernel.old /usr/lib/debug/boot/kernel.old
}


update_world()
{
  if [ -n "$1" ]; then
    usage
    exit 1
  fi
  
  etcupdate -p
  make installworld
  make delete-old
  etcupdate -B
  etcupdate resolve
  cd tools/tools/guy
  make -m $(realpath ../../../share/mk) delete-optional
  ./unused.sh delete
  ./fix_rc_scripts.sh
  cd ../../..
}


cleanup_world()
{
  if [ -n "$1" ]; then
    usage
    exit 1
  fi
  
  make delete-old-libs
}


update_loader()
{
  machine_arch="$(uname -p)"
  case "${machine_arch}" in
    "aarch64")
      efi_bootfile="BOOTAA64.EFI"
      ;;
    "amd64")
      efi_bootfile="BOOTX64.EFI"
      ;;
    *)
      printf "Unsupoorted arch for updating loader\n" 1>&2
      exit 1
      ;;
  esac
  install -c /boot/loader.efi /efi/EFI/BOOT/${efi_bootfile}
}


set_chroot_target()
{
  local elf_machine
  elf_machine=$(readelf -W -h "${DESTDIR}"/usr/lib/crt1.o | sed -n '/Machine:/s/ *Machine: *//p')
  case "${elf_machine}" in
    "Advanced Micro Devices x86-64")
      export TARGET=amd64
      export TARGET_ARCH=amd64
      ;;
    "AArch64")
      export TARGET=arm64
      export TARGET_ARCH=aarch64
      ;;
    *)
      printf "Cannot determine chroot machine and machine arch from /usr/lib/crt1.o\n" 1>&2
      exit 1
      ;;
  esac
}


set_up_crossbuild_overrides()
{
  cat >"$DESTDIR"/etc/cross-build-env.sh <<EOF
# source file for build env variables
export QEMU_EMULATING=1
export ABI_FILE=/usr/lib/crt1.o
EOF
  
  cat >"$DESTDIR"/etc/make.nxb.conf <<EOF
MACHINE=${TARGET}
MACHINE_ARCH=${TARGET_ARCH}
CC=/nxb-bin/usr/bin/cc
CPP=/nxb-bin/usr/bin/cpp
CXX=/nxb-bin/usr/bin/c++
NM=/nxb-bin/usr/bin/nm
LD=/nxb-bin/usr/bin/ld
OBJCOPY=/nxb-bin/usr/bin/objcopy
SIZE=/nxb-bin/usr/bin/size
STRIPBIN=/nxb-bin/usr/bin/strip
SED=/nxb-bin/usr/bin/sed
RANLIB=/nxb-bin/usr/bin/ranlib
YACC=/nxb-bin/usr/bin/yacc
MAKE=/nxb-bin/usr/bin/make
STRINGS=/nxb-bin/usr/bin/strings
AWK=/nxb-bin/usr/bin/awk
FLEX=/nxb-bin/usr/bin/flex
EOF
  
  local hlinks
  hlinks="
    usr/bin/env
    usr/bin/gzip
    usr/bin/head
    usr/bin/id
    usr/bin/limits
    usr/bin/make
    usr/bin/dirname
    usr/bin/diff
    usr/bin/makewhatis
    usr/bin/find
    usr/bin/gzcat
    usr/bin/awk
    usr/bin/touch
    usr/bin/sed
    usr/bin/patch
    usr/bin/install
    usr/bin/gunzip
    usr/bin/readelf
    usr/bin/sort
    usr/bin/tar
    usr/bin/wc
    usr/bin/xargs
    usr/sbin/chown
    bin/cp
    bin/cat
    bin/chmod
    bin/echo
    bin/expr
    bin/hostname
    bin/ln
    bin/ls
    bin/mkdir
    bin/mv
    bin/realpath
    bin/rm
    bin/rmdir
    bin/sleep
    sbin/sha256
    sbin/sha512
    sbin/md5
    sbin/sha1
    bin/sh
    bin/csh
    "
  
  for file in ${hlinks}; do
    install -l h "$DESTDIR/nxb-bin/${file}" "$DESTDIR/${file}"
  done
}


install_chroot_native_xtools()
{
  if [ -n "$1" ]; then
    usage
    exit 1
  fi
  
  if [ -z "${DESTDIR}" ]; then
    echo "DESTDIR not set" 1>&2
    exit 1
  fi
  
  set_chroot_target
  if [ "$(uname -p)" != "${TARGET_ARCH}" ]; then
    make native-xtools-install NXTP=/nxb-bin
    set_up_crossbuild_overrides
  fi
  unset TARGET TARGET_ARCH
}


update_chroot()
{
  if [ -n "$1" ]; then
    usage
    exit 1
  fi
  
  if [ -z "${DESTDIR}" ]; then
    echo "DESTDIR not set" 1>&2
    exit 1
  fi
  
  set_chroot_target
  etcupdate -p -D "${DESTDIR}"
  make installworld WITHOUT_DEBUG_FILES=
  make delete-old WITHOUT_DEBUG_FILES=
  etcupdate -B -D "${DESTDIR}"
  etcupdate resolve -D "${DESTDIR}"
  cd tools/tools/guy
  make -m $(realpath ../../../share/mk) delete-optional
  ./unused.sh delete
  ./fix_rc_scripts.sh
  cd ../../..
  make delete-old-libs
  if [ "$(uname -p)" != "${TARGET_ARCH}" ]; then
    make native-xtools-install NXTP=/nxb-bin
    set_up_crossbuild_overrides
  fi
  unset TARGET TARGET_ARCH
}


set -e

cd ../../..

cmd=$1
shift

case $cmd in
  clean)
    clean $@
    ;;
  build)
    build $@
    ;;
  package)
    package $@
    ;;
  packages)
    packages $@
    ;;
  update-kernel)
    update_kernel $@
    ;;
  cleanup-kernel)
    cleanup_kernel $@
    ;;
  update-world)
    update_world $@
    ;;
  cleanup-world)
    cleanup_world $@
    ;;
  update-loader)
    update_loader $@
    ;;
  install-chroot-native-xtools)
    install_chroot_native_xtools $@
    ;;
  update-chroot)
    update_chroot $@
    ;;
  *)
    usage
    exit 1
    ;;
esac
