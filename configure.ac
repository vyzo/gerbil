# Configure template for Gerbil system.
# Tangled using Org Mode (C-c C-v t) from configure.org
# $ tangle() {
#    emacs --batch -l org --eval "(org-babel-tangle-file \"$1\")"
# }
# $ tangle configure.org

# Copyright (c) 2019 by drewc <me@drewc.ca>, All Rights Reserved.

# Process this file with autoconf to produce a configure script.

AC_INIT(Gerbil,v0.16.0-1snapshot-DEV-20-cd16549,me@drewc.ca,gerbil-v0.16.0-1snapshot-DEV-20-cd16549)
PACKAGE_SHORTNAME="gerbil"

AC_SUBST(PACKAGE_SHORTNAME)
AC_SUBST(PACKAGE_NAME)
AC_SUBST(PACKAGE_VERSION)
AC_SUBST(PACKAGE_STRING)
AC_SUBST(PACKAGE_BUGREPORT)
AC_SUBST(PACKAGE_TARNAME)

AC_COPYRIGHT([[Copyright (c) 2019 by drewc <me@drewc.ca>, All Rights Reserved.]])


# Libxml
AC_ARG_ENABLE(libxml,
AC_HELP_STRING([--enable-libxml],
[build std/xml libraries - requires libxml2 (default is NO)]),
ENABLE_LIBXML=$enableval,
ENABLE_LIBXML=no)

if test "$ENABLE_LIBXML" = yes; then
sed -i -e 's|enable libxml #f|enable libxml #t|g' src/std/build-features.ss || true
LIBS="$LIBS -lxml2"
else
sed -i -e 's|enable libxml #t|enable libxml #f|g' src/std/build-features.ss || true
fi

# Libyaml
AC_ARG_ENABLE(libyaml,
AC_HELP_STRING([--enable-libyaml],
[build std/text/yaml libraries - requires libyaml (default is NO)]),
ENABLE_LIBYAML=$enableval,
ENABLE_LIBYAML=no)

if test "$ENABLE_LIBYAML" = yes; then
sed -i -e 's|enable libyaml #f|enable libyaml #t|g' src/std/build-features.ss || true
LIBS="$LIBS -lyaml"
else
sed -i -e 's|enable libyaml #t|enable libyaml #f|g' src/std/build-features.ss || true
fi

# Zlib
AC_ARG_ENABLE(zlib,
AC_HELP_STRING([--disable-zlib],
[build std/text/zlib libraries - requires zlib (default is --enable-zlib]),
ENABLE_ZLIB=$enableval,
ENABLE_ZLIB=yes)

if test "$ENABLE_ZLIB" = yes; then
sed -i -e 's|enable zlib #f|enable zlib #t|g' src/std/build-features.ss || true
LIBS="$LIBS -lz"
else
sed -i -e 's|enable zlib #t|enable zlib #f|g' src/std/build-features.ss || true
fi

# Sqlite
AC_ARG_ENABLE(sqlite,
AC_HELP_STRING([--disable-sqlite],
[build std/xml libraries - requires sqlite3 (default is --enable-sqlite)]),
ENABLE_SQLITE=$enableval,
ENABLE_SQLITE=yes)
if test "$ENABLE_SQLITE" = yes; then
sed -i -e 's|enable sqlite #f|enable sqlite #t|g' src/std/build-features.ss || true
else
sed -i -e 's|enable sqlite #t|enable sqlite #f|g' src/std/build-features.ss || true
fi

# Mysql
AC_ARG_ENABLE(mysql,
AC_HELP_STRING([--enable-mysql],
[build std/xml libraries - requires mysql (default is NO)]),
ENABLE_MYSQL=$enableval,
ENABLE_MYSQL=no)

if test "$ENABLE_MYSQL" = yes; then
sed -i -e 's|enable mysql #f|enable mysql #t|g' src/std/build-features.ss || true
else
sed -i -e 's|enable mysql #t|enable mysql #f|g' src/std/build-features.ss || true
fi

# Lmdb
AC_ARG_ENABLE(lmdb,
AC_HELP_STRING([--enable-lmdb],
[build std/xml libraries - requires lmdb2 (default is NO)]),
ENABLE_LMDB=$enableval,
ENABLE_LMDB=no)

if test "$ENABLE_LMDB" = yes; then
sed -i -e 's|enable lmdb #f|enable lmdb #t|g' src/std/build-features.ss || true
LIBS="$LIBS -llmdb" 
else
sed -i -e 's|enable lmdb #t|enable lmdb #f|g' src/std/build-features.ss || true
fi

# Leveldb
AC_ARG_ENABLE(leveldb,
AC_HELP_STRING([--enable-leveldb],
[build std/xml libraries - requires leveldb2 (default is NO)]),
ENABLE_LEVELDB=$enableval,
ENABLE_LEVELDB=no)

if test "$ENABLE_LEVELDB" = yes; then
sed -i -e 's|enable leveldb #f|enable leveldb #t|g' src/std/build-features.ss || true
LIBS="$LIBS -lleveldb"
else
sed -i -e 's|enable leveldb #t|enable leveldb #f|g' src/std/build-features.ss || true
fi


AC_OUTPUT(Makefile)
