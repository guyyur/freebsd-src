#!/bin/sh

if [ "`id -u`" != "0" ]; then
  echo "sorry, this must be done as root." 1>&2
  exit 1
fi

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin

target_archs="aarch64 amd64 armv7"
target_aarch64="arm64"
target_amd64="amd64"
target_armv7="arm"
kernconf_aarch64="MYHW MYVIRTHW"
kernconf_amd64="MYHW MYVIRTHW"
kernconf_armv7="MYHW"  # "MYHW MYVIRTHW"
qemu_arch_aarch64="aarch64"
qemu_arch_amd64="x86_64"
qemu_arch_armv7="arm"
# without_debug_files="WITHOUT_DEBUG_FILES="
without_debug_files=""


usage()
{
  cat 1>&2 <<EOF
usage: src.sh command [options]

Commands:
  build
  package
  update-kernel
  cleanup-kernel
  bootstrap-config
  update-world
  cleanup-world
  update-loader
  install-chroot-native-xtools
  bootstrap-chroot-config
  update-chroot

Options for build:
  -jN
  --clean
  --no_clean
  --native
  --non-native
EOF
}

build()
{
  local j_option clean_option native_option
  j_option="-j4"
  clean_option="-DNO_CLEAN"
  native_option=1
  
  for i in $@; do
    case $i in
      -j*)
        j_option=$i
        ;;
      --clean)
        clean_option=""
        ;;
      --no_clean)
        clean_option="-DNO_CLEAN"
        ;;
      --native)
        native_option=1
        ;;
      --non-native)
        native_option=0
        ;;
      *)
        usage
        exit 1
        ;;
    esac
  done
  
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
    
    if [ ${native_option} -eq 1 -a "${machine_arch}" = "${target_arch}" -o ${native_option} -eq 0 -a "${machine_arch}" != "${target_arch}" ]; then
      export TARGET=${target} TARGET_ARCH=${target_arch}
      make ${j_option} ${clean_option} buildworld || exit 1
      make ${j_option} buildkernel KERNCONF="${kernconf}" || exit 1
      if [ "${machine_arch}" != "${target_arch}" ]; then
        make ${j_option} ${clean_option} native-xtools || exit 1
      fi
      unset TARGET TARGET_ARCH
    fi
  done
}

package()
{
  if [ -n "$1" ]; then
    usage
    exit 1
  fi
  
  local revision branch git_revision timestamp workdir distdir
  revision="$(awk -F= '/^REVISION/ { gsub("\"",""); print $2 }' sys/conf/newvers.sh)"
  branch="$(awk -F= '/^BRANCH/ { sub("\\${BRANCH_OVERRIDE:-",""); sub("}",""); gsub("\"",""); print $2 }' sys/conf/newvers.sh)"
  git_revision="$(git rev-parse --verify --short HEAD 2>/dev/null)"
  timestamp=$(date +%Y%m%d)
  workdir="/usr/wrkdir_tmp/src-dist"
  distsdir="/usr/obj/${revision}-${branch}-${timestamp}-${git_revision}"
  
  if [ -e "${workdir}" ]; then
    chflags -R noschg "${workdir}" || exit 1
    rm -Rf "${workdir}" || exit 1
  fi
  
  if [ ! -e "${distsdir}" ]; then
    mkdir "${distsdir}" || exit 1
  fi
  
  local machine_arch target_arch target qemu_arch kernconf
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
    packagedir="${distsdir}/${target_arch}"
    
    if [ ! -e "${packagedir}" ]; then
      mkdir "${packagedir}" || exit 1
    fi
    
    export TARGET=${target} TARGET_ARCH=${target_arch}
    
    mkdir "${workdir}" || exit 1
    
    env DISTDIR="${workdir}" make distributeworld || exit 1
    ( cd tools/tools/guy && env DESTDIR="${workdir}"/base make -m $(realpath ../../../share/mk) delete-optional ) || exit 1
    ( cd tools/tools/guy && env DESTDIR="${workdir}"/base ./unused.sh delete ) || exit 1
    ( cd tools/tools/guy && env DESTDIR="${workdir}"/base ./fix_rc_scripts.sh ) || exit 1
    env DISTDIR="${workdir}" make packageworld ${without_debug_files} || exit 1
    mv "${workdir}"/*.txz "${packagedir}/" || exit 1
    chflags -R noschg "${workdir}"/base || exit 1
    
    # clean up unnecessary files before installing kernels
    rm -Rf "${workdir}"/base/usr/lib/debug || exit 1
    
    # install qemu-ARCH-static to be able to run kldxref
    eval qemu_arch=\${qemu_arch_${target_arch}}
    if [ "${machine_arch}" != "${target_arch}" ]; then
      install -d "${workdir}"/base/usr/local/bin || exit 1
      install /usr/local/bin/qemu-${qemu_arch}-static "${workdir}"/base/usr/local/bin/ || exit 1
    fi
    
    for i in ${kernconf}; do
      env DISTDIR="${workdir}"/base make distributekernel KERNCONF="${i}" || exit 1
      if [ "${machine_arch}" != "${target_arch}" ]; then
        chroot "${workdir}"/base kldxref /kernel/boot/kernel || exit 1
      fi
      ( cd "${workdir}"/base/kernel && tar cvJf "${packagedir}/kernel-${i}.txz" . ) || exit 1
      rm -Rf "${workdir}"/base/kernel || exit 1
    done
    
    rm -Rf "${workdir}" || exit 1
    
    unset TARGET TARGET_ARCH
  done
}

update_kernel()
{
  if [ -n "$1" ]; then
    usage
    exit 1
  fi
  
  make installkernel || exit 1
}

cleanup_kernel()
{
  if [ -n "$1" ]; then
    usage
    exit 1
  fi
  
  chflags -R noschg /boot/kernel.old /usr/lib/debug/boot/kernel.old || exit 1
  rm -Rf /boot/kernel.old /usr/lib/debug/boot/kernel.old || exit 1
}

bootstrap_config()
{
  if [ -n "$1" ]; then
    usage
    exit 1
  fi
  
  etcupdate extract || exit 1
}

update_world()
{
  if [ -n "$1" ]; then
    usage
    exit 1
  fi
  
  etcupdate -p || exit 1
  make installworld || exit 1
  make delete-old || exit 1
  etcupdate -B || exit 1
  etcupdate resolve || exit 1
  cd tools/tools/guy || exit 1
  make -m $(realpath ../../../share/mk) delete-optional || exit 1
  ./unused.sh delete || exit 1
  ./fix_rc_scripts.sh || exit 1
  cd ../../.. || exit 1
}

cleanup_world()
{
  if [ -n "$1" ]; then
    usage
    exit 1
  fi
  
  make delete-old-libs || exit 1
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
  install -c /boot/loader.efi /efi/EFI/BOOT/${efi_bootfile} || exit 1
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
    "ARM")
      export TARGET=arm
      export TARGET_ARCH=armv7
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
    install -l h "$DESTDIR/nxb-bin/${file}" "$DESTDIR/${file}" || exit 1
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
    make native-xtools-install NXTP=/nxb-bin || exit 1
    set_up_crossbuild_overrides
  fi
  unset TARGET TARGET_ARCH
}

bootstrap_chroot_config()
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
  etcupdate extract -D "${DESTDIR}" || exit 1
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
  etcupdate -p -D "${DESTDIR}" || exit 1
  make installworld WITHOUT_DEBUG_FILES= || exit 1
  make delete-old WITHOUT_DEBUG_FILES= || exit 1
  etcupdate -B -D "${DESTDIR}" || exit 1
  etcupdate resolve -D "${DESTDIR}" || exit 1
  cd tools/tools/guy || exit 1
  make -m $(realpath ../../../share/mk) delete-optional || exit 1
  ./unused.sh delete || exit 1
  ./fix_rc_scripts.sh || exit 1
  cd ../../.. || exit 1
  make delete-old-libs || exit 1
  if [ "$(uname -p)" != "${TARGET_ARCH}" ]; then
    make native-xtools-install NXTP=/nxb-bin || exit 1
    set_up_crossbuild_overrides
  fi
  unset TARGET TARGET_ARCH
}

cd ../../.. || exit 1

cmd=$1
shift

case $cmd in
  build)
    build $@
    ;;
  package)
    package $@
    ;;
  update-kernel)
    update_kernel $@
    ;;
  cleanup-kernel)
    cleanup_kernel $@
    ;;
  bootstrap-config)
    bootstrap_config $@
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
  bootstrap-chroot-config)
    bootstrap_chroot_config $@
    ;;
  update-chroot)
    update_chroot $@
    ;;
  *)
    usage
    exit 1
    ;;
esac
