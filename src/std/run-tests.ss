#!/usr/bin/env gxi
;; -*- Gerbil -*-

(import :std/test
	:std/foreign-test
        "build-config"
        "generic-test"
        "coroutine-test"
        "iter-test"
        "sugar-test"
        "amb-test"
        "event-test"
        "misc/string-test"
        "misc/list-test"
        "misc/channel-test"
        "misc/lru-test"
        "misc/func-test"
        "misc/queue-test"
        "misc/deque-test"
        "misc/pqueue-test"
        "misc/rbtree-test"
        "misc/barrier-test"
        "misc/completion-test"
        "misc/bytes-test"
        "misc/text-test"
        "text/csv-test"
        "text/json-test"
        "text/utf8-test"
        "text/utf16-test"
        "actor/xdr-test"
        "actor-test"
        "net/httpd-test"
        "net/sasl-test"
        "protobuf/protobuf-test")

(cond-expand
  (config-have-sqlite
   (import "db/sqlite-test")))

(cond-expand
  (config-have-lmdb
   (import "db/lmdb-test")))

(cond-expand
  (config-have-leveldb
   (import "db/leveldb-test")))

(cond-expand
  ((or linux bsd)
   (import "net/socket/server-test")))

(cond-expand
  (linux
   (import "os/signalfd-test")))

(import "os/signal-handler-test")

(def tests
  [generic-runtime-test
   generic-macro-test
   coroutine-test
   iter-test
   sugar-test
   amb-test
   event-test
   csv-test
   json-test
   utf8-test
   utf16-test
   string-test
   list-test
   channel-test
   lru-test
   func-test
   queue-test
   deque-test
   pqueue-test
   rbtree-test
   barrier-test
   completion-test
   bytes-test
   text-test
   actor-xdr-test
   actor-rpc-test
   actor-rpc-stream-test
   httpd-test
   sasl-test
   protobuf-test
   foreign-test
   (if config-enable-sqlite [sqlite-test] []) ...
   (if config-enable-lmdb [lmdb-test] []) ...
   (if config-enable-leveldb [leveldb-test] []) ...
   socket-server-test
   (cond-expand
     (linux [signalfd-test])
     (else []))
   ...
   signal-handler-test
   ])

(apply run-tests! tests)
(test-report-summary!)

(case (test-result)
  ((OK) (exit 0))
  (else (exit 1)))
