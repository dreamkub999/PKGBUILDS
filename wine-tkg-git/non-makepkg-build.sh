#!/bin/bash

# Created by: Tk-Glitch <ti3nou at gmail dot com>

# This script replaces the wine-tkg PKGBUILD's function for use outside of makepkg or on non-pacman distros

## You can check for missing dependencies by running this script with either `--deps64` argument for 64-bit dependencies or `--deps32` argument for 32-bit dependencies :
# ./non-makepkg-build.sh --deps64
# ./non-makepkg-build.sh --deps32

## On a stock Ubuntu 19.04 install, you'll need the following deps as bare minimum to build default wine-tkg (without Faudio/winevulkan):
# pkg-config (or pkgconf) bison flex schedtool libfreetype6-dev xserver-xorg-dev libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev 
# For 32-bit support : gcc-multilib g++-multilib libfreetype6-dev:i386 xserver-xorg-dev:i386 libgstreamer1.0-dev:i386 libgstreamer-plugins-base1.0-dev:i386

## For proton-tkg, the 32-bit dependencies above are required as well as the following additions:
# curl fontforge fonttools libsdl2-dev python3-tk
# !!! _sdl_joy_support="true" (default setting) would require libsdl2-dev:i386 but due to a conflict between libsdl2-dev:i386 and libmirclientcpp-dev (at least on 19.04) you're kinda frogged and should set _sdl_joy_support to "false" to build successfully. You'll lose SDL2 support on 32-bit apps !!!

## You're on your own to resolve additional dependencies you might want to build with, such as Faudio.

pkgname=wine-tkg-git

_stgsrcdir='wine-staging-git'
_esyncsrcdir='esync'
_where=$PWD # track basedir as different Arch based distros are moving srcdir around

# set srcdir, Arch style
mkdir -p "$_where"/src
srcdir="$_where"/src

# use msg2, error and pkgver funcs for compat
msg2() {
 echo -e " \033[1;34m->\033[1;0m \033[1;1m$1\033[1;0m" >&2
}
error() {
 echo -e " \033[1;31m->\033[1;0m \033[1;1m$1\033[1;0m" >&2
}
pkgver() {
	if [ "$_use_staging" == "true" ]; then
	  cd "${srcdir}/${_stgsrcdir}"
	else
	  cd "${srcdir}/${_winesrcdir}"
	fi

	# retrieve current wine version - if staging is enabled, staging version will be used instead
	_describe_wine
}

  # The dependency "helper" (running configure) doesn't have to go through the initial prompt, so skip it
  if [ "$1" == "--deps64" ] || [ "$1" == "--deps32" ]; then
    _DEPSHELPER=1
  fi

  # load functions
  source "$_where"/wine-tkg-scripts/prepare.sh
  source "$_where"/wine-tkg-scripts/build.sh

  msg2 "Non-makepkg build script will be used.\n"

# init step
  _init

  # this script makes external builds already and we don't want the specific pacman-related stuff to interfere, so enforce _EXTERNAL_INSTALL="false" when not building proton-tkg
  if [ "$_EXTERNAL_INSTALL" == "true" ] && [ "$_EXTERNAL_INSTALL_TYPE" != "proton" ]; then
    _EXTERNAL_INSTALL="false"
  fi

  # disable faudio check so we don't fail to build even if faudio libs are missing
  _faudio_ignorecheck="true"

  _pkgnaming

  # remove the faudio pkgname tag as we can't be sure it'll get used even if enabled
  pkgname="${pkgname/-faudio-git/}"
# init step end

  # Wine source
  if [ "$_plain_mirrorsrc" == "true" ]; then
    _winesrcdir="wine-mirror-git"
    _winesrctarget="https://github.com/wine-mirror/wine.git"
  else
    _winesrcdir="wine-git"
    _winesrctarget="git://source.winehq.org/git/wine.git"
  fi

  find "$_where"/wine-tkg-patches -type f -not -path "*hotfixes*" -exec cp -n {} "$_where" \; # copy patches inside the PKGBUILD's dir to preserve makepkg sourcing and md5sum checking
  cp "$_where"/wine-tkg-userpatches/*.my* "$_where" 2>/dev/null # copy userpatches inside the PKGBUILD's dir


  ## Handle git repos similarly to makepkg to preserve repositories when building both with and without makepkg on Arch
  # Wine source
  cd "$_where"
  git clone --mirror "${_winesrctarget}" "$_winesrcdir"

  # Wine staging source
  if [ "$_use_staging" == "true" ]; then
    git clone --mirror https://github.com/wine-staging/wine-staging.git "$_stgsrcdir"
  fi

  pushd "$srcdir" &>/dev/null

  # Wine staging update and checkout
  if [ "$_use_staging" == "true" ]; then
    cd "$_where"/"${_stgsrcdir}"
    if [[ "https://github.com/wine-staging/wine-staging.git" != "$(git config --get remote.origin.url)" ]] ; then
      echo "${_stgsrcdir} is not a clone of ${_stgsrcdir}. Please delete ${_winesrcdir} and src dirs and try again."
      exit 1
    fi
    git fetch --all -p
    rm -rf "${srcdir}/${_stgsrcdir}" && git clone "$_where"/"${_stgsrcdir}" "${srcdir}/${_stgsrcdir}"
    cd "${srcdir}"/"${_stgsrcdir}"
    git checkout --force --no-track -B makepkg origin/HEAD
    if [ -n "$_staging_version" ] && [ "$_use_staging" == "true" ]; then
      git checkout "${_staging_version}"
    fi
  fi

  # Wine update and checkout
  cd "$_where"/"${_winesrcdir}"
  if [[ "${_winesrctarget}" != "$(git config --get remote.origin.url)" ]] ; then
    echo "${_winesrcdir} is not a clone of ${_winesrcdir}. Please delete ${_winesrcdir} and src dirs and try again."
    exit 1
  fi
  git fetch --all -p
  rm -rf "${srcdir}/${_winesrcdir}" && git clone "$_where"/"${_winesrcdir}" "${srcdir}/${_winesrcdir}"
  cd "${srcdir}"/"${_winesrcdir}"
  git checkout --force --no-track -B makepkg origin/HEAD
  if [ -n "$_plain_version" ] && [ "$_use_staging" != "true" ]; then
    git checkout "${_plain_version}"
  fi

  popd &>/dev/null

nonuser_patcher() {
  if [ "$_NUKR" != "debug" ] || [ "$_DEBUGANSW1" == "y" ]; then
    msg2 "Applying ${_patchname}" && patch -Np1 < "$_where"/"$_patchname" && echo "${_patchmsg}" >> "$_where"/last_build_config.log
  fi
}

build_wine_tkg() {

  set -e

  pkgver=$(pkgver)

  ## prepare step
  cd "$srcdir"
  # state tracker start - FEAR THE MIGHTY FROG MINER
  touch "${_where}"/BIG_UGLY_FROGMINER

  # mingw-w64-gcc
  if [ "$_NOMINGW" == "true" ]; then
    _configure_args+=(--without-mingw)
  fi

  _source_cleanup
  _prepare
  ## prepare step end

  _prebuild_common

  if [ -z "$_nomakepkg_prefix_path" ]; then
    local _prefix="$_where/${pkgname}-${pkgver}"
  else
    local _prefix="${_nomakepkg_prefix_path}/${pkgname}-${pkgver}"
  fi
  local _lib32name="lib32"
  local _lib64name="lib"

  # configure args
  if [ -n "$_configure_userargs64" ]; then
    _configure_args64+=($_configure_userargs64)
  fi
  if [ -n "$_configure_userargs32" ]; then
    _configure_args32+=($_configure_userargs32)
  fi

  # External install
  if [ "$_EXTERNAL_INSTALL" == "true" ]; then
    if [ "$_EXTERNAL_INSTALL_TYPE" != "proton" ]; then
      _prefix="$_DEFAULT_EXTERNAL_PATH/$pkgname-$_realwineversion"
    elif [ "$_EXTERNAL_INSTALL_TYPE" == "proton" ]; then
      #_prefix="$_where"
      _configure_args+=(--without-curses)
    fi
  #else
  #  _configure_args64+=(--libdir="$_prefix/$_lib64name")
  #  _configure_args32+=(--libdir="$_prefix/$_lib32name")
  fi

  _build
  _package_nomakepkg
}

if [ "$1" == "--deps64" ]; then
  cd "${srcdir}"/"${_winesrcdir}"
  ./configure --enable-win64
elif [ "$1" == "--deps32" ]; then
  cd "${srcdir}"/"${_winesrcdir}"
  ./configure
else
  build_wine_tkg
fi

trap _exit_cleanup EXIT
