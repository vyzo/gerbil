;; -*- Gerbil -*-
(def build-spec
  `((gxc: "build-config" dep: ("build-features.ss"))
    "interactive"
    "foreign"
    ;; tests for :std/foreign
    "foreign-test"
    "format"
    "pregexp"
    "sort"
    "sugar"
    "make"
    "build-script"
    "error"
    "contract"
    "getopt"
    "logger"
    (gxc: "generic/dispatch" ,@(include-gambit-sharp))
    "generic/macros"
    (gxc: "generic/builtin" ,@(include-gambit-sharp))
    "generic"
    "ref"
    (gxc: "event" ,@(include-gambit-sharp))
    "coroutine"
    "iter"
    "test"
    "stxparam"
    "stxutil"
    "lazy"
    "amb"
    ;; debugging
    (gxc: "debug/heap" ,@(include-gambit-sharp))
    "debug/memleak"
    (gxc: "debug/threads" ,@(include-gambit-sharp))
    ;; SRFI: This is my grandfather's axe; my father replaced the head
    ;;       and i have replaced the handle.
    "srfi/srfi-support"
    "srfi/1"
    "srfi/8"
    "srfi/9"
    "srfi/14"
    (gxc: "srfi/13" "-cc-options" "--param max-gcse-memory=300000000")
    "srfi/19"
    "srfi/41"
    "srfi/41-iter"
    (gxc: "srfi/42" "-cc-options" "--param max-gcse-memory=300000000")
    "srfi/43"
    "srfi/78"
    "srfi/95"
    "srfi/101"
    "srfi/113"
    "srfi/116"
    "srfi/117"
    "srfi/121"
    "srfi/121-iter"
    "srfi/124"
    "srfi/125"
    "srfi/127"
    "srfi/127-iter"
    "srfi/128"
    "srfi/130"
    "srfi/132"
    "srfi/133"
    "srfi/134"
    "srfi/srfi-135/etc"
    "srfi/srfi-135/kernel8"
    "srfi/srfi-135/macros"
    "srfi/srfi-135/text"
    "srfi/srfi-135/binary"
    "srfi/135"
    "srfi/141"
    "srfi/143"
    "srfi/144"
    "srfi/145"
    "srfi/151"
    "srfi/146"
    "srfi/146/vector-edit"
    "srfi/146/hamt-misc"
    "srfi/146/hamt"
    "srfi/146/hamt-map"
    "srfi/146/hash"
    "srfi/115"
    "srfi/158"
    "srfi/158-iter"
    "srfi/159/environment"
    "srfi/159/string"
    "srfi/159/base"
    "srfi/159/show"
    "srfi/159/columnar"
    "srfi/159/unicode"
    "srfi/159/color"
    "srfi/159"
    "srfi/160/cvector"
    "srfi/160/base"
    "srfi/160/macros"
    "srfi/160/u8"
    "srfi/160/s8"
    "srfi/160/u16"
    "srfi/160/s16"
    "srfi/160/u32"
    "srfi/160/s32"
    "srfi/160/u64"
    "srfi/160/s64"
    "srfi/160/f32"
    "srfi/160/f64"
    "srfi/160/c64"
    "srfi/160/c128"
    ;; :std/parser
    "parser/rlang"
    "parser/base"
    (gxc: "parser/stream" ,@(include-gambit-sharp))
    "parser/lexer"
    (gxc: "parser/defparser" "-cc-options" "--param max-gcse-memory=300000000")
    (gxc: "parser/rx-parser" "-cc-options" "--param max-gcse-memory=300000000")
    "parser/deflexer"
    "parser/grammar-reader"
    "parser/grammar"
    "parser"
    ;; :std/text
    "text/utf8"
    "text/utf16"
    "text/utf32"
    "text/hex"
    (gsc: "text/base64")
    (ssi: "text/base64")
    "text/base58"
    "text/csv"
    "text/json"
    ,@(if config-enable-libyaml
        `((gsc: "text/libyaml"
                "-cc-options" ,(cppflags "libyaml" "")
                "-ld-options" ,(ldflags "libyaml" "-lyaml"))
          (ssi: "text/libyaml")
          "text/yaml")
        '())
    ,@(if config-enable-zlib
        `((gsc: "text/_zlib"
                "-cc-options" ,(cppflags "zlib" "")
                "-ld-options" ,(ldflags "zlib" "-lz"))
          (ssi: "text/_zlib")
          "text/zlib")
        '())
    ;; :std/net
    "net/address"
    "net/uri"
    "net/socks"
    "net/request"
    "net/websocket"
    "net/wamp"
    (gxc: "net/repl" ,@(include-gambit-sharp))
    ;; std/os
    (gxc: "os/error" ,@(include-gambit-sharp))
    (gxc: "os/fd" ,@(include-gambit-sharp))
    (gxc: "os/fdio" ,@(include-gambit-sharp))
    (gxc: "os/fcntl" ,@(include-gambit-sharp))
    (gxc: "os/flock" ,@(include-gambit-sharp))
    (gxc: "os/pipe" ,@(include-gambit-sharp))
    ,(cond-expand
       (linux
        `(gsc: "os/_socket" "-cc-options" "-D_GNU_SOURCE" ,@(include-gambit-sharp)))
       (else
        `(gsc: "os/_socket" ,@(include-gambit-sharp))))
    (ssi: "os/_socket")
    "os/socket"
    ,@(cond-expand
        (linux
         `((gxc: "os/epoll" ,@(include-gambit-sharp))
           (gxc: "os/inotify" ,@(include-gambit-sharp))))
        (bsd
         `((gxc: "os/kqueue" ,@(include-gambit-sharp))))
        (else '()))
    "os/signal"
    ,@(cond-expand
        (linux
         `((gxc: "os/signalfd" ,@(include-gambit-sharp))))
        (else '()))
    "os/signal-handler"
    "os/pid"
    ;; :std/net/bio
    "net/bio/input"
    "net/bio/output"
    "net/bio/buffer"
    "net/bio/file"
    "net/bio"
    ;; :std/net/socket
    "net/socket/base"
    "net/socket/basic-socket"
    "net/socket/api"
    "net/socket/buffer"
    "net/socket/basic-server"
    ,@(cond-expand
        (linux
         '("net/socket/epoll-server"))
        (bsd
         '("net/socket/kqueue-server"))
        (else '()))
    "net/socket/server"
    "net/socket"
    ;; :std/net/httpd
    "net/httpd/mux"
    "net/httpd/handler"
    "net/httpd/server"
    "net/httpd/file"
    "net/httpd"
    "net/sasl"
    ;; :std/xml
    ,@(if config-enable-libxml
        `((gsc: "xml/_libxml"
                "-cc-options" ,(shell-config "xml2-config" "--cflags")
                "-ld-options" ,(shell-config "xml2-config" "--libs")
                ,@(include-gambit-sharp))
          (ssi: "xml/_libxml")
          "xml/libxml")
        '())
    (gxc: "xml/ssax" "-cc-options" "--param max-gcse-memory=300000000")
    "xml/sxpath"
    "xml/sxml"
    (gsc: "xml/sxml-to-xml")
    (ssi: "xml/sxml-to-xml")
    "xml/print"
    "xml"
    ;; :std/crypto
    (gsc: "crypto/libcrypto"
          "-cc-options" ,(cppflags "libcrypto" "")
          "-ld-options" ,(ldflags "libcrypto" "-lcrypto")
          ,@(include-gambit-sharp))
    (static-include: "crypto/libcrypto-rfc5114.c")
    (ssi: "crypto/libcrypto")
    (gxc: "crypto/etc" ,@(include-gambit-sharp))
    "crypto/digest"
    "crypto/cipher"
    "crypto/hmac"
    "crypto/bn"
    "crypto/dh"
    "crypto"
    ;; :std/misc
    "misc/timeout"
    "misc/list"
    "misc/rtd"
    "misc/shuffle"
    "misc/uuid"
    "misc/repr"
    "misc/queue"
    "misc/pqueue"
    "misc/deque"
    "misc/rbtree"
    "misc/lru"
    "misc/string"
    "misc/sync"
    "misc/completion"
    "misc/barrier"
    "misc/channel"
    (gxc:  "misc/ports" ,@(include-gambit-sharp))
    (gxc:  "misc/threads" ,@(include-gambit-sharp))
    "misc/process"
    (gxc:  "misc/shared" "-e" "(include \"~~lib/_gambit#.scm\")")
    "misc/text"
    "misc/func"
    "misc/bytes"
    ;; :std/protobuf
    "protobuf/io"
    "protobuf/macros"
    "protobuf/proto-grammar"
    "protobuf/proto"
    ;; :std/actor
    (gxc: "actor/message" ,@(include-gambit-sharp))
    (gxc: "actor/xdr"  ,@(include-gambit-sharp))
    (gxc: "actor/proto" "-cc-options" "--param max-gcse-memory=300000000")
    "actor/rpc/base"
    "actor/rpc/proto/message"
    "actor/rpc/proto/null"
    "actor/rpc/proto/cookie"
    "actor/rpc/proto/cipher"
    "actor/rpc/connection"
    "actor/rpc/server"
    "actor/rpc"
    "actor"
    "web/fastcgi"
    "web/rack"
    "db/dbi"
    "db/conpool"
    "db/postgresql-driver"
    "db/postgresql"
    ,@(if config-enable-sqlite
        `((gsc: "db/_sqlite"
                "-cc-options" ,(cppflags "sqlite3" "")
                "-ld-options" ,(ldflags "sqlite3" "-lsqlite3"))
          (ssi: "db/_sqlite")
          "db/sqlite")
        '())
    ,@(if config-enable-mysql
        `((gsc: "db/_mysql"
                "-cc-options" ,(cppflags "mysqlclient" "")
                "-ld-options" ,(ldflags "mysqlclient" "-lpthread -lmysqlclient"))
          (ssi: "db/_mysql")
          "db/mysql")
        '())
    ,@(if config-enable-lmdb
        `((gsc: "db/_lmdb"
                "-cc-options" ,(cppflags "lmdb" "")
                "-ld-options" ,(ldflags "lmdb" "-llmdb"))
          (ssi: "db/_lmdb")
          "db/lmdb")
        '())
    ,@(if config-enable-leveldb
        `((gsc: "db/_leveldb"
                "-cc-options" ,(cppflags "leveldb" "")
                "-ld-options" ,(ldflags "leveldb" "-lleveldb"))
          (ssi: "db/_leveldb")
          "db/leveldb")
        '())
    ))
