;;; -*- Gerbil -*-
;;; (C) vyzo
;;; WAMP client

(import :gerbil/gambit/threads
        :gerbil/gambit/ports
        :gerbil/gambit/bits
        :gerbil/gambit/misc
        :std/error
        :std/contract
        :std/sugar
        :std/logger
        :std/misc/completion
        :std/misc/threads
        :std/net/websocket
        :std/actor/message
        :std/actor/proto
        :std/crypto/etc
        :std/text/json)
(export
  ;; TODO: this exports more than it needs to; restrict interface further.
  (except-out #t
              wamp-client wamp-reader
              session-details
              wamp-open-session
              wamp-send
              wamp-recv
              HELLO WELCOME ABORT GOODBYE
              ERROR
              PUBLISH PUBLISHED
              SUBSCRIBE SUBSCRIBED
              UNSUBSCRIBE UNSUBSCRIBED
              EVENT
              CALL RESULT
              REGISTER REGISTERED UNREGISTER UNREGISTERED
              INVOCATION YIELD))

(defstruct (wamp-error <error>) ()
  constructor: :init!
  final: #t)

(defstruct invocation-error (err details tail)
  constructor: :init!
  final: #t)

(defmethod {:init! wamp-error}
  (lambda (self where err . irritants)
    (struct-instance-init! self err irritants where)))

(defmethod {:init! invocation-error}
  (lambda (self err details args kws)
    (let (tail
          (cond
           (kws [args kws])
           ((not (null? args)) [args])
           (else [])))
      (struct-instance-init! self err details tail))))

(def (raise-invocation-error err details (args []) (kws #f))
  (raise (make-invocation-error err details args kws)))

(def (start-wamp-client! url realm
                         redirect: (redirect #t)
                         headers: (headers #f)
                         cookies: (cookies #f)
                         params: (params #f))
  (start-logger!)
  (let* ((compl (make-completion))
         (client (spawn/group 'wamp-client wamp-client-main
                              compl url realm
                              redirect: redirect
                              headers: headers
                              cookies: cookies
                              params: params))
         (details
          (try
           (completion-wait! compl)
           (catch (e)
             (thread-group-kill! (thread-thread-group client))
             (raise e)))))
    (values client details)))

(def (wamp-client-main compl url realm
                       redirect: redirect
                       headers: headers
                       cookies: cookies
                       params: params)
  (def (open-session)
    (let* ((headers
            (cons '("Sec-WebSocket-Protocol" . "wamp.2.json")
                  (or headers [])))
           (ws (open-websocket-client url
                                      redirect: redirect
                                      headers: headers
                                      cookies: cookies
                                      params: params))
           ((values sid details)
            (try
             (wamp-open-session ws realm)
             (catch (e)
               (websocket-close ws)
               (raise e)))))
      (values ws sid details)))

  (let ((values ws sid details)
        (with-completion-error compl
          (open-session)))
    (completion-post! compl details)
    (wamp-client ws realm sid)))

;; synchronous client interface
;; => (values details args kws)
(def/c (wamp-call cli name opts args kws)
  (@contract (string? name))
  (!!wamp.call cli name opts args kws))

(def/c (wamp-publish cli topic opts args kws)
  (@contract (string? topic))
  (!!wamp.publish cli topic opts args kws))

;; => object-port of (values details args kws)
(def/c (wamp-subscribe cli topic)
  (@contract (string? topic))

  (def (event-handler outp)
    (try
     (!!wamp.subscribe cli topic #f)
     (let lp ()
       (<- ((!wamp.event _ details args kws)
            (write (values details args kws) outp)
            (lp))
           ((!wamp.close-stream)
            (!!wamp.unsubscribe cli topic)
            (close-port outp))
           ((!wamp.shutdown)
            (close-port outp))))
     (catch (e)
       (!!wamp.unsubscribe cli topic)
       (write e outp)
       (close-port outp))))

  (let* (((values inp outp)
          (open-vector-pipe [permanent-close: #t direction: 'input]
                            [permanent-close: #t direction: 'output]))
         (handler (spawn/name 'wamp-receive event-handler outp))
         (close (lambda () (!!wamp.close-stream handler))))
    (make-will inp (lambda (_) (close)))
    (values inp close)))

(def/c (wamp-register cli proc name opts)
  (@contract (procedure? proc)
             (string? name))
  (!!wamp.register cli proc name opts))

(def (wamp-unregister cli name)
  (!!wamp.unregister cli name))

;; close a wamp client
(def (wamp-close cli)
  (let (tgroup (thread-thread-group cli))
    (try
     (!!wamp.shutdown cli)
     (thread-join! cli)
     (finally
      (thread-group-kill! tgroup)))))

;; wamp client actor protocol
(defproto wamp
  ;; rpc
  call:
  (register proc name opts)
  (unregister name)
  (call name opts args kws)             ; => (values details args kws)
  ;; pubsub
  (subscribe topic opts)
  event:
  (unsubscribe topic)
  (publish topic opts args kws)
  (event topic details args kws)
  ;; notifications
  (shutdown)
  ;; internal
  (receive msg)
  (close-connection e)
  (remove-thread e)
  (close-stream))

(def (wamp-client ws realm sid)
  (def pend-calls                       ; request-id -> [thread . k]
    (make-hash-table-eqv))
  (def pend-subscriptions               ; request-id -> topic
    (make-hash-table-eqv))
  (def pend-topic-subscriptions         ; topic -> [[thread . k] ...]
    (make-hash-table))
  (def subscriptions                    ; subscription-id -> topic
    (make-hash-table-eqv))
  (def topic-subscription-ids           ; topic -> subscription-id
    (make-hash-table))
  (def topic-subscriptions              ; topic -> [thread ...]
    (make-hash-table))
  (def actor-subscriptions              ; thread -> [topic ...]
    (make-hash-table-eq))
  (def pend-registrations               ; request-id -> [[thread . k] . [proc-uri . proc]]
    (make-hash-table-eqv))
  (def registrations                    ; registration-id -> [proc-uri . proc]
    (make-hash-table-eqv))
  (def procedure-registrations          ; proc-uri -> registration-id
    (make-hash-table))
  (def pend-unregistrations             ; request-id -> [[thread . k] registration-id]
    (make-hash-table-eqv))

  (def reader
    (spawn/name 'wamp-reader wamp-reader (current-thread) ws))

  (def (monitor-thread thread)
    (def (monitor cli thread)
      (with-catch void (cut thread-join! thread))
      (!!wamp.remove-thread cli thread))
    (spawn/name 'wamp-monitor monitor (current-thread) thread))

  (def (remove-thread! thread)
    (alet (topics (hash-get actor-subscriptions thread))
      (for-each (cut remove-subscription! <> thread)
                topics)
      (hash-remove! actor-subscriptions thread)))

  (def (remove-subscription! topic thread)
    (let* ((subs (hash-ref topic-subscriptions topic))
           (subs (remq thread subs)))
      (if (null? subs)
        (let (subid (hash-ref topic-subscription-ids topic))
          (hash-remove! subscriptions subid)
          (hash-remove! topic-subscriptions topic)
          (hash-remove! topic-subscription-ids topic)
          (let (reqid (request-id))
            (wamp-send ws [UNSUBSCRIBE reqid subid])))
        (hash-put! topic-subscriptions topic subs))))

  (def (remove-actor-subscription! topic thread)
    (alet (topics (hash-get actor-subscriptions thread))
      (let (topics (remove topic topics))
        (if (null? topics)
          (hash-remove! actor-subscriptions thread)
          (hash-put! actor-subscriptions thread topics)))
      (remove-subscription! topic thread)))

  (def (add-actor-subscription! topic thread)
    (cond
     ((hash-get actor-subscriptions thread)
      => (lambda (topics)
           (hash-put! actor-subscriptions thread (cons topic topics))))
     (else
      (monitor-thread thread)
      (hash-put! actor-subscriptions thread [topic]))))

  (def (invoke proc reqid details rest)
    (let (vals
          (match rest
                 ([] (values details [] #f))
                 ([args] (values details args #f))
                 ([args kws] (values details args kws))))
      (try
       (with ((values opts args kws) (call/values (lambda () vals) proc))
         (wamp-send ws [YIELD reqid (or opts empty-hash) (message-tail args kws) ...]))
       (catch (invocation-error? e)
         (wamp-send ws [ERROR INVOCATION reqid
                              (invocation-error-details e)
                              (invocation-error-err e)
                              (invocation-error-tail e) ...]))
       (catch (e)
         (log-error "invocation error" e)
         (wamp-send ws [ERROR INVOCATION reqid
                              (hash (message "Internal Server Error"))
                              "internal_server_error"])))))

  (def (receive msg)
    (match msg
      ([(eq? EVENT) subid pubid details . rest]
       (alet (topic (hash-get subscriptions subid))
         (let ((actors (hash-ref topic-subscriptions topic))
               (evt
                (match rest
                  ([] (make-wamp.event topic details [] #f))
                  ([args] (make-wamp.event topic details args #f))
                  ([args kws] (make-wamp.event topic details args kws)))))
           (for-each
             (lambda (thread)
               (send-message thread (make-!event evt)))
             actors))))

      ([(eq? RESULT) reqid details . rest]
       (with ([src . k] (hash-ref pend-calls reqid))
         (hash-remove! pend-calls reqid)
         (let (val
               (match rest
                 ([] (values details [] #f))
                 ([args] (values details args #f))
                 ([args kws] (values details args kws))))
           (!!value src val k))))

      ([(eq? INVOCATION) reqid regid details . rest]
       (with ([name . proc] (hash-ref registrations regid))
         (spawn/name 'wamp-invocation invoke proc reqid details rest)))

      ([(eq? SUBSCRIBED) reqid subid]
       (let* ((topic (hash-ref pend-subscriptions reqid))
              (pend  (hash-ref pend-topic-subscriptions topic)))
         (hash-put! subscriptions subid topic)
         (hash-put! topic-subscriptions topic (map car pend))
         (hash-put! topic-subscription-ids topic subid)
         (for-each (match <>
                     ([src . k]
                      (add-actor-subscription! topic src)
                      (!!value src (void) k)))
                   pend)))

      ([(eq? UNSUBSCRIBED) . _]
       (void))

      ([(eq? REGISTERED) reqid regid]
       (with* (([pend . reg] (hash-ref pend-registrations reqid))
               ([src . k] pend)
               ([name . proc] reg))
         (hash-remove! pend-registrations reqid)
         (hash-put! registrations regid reg)
         (hash-put! procedure-registrations name regid)
         (!!value src (void) k)))

      ([(eq? UNREGISTERED) reqid]
       (with* (([pend . regid] (hash-ref pend-unregistrations reqid))
               ([src . k] pend)
               ([name . proc] (hash-ref registrations regid)))
         (hash-remove! pend-unregistrations reqid)
         (hash-remove! registrations regid)
         (hash-remove! procedure-registrations name)
         (!!value src (void) k)))

      ([(eq? ERROR) what reqid details err . rest]
       (cond
        ((eq? what CALL)
         (let (pend (hash-ref pend-calls reqid))
           (hash-remove! pend-calls reqid)
           (let (err (apply make-wamp-error 'CALL err details rest))
             (send-pend-error pend err))))

        ((eq? what SUBSCRIBE)
         (let* ((topic (hash-ref pend-subscriptions reqid))
                (pend (hash-ref pend-topic-subscriptions topic)))
           (hash-remove! pend-subscriptions reqid)
           (hash-remove! pend-topic-subscriptions topic)
           (let (err (apply make-wamp-error 'SUBSCRIBE err details rest))
             (for-each (cut send-pend-error <> err) pend))))

        ((eq? what REGISTER)
         (with ([pend . reg] (hash-ref pend-registrations reqid))
           (hash-remove! pend-registrations reqid)
           (let (err (apply make-wamp-error 'REGISTER err details rest))
             (send-pend-error pend err))))

        ((eq? what UNREGISTER)
         (with ([pend . regid] (hash-ref pend-unregistrations reqid))
           (hash-remove! pend-unregistrations reqid)
           (let (err (apply make-wamp-error 'UNREGISTER err details rest))
             (send-pend-error pend err))))

        (else
         (warning "unexpected ERROR: ~a ~a" what err))))

      ([(eq? GOODBYE) details reason]
       (wamp-send ws [GOODBYE empty-hash "wamp.error.goodbye_and_out"])
       (raise 'shutdown))

      (else
       (warning "unexpected message: ~a" msg))))

  (def rbytes (make-u8vector 7))
  (def rmax (expt 2 53))

  (def (request-id)
    (random-bytes! rbytes)
    (let lp ((k 0) (r 0))
      (if (##fx< k 7)
        (lp (##fx+ k 1)
            (bitwise-ior (arithmetic-shift r 8) (##u8vector-ref rbytes k)))
        (modulo r rmax))))

  (def (message-tail args kws)
    (if (null? args)
      (if (and kws (not (##fxzero? (hash-length kws))))
        [[] kws]
        [])
      (if (and kws (not (##fxzero? (hash-length kws))))
        [args kws]
        [args])))

  (def (loop)
    (<- ((!wamp.receive msg)
         (receive msg))

        ;; rpc calls
        ((!wamp.call name opts args kws k)
         (let (reqid (request-id))
           (hash-put! pend-calls reqid (cons @source k))
           (wamp-send ws [CALL reqid (or opts empty-hash) name (message-tail args kws) ...])))

        ((!wamp.register proc name opts k)
         (cond
          ((hash-get procedure-registrations name)
           (!!error "procedure already registered" k))
          (else
           (let (reqid (request-id))
             (hash-put! pend-registrations reqid (cons (cons @source k) (cons name proc)))
             (wamp-send ws [REGISTER reqid (or opts empty-hash) name])))))

        ((!wamp.unregister name k)
         (cond
          ((hash-get procedure-registrations name)
           => (lambda (regid)
                (let (reqid (request-id))
                  (hash-put! pend-unregistrations reqid (cons (cons @source k) regid))
                  (wamp-send ws [UNREGISTER reqid regid]))))
          (else
           (!!error "procedure is not registered" k))))


        ;; pubsub
        ((!wamp.subscribe topic opts k)
         (cond
          ((hash-get topic-subscriptions topic)
           => (lambda (actors)
                (hash-put! topic-subscriptions topic (cons @source actors))
                (add-actor-subscription! topic @source)
                (!!value (void) k)))
          ((hash-get pend-topic-subscriptions topic)
           => (lambda (pend)
                (hash-put! pend-topic-subscriptions topic (cons (cons @source k) pend))
                (!!value (void) k)))
          (else
           (let (reqid (request-id))
             (hash-put! pend-subscriptions reqid topic)
             (hash-put! pend-topic-subscriptions topic [(cons @source k)])
             (wamp-send ws [SUBSCRIBE reqid (or opts empty-hash) topic])))))

        ((!wamp.unsubscribe topic)
         (remove-actor-subscription! topic @source))

        ((!wamp.publish topic opts args kws)
         (let (reqid (request-id))
           (wamp-send ws [PUBLISH reqid (or opts empty-hash) topic (message-tail args kws) ...])))

        ;; control
        ((!wamp.shutdown)
         (wamp-send ws [GOODBYE empty-hash "wamp.error.close_realm"])
         (raise 'shutdown))

        ((!wamp.close-connection e)
         (raise e))

        ((!wamp.remove-thread thread)
         (remove-thread! thread))

        (bogus
         (warning "unexpected message: ~a" bogus)))
    (loop))

  (def (send-shutdown-errors pend)
    (let (err (make-wamp-error 'wamp-client "client shutdown"))
      (for-each (cut send-pend-error <> err) pend)))

  (def (send-pend-error pend err)
    (with ([src . k] pend)
      (!!error src err k)))

  (try
   (loop)
   (catch (e)
     (unless (eq? e 'shutdown)
       (log-error "wamp client error" e))
     (websocket-close ws)
     (send-shutdown-errors (hash-values pend-calls))
     (for-each send-shutdown-errors (hash-values pend-subscriptions))
     (send-shutdown-errors (map car (hash-values pend-registrations)))
     (send-shutdown-errors (map car (hash-values pend-unregistrations)))
     (for-each (cut !!wamp.shutdown <>) (hash-keys actor-subscriptions))
     (unless (eq? e 'shutdown)
       (raise e)))))

(def (wamp-reader cli ws)
  (try
   (let lp ()
     (let (msg (wamp-recv ws))
       (!!wamp.receive cli msg)
       (lp)))
   (catch (e)
     (!!wamp.close-connection cli e))))

;;; Protocol Details
(def empty-hash (make-hash-table))

(defconst HELLO         1)
(defconst WELCOME       2)
(defconst ABORT         3)
(defconst GOODBYE       6)
(defconst ERROR         8)
(defconst PUBLISH      16)
(defconst PUBLISHED    17)
(defconst SUBSCRIBE    32)
(defconst SUBSCRIBED   33)
(defconst UNSUBSCRIBE  34)
(defconst UNSUBSCRIBED 35)
(defconst EVENT        36)
(defconst CALL         48)
(defconst RESULT       50)
(defconst REGISTER     64)
(defconst REGISTERED   65)
(defconst UNREGISTER   66)
(defconst UNREGISTERED 67)
(defconst INVOCATION   68)
(defconst YIELD        70)

(def session-details
  (hash
   (agent (string-append "Gerbil-" (gerbil-version-string)))
   (roles (hash
             (publisher empty-hash)
             (subscriber empty-hash)
             (caller empty-hash)
             (callee empty-hash)))))

(def (wamp-open-session ws realm)
  (wamp-send ws [HELLO realm session-details])
  (match (wamp-recv ws)
    ([(eq? WELCOME) sid details]
     (values sid details))
    ([(eq? ABORT) details reason]
     (raise (make-wamp-error 'wamp-open-session reason details)))))

(def (wamp-send ws msg)
  (let (outp (open-output-u8vector))
    (write-json msg outp)
    (websocket-send ws (get-output-u8vector outp) 'text)))

(def (wamp-recv ws)
  (let ((values bytes type) (websocket-recv ws))
    (if (eq? type 'text)
      (read-json (open-input-u8vector [char-encoding: 'UTF-8 init: bytes]))
      (begin
        (warning "wamp-recv: server sent binary data (~s)" (u8vector-length bytes))
        (raise-io-error 'wamp-recv "server sent binary data" bytes)))))
