#!/bin/sh
GERBIL_SOURCE="${1:-`pwd`}"

# Our ./configure is generated from configure.ac. In that file there's a line,
# AC_INIT(Gerbil,v0,me@drewc.ca,gerbil-v0), that specifies the version.

# Gerbil gets its version from the last tag in the tree. We'll replace that line
# with the version.

replace_version () {
    GERBIL_VERSION=`cd ${GERBIL_SOURCE} && git describe --tags`
    echo "Replacing PACKAGE_VERSION and PACKAGE_TARNAME using ${GERBIL_VERSION}"
    sed -r -i "s/(AC_INIT[(]Gerbil,).*(,me@drewc.ca,gerbil-).*[)]/\1${GERBIL_VERSION}\2${GERBIL_VERSION})/" $1
}

# But, even before that, the configure.ac and Makefile.in are generated from
# configure.org. 

tangle() {
    emacs --batch -l org --eval "(org-babel-tangle-file \"$1\")"
}

# Once all that is done, run autoconf. 

cd $GERBIL_SOURCE && tangle configure.org && replace_version configure.ac && autoconf

echo Generated ./configure
