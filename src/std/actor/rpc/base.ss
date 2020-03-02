;;; -*- Gerbil -*-
;;; (C) vyzo
;;; actor rpc base

(import :gerbil/gambit/threads
        :std/contract
        :std/misc/uuid
        :std/misc/sync
        :std/net/bio
        :std/actor/message
        :std/actor/proto
        :std/actor/xdr)
(export #t)

;;; wire rpc protocols
(defstruct !rpc-protocol (connect accept))

(def (xdr-read-uuid buffer)
  (let (bytes (make-u8vector uuid-length))
    (bio-read-bytes bytes buffer)
    (make-uuid bytes #f)))

(def (xdr-write-uuid obj buffer)
  (bio-write-subu8vector (uuid->u8vector obj) 0 uuid-length buffer))


(defproto-default-type
  (uuid::t xdr-read-uuid xdr-write-uuid)
  (actor-error::t)
  (remote-error::t)
  (rpc-error::t))

;; rpc server protocol
(defproto rpc
  id: std/actor#rpc
  ;; server <-> connection
  event:
  (connection-accept sock sa)
  (connection-shutdown)
  (connection-close)
  ;; client -> server
  call:
  (connect id address proto)
  (register id proto)
  (unregister id)
  (resolve id)
  (server-address)
  event:
  (monitor remote)
  (unmonitor remote)
  (disconnect remote)
  (shutdown))

(def null-uuid
  (u8vector->uuid (make-u8vector uuid-length)))

(def (rpc-monitor thread (msg thread))
  (def (thread-monitor server thread msg)
    (with-catch values (cut thread-join! thread))
    (thread-send server msg))
  (spawn/name 'rpc-monitor thread-monitor (current-thread) thread msg))

(def (make-uuid-table)
  (make-hash-table test: uuid=? hash: uuid-hash))

(def +protocols+
  (make-uuid-table))

(def/c (bind-protocol! id proto)
  (@contract (!protocol? proto))
  (hash-put! +protocols+ (UUID id) proto))

(def (lookup-protocol uuid)
  (hash-get +protocols+ uuid))

(def (make-actor-table)
  (make-sync-hash (make-uuid-table)))
(def (actor-table-put! at uuid actor proto)
  (sync-hash-put! at uuid (values actor proto)))
(defalias actor-table-get
  sync-hash-get)
(defalias actor-table-key?
  sync-hash-key?)
(defalias actor-table-remove!
  sync-hash-remove!)
(defalias actor-table-do
  sync-hash-do)
