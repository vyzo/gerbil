#!/bin/sh
set -eu

readonly FEATURES='libxml libyaml zlib sqlite mysql lmdb leveldb'
readonly OPTIONS='gsc'

enable_libxml='#f'
enable_libyaml='#f'
enable_zlib='#t'
enable_sqlite='#t'
enable_mysql='#f'
enable_lmdb='#f'
enable_leveldb='#f'

with_gsc='gsc'

feature_exists() {
  case " $FEATURES " in
    *" $1 "*) return 0;;
  esac
  return 1
}

set_feature_enable() {
  feature="$1"
  enable="$2"
  if ! feature_exists "$feature"; then
    printf 'configure.sh: unknown feature "%s".\n' "$feature" >&2
    exit 1
  fi
  eval "enable_$feature='$enable'"
}

option_exists() {
  case " $OPTIONS " in
    *" $1 "*) return 0;;
  esac
  return 1
}

set_option() {
  option="$1"
  value="$2"
  if ! option_exists "$option"; then
    printf 'configure.sh: unknown option "%s".\n' "$option" >&2
    exit 1
  fi
  eval "with_$option='$value'"
}

write_build_features() {
  (
    for feature in $FEATURES; do
      eval "enable=\"\$enable_$feature\""
      printf '(enable %s %s)\n' "$feature" "$enable"
    done
  ) >std/build-features.ss
}

while [ $# -gt 0 ]; do
  case "$1" in
    --enable-*)  set_feature_enable "${1#--enable-}"  '#t';;
    --disable-*) set_feature_enable "${1#--disable-}" '#f';;
    --with-*=*)
      arg="${1#--with-}"
      set_option "${arg%=*}" "${arg#*=}"
      ;;
    *)
      printf 'configure.sh: unknown argument "%s".\n' "$1" >&2
      exit 1
      ;;
  esac
  shift
done

write_build_features
