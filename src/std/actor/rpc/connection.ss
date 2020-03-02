;;; -*- Gerbil -*-
;;; (C) vyzo
;;; actor rpc connections

(import :gerbil/gambit/threads
        :gerbil/gambit/os
        :gerbil/gambit/exceptions
        :std/sugar
        :std/contract
        :std/logger
        :std/net/bio
        :std/net/socket
        :std/os/socket
        :std/misc/uuid
        :std/misc/threads
        :std/actor/message
        :std/actor/xdr
        :std/actor/proto
        :std/actor/rpc/base
        :std/actor/rpc/proto/message)
(export #t)

(declare (not safe))

(def (rpc-server-connection rpc-server actors sock sa cliaddr proto-e)
  (try
   (rpc-set-nodelay! sock (socket-address-family sa))
   (rpc-connection-loop rpc-server actors sock cliaddr proto-e)
   (catch (e)
     (rpc-connection-cleanup rpc-server e sock))))

(def (rpc-client-connection rpc-server actors address proto-e)
  (try
   (let* ((sa (socket-address address))
          (cli (ssocket-connect sa)))
     (rpc-set-nodelay! cli (socket-address-family sa))
     (rpc-connection-loop rpc-server actors cli address proto-e))
   (catch (e)
     (rpc-connection-cleanup rpc-server e #f))))

(def (rpc-set-nodelay! sock safamily)
  (when (or (eq? safamily AF_INET)
            (eq? safamily AF_INET6))
    (socket-setsockopt (ssocket-socket sock) IPPROTO_TCP TCP_NODELAY 1)))

(def rpc-keep-alive 60) ; keep-alive interval

(def/c (set-rpc-keep-alive-interval! dt)
  (@contract (or (not dt) (and (real? dt) (positive? dt))))
  (set! rpc-keep-alive dt))

;; TODO idle-timeout is ignored
(def rpc-idle-timeout #f)

(def/c (set-rpc-idle-timeout! dt)
  (@contract (or (not dt) (and (real? dt) (positive? dt))))
  (set! rpc-idle-timeout dt))

(def rpc-call-timeout 60)

(def/c (set-rpc-call-timeout! dt)
  (@contract (or (and (real? dt) (positive? dt) (finite? dt)) (not dt)))
  (set! rpc-call-timeout dt))

;; connection state: message continuations
(defstruct continuation-table
  (mx                      ; mutex
   continuations           ; wire-id => (values actor proto k stream?)
   stream-continuations    ; k => wire-id
   stream-actors           ; wire-id => [actor . dest]
   timeouts                ; timeout => wire-id
   continuation-timeouts)  ; wire-id => timeout
  final: #t unchecked: #t
  constructor: :init!)

(defmethod {:init! continuation-table}
  (lambda (self)
    (struct-instance-init! self
      (make-mutex 'continuation-table)
      (make-hash-table-eqv)                     ; continuations
      (make-hash-table-eq)                      ; stream-continuations
      (make-hash-table-eqv)                     ; stream-actors
      (make-hash-table-eq)                      ; timeouts
      (make-hash-table-eqv))))                  ; continuation-timeouts

(defrules with-continuation-table ()
  ((_ cont-table body ...)
   (let (mx (&continuation-table-mx cont-table))
     (mutex-lock! mx)
     (let (res (begin body ...))
       (mutex-unlock! mx)
       res))))

(defrules continuation-table-do ()
  ((_ cont-table body ...)
   (let (mx (&continuation-table-mx cont-table))
     (mutex-lock! mx)
     body ...
     (mutex-unlock! mx))))

(def (continuation-table-get cont-table cont)
  (with-continuation-table cont-table
    (let (ct (&continuation-table-continuations cont-table))
      (hash-get ct cont))))

(def (continuation-table-remove! cont-table cont)
  (with-continuation-table cont-table
    (let (ct (&continuation-table-continuations cont-table))
      (alet (continuation (hash-get ct cont))
        (hash-remove! ct cont)
        (with ((values _ _ k stream?) continuation)
          (when stream?
            (hash-remove! (&continuation-table-stream-continuations cont-table) k)))
        (let (tt (&continuation-table-continuation-timeouts cont-table))
          (alet (timeo (hash-get tt cont))
            (hash-remove! tt cont)
            (hash-remove! (&continuation-table-timeouts cont-table) timeo)))
        continuation))))

(def (continuation-table-get-stream-actor cont-table cont)
  (with-continuation-table cont-table
    (let (st (&continuation-table-stream-actors cont-table))
      (hash-get st cont))))

(def (continuation-table-put-stream-actor! cont-table cont val)
  (with-continuation-table cont-table
    (let (st (&continuation-table-stream-actors cont-table))
      (hash-put! st cont val))))

(def (continuation-table-remove-stream-actor! cont-table cont)
  (with-continuation-table cont-table
    (let (st (&continuation-table-stream-actors cont-table))
      (hash-remove! st cont))))

(def (continuation-table-get-stream-cont cont-table k)
  (with-continuation-table cont-table
    (let (sct (&continuation-table-stream-continuations cont-table))
      (hash-get sct k))))

(def (continuation-table-get-timeout cont-table timeo)
  (with-continuation-table cont-table
    (let (tt (&continuation-table-timeouts cont-table))
      (hash-get tt timeo))))

;; DEBUG
(def (continuation-table-dump! cont-table (port (current-error-port)))
  (parameterize ((current-output-port port))
    (continuation-table-do cont-table
      (with ((continuation-table _ conts sconts sactors tmos ctmos) cont-table)
        (displayln "continuations: " (hash-length conts))
        (hash-for-each
         (lambda (wire-id continuation)
           (with ((values actor proto k stream?) continuation)
             (displayln wire-id " -> " [actor proto k stream?])))
         conts)
        (displayln "stream-continuations: " (hash-length sconts))
        (hash-for-each
         (lambda (k wire-id)
           (displayln k " -> " wire-id))
         sconts)
        (displayln "stream-actors: " (hash-length sactors))
        (hash-for-each
         (lambda (wire-id sactor)
           (displayln wire-id " -> " sactor))
         sactors)
        (displayln "timeouts: " (hash-length tmos))
        (hash-for-each
         (lambda (tmo wire-id)
           (displayln (time->seconds tmo) " -> " wire-id))
         tmos)))))

;; the main thread of the connection; it's the proxy actor in remote handles
(def (rpc-connection-loop rpc-server actors sock peer-address proto-e)
  (def input-buffer
    (open-ssocket-input-buffer sock))
  (def output-buffer
    (open-ssocket-output-buffer sock))
  (defvalues (read-e write-e)
    (proto-e input-buffer output-buffer))
  (def cont-table
    (make-continuation-table))

  (def next-timeout #f)
  (def next-continuation-id 0)

  (def next-heartbeat
    (seconds->time (+ (##current-time-point) 60)))

  (def writer
    (spawn/name 'rpc-connection-writer rpc-connection-writer
                output-buffer write-e))
  (def reader
    (spawn/name 'rpc-connection-reader rpc-connection-reader
                (current-thread) peer-address input-buffer actors cont-table writer read-e))

  (def (close-connection)
    (ssocket-close sock)
    (thread-send writer 'exit)
    (continuation-table-do cont-table
      (hash-for-each
       (lambda (wire-id cont)
         (with ((values actor proto k stream?) cont)
           (!!error actor (make-rpc-error 'rpc "connection error") k)))
       (&continuation-table-continuations cont-table))
      (hash-for-each
       (lambda (wire-id stream)
         (with ([actor . dest] stream)
           (let (abort (make-message (make-!abort wire-id) dest actor #f))
             (send actor abort))))
       (&continuation-table-stream-actors cont-table)))
    (rpc-connection-shutdown rpc-server)
    (raise 'shutdown))

  (def (write-message msg)
    (with ((message content src dest opts) msg)
      (if (remote? dest)
        (with ((remote _ uuid address proto) dest)
          (set! (message-dest msg)
            uuid)
          ;; keep track of continuation and timeout
          (match content
            ((!call _ k)
             (let (wire-id (next-continuation-id!))
               (continuation-table-do cont-table
                 (hash-put! (&continuation-table-continuations cont-table)
                            wire-id (values src proto k #f))
                 (alet (timeo (rpc-options-timeout opts rpc-call-timeout))
                   (hash-put! (&continuation-table-timeouts cont-table)
                              timeo wire-id)
                   (hash-put! (&continuation-table-continuation-timeouts cont-table)
                              wire-id timeo)
                   (set-timeout! timeo)))
               (set! (!call-k content) wire-id)
               (marshal-and-write msg proto #t)))
            ((!stream _ k)
             (let (wire-id (next-continuation-id!))
               (continuation-table-do cont-table
                 (hash-put! (&continuation-table-continuations cont-table)
                            wire-id (values src proto k #t))
                 (hash-put! (&continuation-table-stream-continuations cont-table)
                            k wire-id)
                 (alet (timeo (rpc-options-timeout opts #f))
                   (hash-put! (&continuation-table-timeouts cont-table)
                              timeo wire-id)
                   (hash-put! (&continuation-table-continuation-timeouts cont-table)
                              wire-id timeo)
                   (set-timeout! timeo)))
               (set! (!stream-k content) wire-id)
               (marshal-and-write msg proto #t)))
            ((? (or !value? !yield? !error? !end?))
             (marshal-and-write msg proto #t))
            ((!sync wire-id)
             (continuation-table-put-stream-actor! cont-table wire-id (cons src dest))
             (marshal-and-write msg proto #t))
            ((!continue k)
             (let (wire-id (continuation-table-get-stream-cont cont-table k))
               (if wire-id
                 (begin
                   (set! (!continue-k content) wire-id)
                   (marshal-and-write msg proto #t))
                 (warning "bad continue; unknown stream ~a" k))))
            ((!close k)
             (let (wire-id (continuation-table-get-stream-cont cont-table k))
               (if wire-id
                 (begin
                   (set! (!close-k content) wire-id)
                   (marshal-and-write msg proto #t))
                 (warning "bad close; unknown stream ~a" k))))
            ((!abort k)
             (let (wire-id (continuation-table-get-stream-cont cont-table k))
               (if wire-id
                 (begin
                   (set! (!abort-k content) wire-id)
                   (continuation-table-remove! cont-table wire-id)
                   (marshal-and-write msg proto #t))
                 (warning "bad abort; unknown stream ~a" k))))
            (else
             (marshal-and-write msg proto #t))))
        (warning "bad handle; no protocol ~a ~a" dest msg))))

  (def (next-continuation-id!)
    (let (next next-continuation-id)
      (set! next-continuation-id (1+ next))
      next))

  (def (marshal-and-write msg proto dispatch-marshal-error?)
    (defrules dispatch-marshal-error ()
      ((_ what)
       (let ((content (message-e msg))
             (dest    (message-dest msg)))
         (match content
           ((or (!call e wire-id) (!stream e wire-id))
            (dispatch-error wire-id what))
           ((or (!error e wire-id) (!yield e wire-id))
            (when dispatch-marshal-error?
              (dispatch-remote-error (make-!error what wire-id) dest)))
           (else (void))))))

    (let (e (try (rpc-proto-marshal-message msg proto)
                 (catch (exception? e) e)))
      (cond
       ((u8vector? e)
        (if (fx<= (u8vector-length e) rpc-proto-message-max-length)
          (thread-send writer e)
          (begin
            (warning "message too large; not sending %d bytes" (u8vector-length e))
            (dispatch-marshal-error "message too large"))))
       ((chunked-output-buffer? e)
        (if (fx<= (chunked-output-length e) rpc-proto-message-max-length)
          (thread-send writer e)
          (begin
            (warning "message too large; not sending %d bytes" (chunked-output-length e))
            (dispatch-marshal-error "message too large"))))
       (dispatch-marshal-error?
        (log-error "marshal error" e)
        (dispatch-marshal-error "marshal error"))
       (else
        (log-error "marshal error" e)))))

  (def (dispatch-error wire-id what)
    (match (continuation-table-remove! cont-table wire-id)
      ((values actor proto k stream?)
       (!!error actor (make-rpc-error 'rpc what) k))
      (else (void))))

  (def (dispatch-remote-error what dest)
    (marshal-and-write (make-message what (void) dest #f) #f #f))

  (def (dispatch-timeout timeo)
    (set! next-timeout #f)
    (cond
     ((continuation-table-get-timeout cont-table timeo)
      => (lambda (wire-id)
           (dispatch-error wire-id "timeout")))))

  (def (timeout< a b)
    (< (time->seconds a)
       (time->seconds b)))

  (def (set-timeout! timeo)
    (when (or (not next-timeout) (timeout< timeo next-timeout))
      (set! next-timeout timeo)))

  (def (timeout-event)
    (unless next-timeout
      (continuation-table-do cont-table
        (let (timeouts (&continuation-table-timeouts cont-table))
          (unless (fxzero? (hash-length timeouts))
            (hash-for-each
             (lambda (timeo _)
               (set-timeout! timeo))
             timeouts)))))
    next-timeout)

  (def (heartbeat!)
    (let (dead-continuations
          (with-continuation-table cont-table
            (hash-fold
             (lambda (wire-id continuation r)
               (with ((values actor _ _ _) continuation)
                 (if (and (thread? actor) (thread-dead? actor))
                   (cons wire-id r)
                   r)))
             [] (&continuation-table-continuations cont-table))))
      (for-each
        (lambda (wire-id)
          (match (continuation-table-remove! cont-table wire-id)
            ((values actor proto k stream?)
             (debug "removing continuation ~a for dead actor ~a" wire-id actor)
             (when stream?
               (dispatch-remote-error (make-!abort wire-id) null-uuid)))
            (else (void))))
        dead-continuations))
    (set! next-heartbeat
      (seconds->time (+ (##current-time-point) 60))))

  (def (dump! port)
    (parameterize ((current-output-port port))
      (displayln "=== rpc-connection ===")
      (displayln "peer-address: " peer-address)
      (displayln "next-continuation-id: " next-continuation-id)
      (displayln "next-timeout: " (and next-timeout (time->seconds next-timeout))))
    (continuation-table-dump! cont-table port))

  (def (loop)
    (<< (! (timeout-event)
           => dispatch-timeout)
        (! next-heartbeat
           (heartbeat!))
        ((? message? msg)
         (write-message msg))
        ((? eof-object?)
         (close-connection))
        ('shutdown
         (close-connection))
        ((? thread? thread)
         (try
          (thread-join! thread)
          (warning "connection error: i/o thread ~a exited unexpectedly" (thread-name thread))
          (catch (uncaught-exception? e)
            (log-error "connection error" (uncaught-exception-reason e)))
          (catch (e)
            (log-error "connection error" e)))
         (close-connection))
        ;; DEBUG
        ('dump
         (dump! (current-error-port)))
        (['dump port]
         (dump! port))
        (bogus
         (warning "unexpected message ~a" bogus)))
    (loop))

  (def (run)
    ;; create a denv cell for current-xdr-type-registry
    (parameterize ((current-xdr-type-registry +xdr-default-type-registry+))
      (loop)))

  (rpc-monitor reader)
  (rpc-monitor writer)
  (try
   (run)
   (catch (e)
     (unless (eq? 'shutdown e)
       (log-error "unhandled exception" e)
       (with-catch void close-connection)))))

;; the writer of the connection: receives marshaled outbound messages
;; and writes them to the socket
(def (rpc-connection-writer sockbuf write-e)
  (def (loop)
    (<< (! rpc-keep-alive
           (write-e sockbuf (void))
           (loop))
        ((? output-buffer? buf)
         (write-e sockbuf buf)
         (loop))
        ((? u8vector? data)
         (write-e sockbuf data)
         (loop))
        ('exit (void))
        (bogus
         (warning "unexpected message ~a" bogus)
         (loop))))
  (try
   (loop)
   (catch (e)
     (log-error "unhandled exception" e))))

;; the reader of the connection: reads, unmarshals, and dispatches inbound messages
(def (rpc-connection-reader conn connaddr sockbuf actor-table cont-table writer read-e)
  (def (loop u8buf)
    (match (read-e sockbuf u8buf)
      ((values u8buf count)
       (let* ((buffer (open-input-buffer u8buf 0 count))
              (msg (read-envelope buffer)))
         (match msg
           ((message content)
            (match content
             ((? (or !call? !event? !stream?))
              (dispatch-call msg buffer))
             ((? (or !value? !error? !yield? !end? !sync?))
              (dispatch-value msg buffer))
             ((? (or !continue? !close? !abort?))
              (dispatch-control msg buffer))
             (else
              (dispatch-call msg buffer))))
           (else (void)))
         (loop u8buf)))

      ((? void?)
       (loop u8buf))

      ((? eof-object?)
       (thread-send conn #!eof))

      (unexpected
       (error "read unexpected object" unexpected))))

  (def (dispatch-call msg buffer)
    (let (uuid (message-dest msg))
      (cond
       ((actor-table-get actor-table uuid)
        => (match <>
             ((values actor proto)
              (cond
               ((read-payload! msg buffer proto)
                (set! (message-dest msg)
                  actor)
                (set! (message-source msg)
                  (make-remote conn uuid connaddr proto))
                ;; it is possible that the actor unregistered while unmarshalling
                ;; but i can live with that race -- it is equivalent to receiving
                ;; a message while unregistering.
                ;; also note that eliminating that race would require a lock
                ;; on the actor-table, which we want to avoid as it's server
                ;; scoped (shared by all connections in the ensemble)
                (send actor msg))
               ((or (!call? (message-e msg)) (!stream? (message-e msg)))
                (let* ((content (message-e msg))
                       (k (if (!call? content)
                          (!call-k content)
                          (!stream-k content))))
                  (dispatch-remote-error (make-!error "unmarshal error" k) uuid)))))))
        (else
         (warning "cannot route message; no actor binding ~a" (uuid->string uuid))
         (match (message-e msg)
           ((or (!call _ k) (!stream _ k))
            (dispatch-remote-error (make-!error "no binding" k) uuid))
           (else (void)))))))

  (def (dispatch-value msg buffer)
    (let* ((content (message-e msg))
           (cont    (value-k content)))
      (cond
       ((continuation-table-get cont-table cont)
        => (match <>
             ((values actor proto k stream?)
              (cond
               ((read-payload! msg buffer proto)
                (value-k-set! content k)
                (set! (message-source msg)
                  (make-remote conn (message-dest msg) connaddr proto))
                (cond
                 ((or (!yield? content) (!sync? content))
                  ;; race with timeout, so we need to lock and check the cont table again
                  (let (ok
                        (with-continuation-table cont-table
                          (if (hash-get (&continuation-table-continuations cont-table) cont)
                            (begin (send actor msg) #t)
                            #f)))
                    (unless ok
                      ;; that needs to marshal and can take time, so we need to  do it
                      ;; without the lock; hence the little dance.
                      (when (!sync? content)
                        (dispatch-remote-error (make-!abort cont) (message-dest msg))))))
                 ((continuation-table-remove! cont-table cont)
                  ;; there is no race here, because continuation-table-remove! is
                  ;; atomic and returns #f if no continuation was removed
                  (send actor msg))))
               (else
                (when (continuation-table-remove! cont-table cont)
                  (!!error actor (make-rpc-error 'rpc "unmarshal error") k))
                (when (!sync? content)
                  (dispatch-remote-error (make-!abort cont) (message-dest msg))))))))
       (else
        (warning "cannot route message; unknown continuation ~a" cont)
        (when (!sync? content)
          (dispatch-remote-error (make-!abort cont) (message-dest msg)))))))

  (def (dispatch-control msg buffer)
    (let* ((content (message-e msg))
           (cont    (value-k content))
           (stream  (continuation-table-get-stream-actor cont-table cont)))
      (if stream
        (with ([actor . dest] stream)
          (set! (message-source msg) dest)
          (send actor msg)
          (continuation-table-remove-stream-actor! cont-table cont))
        (begin
          (warning "unexpected control message; unknown stream ~a" cont)
          (unless (!abort? content)
            (dispatch-remote-error (make-!error "uknown stream" cont) (message-dest msg)))))))

  (def (value-k obj)
    (##vector-ref obj (fx1- (##vector-length obj))))

  (def (value-k-set! obj k)
    (##vector-set! obj (fx1- (##vector-length obj)) k))

  (def (dispatch-remote-error err dest)
    (let* ((msg (make-message err (void) dest #f))
           (data (rpc-proto-marshal-message msg #f)))
      (thread-send writer data)))

  (def (read-envelope buffer)
    (try
     (rpc-proto-read-envelope buffer)
     (catch (exception? e)
       (log-error "read error" e)
       e)))

  (def (read-payload! msg buffer proto)
    (try
     (rpc-proto-read-payload! msg buffer proto)
     (catch (e)
       (log-error "unmarshal error" e)
       #f)))

  (def (run)
    ;; create denv cell for current-xdr-type-registry
    (parameterize ((current-xdr-type-registry +xdr-default-type-registry+))
      (loop (make-u8vector 4096))))

  (try
   (run)
   (catch (e)
     (log-error "unhandled exception" e))))

;;; utilities
(def (rpc-options-timeout opts default)
  (def (timeout dt default)
    (cond
     ((real? dt)                        ; rel time
      (seconds->time
       (+ (##current-time-point) dt)))
     ((time? dt) dt)                    ; abs time
     ((not dt) dt)                      ; bottom
     (else
      (timeout default #f))))
  (cond
   ((and opts (memq timeout: opts))
    => (lambda (plist)
         (timeout (cadr plist) default)))
   (else
    (timeout default #f))))

(def (rpc-connection-shutdown rpc-server)
  (!!rpc.connection-shutdown rpc-server)
  (let lp ()
    (<< ((? message? msg)
         (with ((message content) msg)
           (match content
             ((!rpc.connection-close)
              (rpc-send-error-responses "connection error"))
             (else
              (rpc-send-error-response msg "connection error")
              (lp)))))
        (ignore (lp)))))

(def (rpc-connection-cleanup rpc-server exn sock)
  (log-error "connection error" exn)
  (when sock
    (ssocket-close sock))
  (rpc-connection-shutdown rpc-server))

(def (rpc-send-error-response msg what)
  (when (message? msg)
    (with ((message content src dest) msg)
      (match content
        ((or (!call _ k) (!stream _ k))
         (!!error (message-source msg) (make-rpc-error 'rpc what) k))
        ((!yield k)
         (let (abort (make-message (make-!abort k) dest src #f))
           (send src abort)))
        (else (void))))))

(def (rpc-send-error-responses what)
  (let lp ()
    (<< ((? message? msg)
         (rpc-send-error-response msg what)
         (lp))
        (ignore (lp))
        (else (void)))))
