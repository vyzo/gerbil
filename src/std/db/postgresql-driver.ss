;;; -*- Gerbil -*-
;;; (C) vyzo
;;; PostgreSQL driver

(import :gerbil/gambit/threads
        :gerbil/gambit/ports
        :gerbil/gambit/bits
        :std/actor/proto
        :std/actor/message
        :std/misc/channel
        :std/misc/list
        :std/net/bio
        :std/net/sasl
        :std/text/utf8
        :std/text/hex
        :std/crypto
        :std/logger
        :std/sugar
        :std/error
        :std/contract
        :std/db/dbi)
(export postgresql-connect!
        postgresql-prepare-statement!
        postgresql-close-statement!
        postgresql-exec!
        postgresql-query!
        postgresql-continue!
        postgresql-reset!
        postgresql-close!
        (rename: !token? query-token?))

;;; driver interface
(defproto postgresql
  (prepare name sql)
  (exec name params)
  (query name params)
  event:
  (continue token)
  (reset token)
  (close name)
  (shutdown))

(defrules with-driver ()
  ((_ conn driver body ...)
   (cond
    ((thread? conn)
     (let (driver conn)
       body ...))
    ((connection-e conn)
     => (lambda (driver) body ...))
    (else
     (error "connection has been closed" conn)))))

(defrules get-driver ()
  ((_ conn)
   (if (thread? conn) conn (connection-e conn))))

#;(defrules DEBUG ()
  ((_ what arg ...)
   (begin
     (display what)
     (begin (write arg) (display " ")) ...
     (newline))))

(defrules DEBUG ()
  ((_ what arg ...)
   (void)))

(def (postgresql-prepare-statement! conn name sql)
  (with-driver conn driver
    (!!postgresql.prepare driver name sql)))

(def (postgresql-close-statement! conn name)
  (alet (driver (get-driver conn))
    (!!postgresql.close driver name)))

(def (postgresql-exec! conn name bind)
  (with-driver conn driver
    (!!postgresql.exec driver name bind)))

(def (postgresql-query! conn name bind)
  (with-driver conn driver
    (!!postgresql.query driver name bind)))

(def/c (postgresql-continue! conn token)
  (@contract (!token? token))
  (with-driver conn driver
    (!!postgresql.continue driver token)))

(def/c (postgresql-reset! conn token)
  (@contract (!token? token))
  (alet (driver (get-driver conn))
    (!!postgresql.reset driver token)))

(def (postgresql-close! conn)
  (alet (driver (get-driver conn))
    (!!postgresql.shutdown driver)))

;;; driver implementation
(def (postgresql-connect! host port user passwd db)
  (def sock
    (open-tcp-client [server-address: host port-number: port]))

  (def buffer
    (box (make-u8vector 1024)))

  (def (start-driver! sock)
    (DEBUG "STARTING DRIVER")
    (let lp ()
      (match (postgresql-recv! sock buffer)
        (['ReadyForQuery _]
         (spawn/name 'postgresql-connection postgresql-driver sock))
        (['ErrorResponse msg . irritants]
         (apply raise-io-error 'postgresql-connect! msg irritants))
        (['NoticeResponse msg . irritants]
         (warning "NOTICE: ~a ~a" msg irritants)
         (lp))
        (else
         (lp)))))

  (defrules send! ()
    ((_ msg)
     (postgresql-send! sock msg)))

  (defrules recv! ()
    ((_ clause ...)
     (match (postgresql-recv! sock buffer)
       clause ...
       (['ErrorResponse msg . irritants]
        (apply raise-io-error 'postgresql-connect! msg irritants))
       (unexpected
        (raise-io-error 'postgresql-connect! "unexpected message" unexpected)))))

  (def (authen-pass sock pass)
    (send! ['PasswordMessage pass])
    (recv!
     (['AuthenticationRequest 'AuthenticationOk]
      (start-driver! sock))))

  (def (authen-cleartext sock)
    (DEBUG "AUTHEN CLEARTEXT")
    (authen-pass sock passwd))

  (def (authen-md5 sock salt)
    (def (md5-hex data)
      (hex-encode (md5 data)))

    (DEBUG "AUTHEN MD5")
    (let* ((word1 (string-append passwd user))
           (word2 (md5-hex word1))
           (word3 (u8vector-append (string->utf8 word2) salt))
           (word4 (md5-hex word3))
           (pass (string-append "md5" word4)))
      (authen-pass sock pass)))

  (def (authen-sasl sock mechanisms)
    (DEBUG "AUTHEN SASL")
    (unless (member "SCRAM-SHA-256" mechanisms)
      (raise-io-error 'postgresql-connect! "unknown SASL authentication mechanisms" mechanisms))
    (let* ((ctx (scram-sha-256-begin "" passwd))
           (msg (scram-client-first-message ctx)))
      (send! ['SASLInitialResponse "SCRAM-SHA-256" msg])
      (recv!
       (['AuthenticationRequest 'AuthenticationSASLContinue msg]
        (scram-client-first-server-message! ctx msg)
        (let (msg (scram-client-final-message ctx))
          (send! ['SASLResponse msg])
          (recv!
           (['AuthenticationRequest 'AuthenticationSASLFinal msg]
            (scram-client-final-server-message! ctx msg)
            (recv!
             (['AuthenticationRequest 'AuthenticationOk]
              (start-driver! sock))))))))))

  (start-logger!)
  (DEBUG "STARTUP")
  (try
   (send! ['StartupMessage ["user" . user] (if db [["database" . db]] []) ...])
   (recv!
    (['AuthenticationRequest what . rest]
     (DEBUG "AUTHENTICATION REQUEST " what)
     (case what
       ((AuthenticationOk)
        (start-driver! sock))
       ((AuthenticationCleartextPassword)
        (authen-cleartext sock))
       ((AuthenticationMD5Password)
        (authen-md5 sock (car rest)))
       ((AuthenticationSASL)
        (authen-sasl sock rest))
       (else
        (raise-io-error 'postgresql-connect! "unsupported authentication mechanism" what)))))
   (catch (e)
     (close-port sock)
     (raise e))))

(def (postgresql-driver sock)
  (def query-limit 1000)
  (def query-output #f)
  (def query-token #f)

  (def buffer (box (make-u8vector 1024)))

  (def deferred-close [])

  (def (send! msg)
    (postgresql-send! sock msg))

  (def (recv!)
    (match (postgresql-recv! sock buffer)
      (['NoticeResponse msg . irritants]
       (notice! msg irritants)
       (recv!))
      (msg msg)))

  (def (notice! msg irritants)
    (warning "NOTICE: ~a ~a" msg irritants))

  (def (resync!)
    (let lp ()
      (match (recv!)
        (['ReadyForQuery _]
         (void))
        (else
         (lp)))))

  (def (maybe-sync!)
    (when query-output
      (channel-sync query-output (make-sql-error "portal expired" [] 'postgresql-query-pump!))
      (channel-close query-output)
      (set! query-output #f)
      (set! query-token #f)
      (resync!)
      (let (to-close deferred-close)
        (set! deferred-close [])
        (for-each close to-close))))

  (def (prepare name sql)
    ;; Parse (name sql) -> ParseComplete | ErrorResponse
    ;; Describe (name)  -> ParameterDescription | ErrorResponse
    ;;                     RowDescription | NoData
    ;; Sync             -> ReadyForQuery
    (def params #f)
    (def cols #f)

    (maybe-sync!)
    (send! ['Parse name sql])
    (send! ['Describe #\S name])
    (send! '(Sync))
    (match (recv!)
      (['ParseComplete]
       (void))
      (['ErrorResponse msg . irritants]
       (resync!)
       (apply raise-sql-error 'postgresql-prepare! msg irritants)))
    (match (recv!)
      (['ParameterDescription . query-params]
       (set! params query-params))
      (['ErrorResponse msg . irritants]
       (resync!)
       (apply raise-sql-error 'postgresql-prepare! msg irritants)))
    (match (recv!)
      (['RowDescription . fields]
       (set! cols fields))
      (['NoData]
       (set! cols [])))
    (resync!)
    (values params cols))

  (def (exec name params)
    ;; Bind ("" name params) ->  BindComplete | ErrorResponse
    ;; Execute ("")          -> DataRow ...
    ;;                          CommandComplete | EmptyQueryResponse
    ;;                          | ErrorResponse | PortalSuspended.
    ;; Sync                  -> ReadyForQuery
    (def res #f)

    (maybe-sync!)
    (send! ['Bind "" name . params])
    (send! '(Execute "" 1))
    (send! '(Sync))
    (match (recv!)
      (['BindComplete]
       (void))
      (['ErrorResponse msg . irritants]
       (resync!)
       (apply raise-sql-error 'postgresql-exec! msg irritants)))
    (let lp ()
      (match (recv!)
        (['DataRow . cols]
         (lp))
        (['CommandComplete tag]
         (set! res tag))
        ([(or 'PortalSuspended 'EmptyQueryResponse)]
         (void))
        (['ErrorResponse msg . irritants]
         (resync!)
         (apply raise-sql-error 'postgreql-exec msg irritants))))
    (resync!)
    res)

  ;; Query backpressure mechanism: the query pump reads and buffers up
  ;; to query-limit rows before requiring a continue signal from
  ;; the query client.
  ;; If the client aborts (or issues a new query), the remaining results
  ;; of the query will be skipped over on resync.
  ;; The plan was originally to use (named) portals with Execute limit
  ;; and rely on PortalSuspended to implement staging of input.
  ;; Unfortunately, the server (tested with 10.1) doesn't start
  ;; sending anything back until it sees a Sync; this kills
  ;; the portal unless it's in a BEGIN/COMMIT block so the backpressure
  ;; idea using portal suspension can't work without wrapping every
  ;; query in an explicit txn (which is undesirable for obvious reasons)
  (def (query-start name params)
    ;; Bind ("" name params) ->  BindComplete | ErrorResponse
    (maybe-sync!)
    (send! ['Bind "" name . params])
    (send! '(Execute "" 0))
    (send! '(Sync))
    (match (recv!)
      (['BindComplete]
       (let ((ch (make-channel query-limit))
             (token (make-!token)))
         (set! query-output ch)
         (set! query-token token)
         (values ch token)))
      (['ErrorResponse msg . irritants]
       (resync!)
       (apply raise-sql-error 'postgresql-query! msg irritants))))

  (def (query-pump)
    ;; Execute ("")          -> DataRow ...
    ;;                          CommandComplete | EmptyQueryResponse
    ;;                          | ErrorResponse | PortalSuspended.
    ;; Sync                  -> ReadyForQuery
    (let/cc break
      (let lp ()
        (match (recv!)
          (['DataRow . cols]
           (cond
            ((channel-try-put query-output cols)
             (lp))
            (else
             (channel-sync query-output cols query-token)
             (break))))
          (['CommandComplete tag]
           (void))
          ([(or 'PortalSuspended 'EmptyQueryResponse)]
           (void))
          (['ErrorResponse msg . irritants]
           (channel-sync query-output (make-sql-error msg irritants 'postgresql-query!)))))
      (channel-close query-output)
      (set! query-output #f)
      (set! query-token #f)
      (resync!)))

  (def (close name)
    ;; Close (name) -> CloseComplete | ErrorResponse
    (if query-output
      (push! name deferred-close)
      (begin
        (send! ['Close #\S name])
        (send! '(Sync))
        (match (recv!)
          (['CloseComplete]
           (void))
          (['ErrorResponse msg . irritants]
           (warning "error closing statement ~a: ~a" name msg)))
        (resync!))))

  (def (shutdown!)
    (send! '(Sync))
    (resync!)
    (send! '(Terminate))
    (raise 'shutdown))

  (defrules do-action ()
    ((_ k action)
     (try
      (let (res action)
        (!!value res k))
      (catch (e)
        (!!error e k)
        (unless (sql-error? e)
          (raise e)))))
    ((recur k action continue ...)
     (begin
       (recur k action)
       continue ...)))

  (def (loop)
    (<- ((!postgresql.prepare name sql k)
         (do-action k (prepare name sql)))
        ((!postgresql.exec name params k)
         (do-action k (exec name params)))
        ((!postgresql.query name params k)
         (do-action k (query-start name params) (query-pump)))
        ((!postgresql.continue token)
         (when (eq? token query-token)
           (query-pump)))
        ((!postgresql.reset token)
         (when (eq? token query-token)
           (maybe-sync!)))
        ((!postgresql.close name)
         (close name))
        ((!postgresql.shutdown)
         (shutdown!))
        (bogus
         (warning "unexpected message: ~a" bogus)))
    (loop))

  (try
   (loop)
   (catch (e)
     (unless (eq? e 'shutdown)
       (log-error "unhandled exception" e)
       (raise e)))
   (finally
    (when query-output
      (channel-sync query-output (make-sql-error "connection error" [] 'postgresql-driver))
      (channel-close query-output))
    (close-port sock))))

;;; Protocol I/O
(def (postgresql-send! sock msg)
  (def (marshal-and-write tid body marshal)
    (let* ((payload (marshal body))
           (payload-len
            (cond
             ((u8vector? payload)
              (u8vector-length payload))
             ((chunked-output-buffer? payload)
              (chunked-output-length payload))
             (else
              (raise-io-error 'postgresql-send! "unexpected payload" tid body payload)))))
      (when tid
        (write-u8 tid sock))
      (write-u32 (##fx+ payload-len 4) sock)
      (if (u8vector? payload)
        (let (len (u8vector-length payload))
          (when (##fx> len 0)
            (write-subu8vector payload 0 len sock)))
        (for-each
          (lambda (u8v)
            (write-subu8vector u8v 0 (u8vector-length u8v) sock))
          (chunked-output-chunks payload)))
      (force-output sock)))

  (def (write-u32 u32 sock)
    (write-u8 (##fxand (##fxarithmetic-shift-right u32 24) #xff) sock)
    (write-u8 (##fxand (##fxarithmetic-shift-right u32 16) #xff) sock)
    (write-u8 (##fxand (##fxarithmetic-shift-right u32 8) #xff) sock)
    (write-u8 (##fxand u32 #xff) sock))

  (DEBUG "SEND " msg)
  (with ([tag . body] msg)
    (cond
     ((hash-get +frontend-messages+ tag)
      => (match <>
           ([tid . marshal]
            (marshal-and-write tid body marshal))))
     ((eq? tag 'StartupMessage)
      (marshal-and-write #f body marshal-startup))
     (else
      (raise-io-error 'postgresql-send! "cannot marshal; unknown message tag" msg)))))

(def (postgresql-recv! sock buf)
  (def (read-u32 sock u8v)
    (let (rd (read-subu8vector u8v 0 4 sock))
      (cond
       ((##fx< rd 4)
        (raise-io-error 'postgresql-recv! "premature end of input" rd))
       ((##fxarithmetic-shift-left? (##u8vector-ref u8v 0) 24)
        => (lambda (bits)
             (##fxior bits
                      (##fxarithmetic-shift-left (##u8vector-ref u8v 1) 16)
                      (##fxarithmetic-shift-left (##u8vector-ref u8v 2) 8)
                      (##u8vector-ref u8v 3))))
       (else
        (bitwise-ior (arithmetic-shift (##u8vector-ref u8v 0) 24)
                     (##fxarithmetic-shift-left (##u8vector-ref u8v 1) 16)
                     (##fxarithmetic-shift-left (##u8vector-ref u8v 2) 8)
                     (##u8vector-ref u8v 3))))))

  (DEBUG "RECEIVE!")
  (let* ((tid (read-u8 sock))
         (_ (when (eof-object? tid)
              (raise-io-error 'postgresql-recv! "connection closed")))
         (payload-len (read-u32 sock (unbox buf)))
         (payload-len (##fx- payload-len 4))
         (u8buf
          (let (u8buf (unbox buf))
            (if (##fx< (u8vector-length u8buf) payload-len)
              (let (u8buf (make-u8vector payload-len))
                (set! (box buf) u8buf)
                u8buf)
              u8buf)))
         (rd
          (if (##fx> payload-len 0)
            (read-subu8vector u8buf 0 payload-len sock)
            0))
         (_ (when (##fx< rd payload-len)
              (raise-io-error 'postgresql-recv! "premature end of input" rd tid payload-len)))
         (bio (open-input-buffer u8buf 0 payload-len)))

    (DEBUG "READ MESSAGE " tid payload-len)
    (cond
     ((vector-ref +backend-messages+ tid)
      => (match <>
           ([tag . unmarshal]
            (DEBUG "UNMARSHAL " tag)
            (let* ((body (unmarshal bio))
                   (msg (cons tag body)))
              (DEBUG "RECEIVE " msg)
              msg))))
     (else
      (raise-io-error 'postgresql-recv! "unexpected backend message" tid)))))

;;; message unmarshaling
(def (unmarshal-ignore bio)
  '(...))

(def (unmarshal-empty bio)
  '())

(def (unmarshal-authen-request bio)
  (let (t (bio-read-u32 bio))
    (case t
      ((0) '(AuthenticationOk))
      ((2) '(AuthenticationKerberosV5))
      ((3) '(AuthenticationCleartextPassword))
      ((5)
       (let (salt (make-u8vector 4))
         (bio-read-bytes salt bio)
         ['AuthenticationMD5Password salt]))
      ((6) '(AuthenticationSCMCredential))
      ((7) '(AuthenticationGSS))
      ((8)
       (let (data (unmarshal-bytes-rest bio))
         ['AuthenticationGSSContinue data]))
      ((9) '(AuthenticationSSPI))
      ((10)
       (let (mechanisms (unmarshal-string-list bio))
         ['AuthenticationSASL . mechanisms]))
      ((11)
       (let (data (unmarshal-string-rest bio))
         ['AuthenticationSASLContinue data]))
      ((12)
       (let (data (unmarshal-string-rest bio))
         ['AuthenticationSASLFinal data]))
      (else
       [t '...]))))

(def (unmarshal-string-list bio)
  (let lp ((r []))
    (let (next (unmarshal-string bio))
      (if (string-empty? next)
        (reverse r)
        (lp (cons next r))))))

(def (unmarshal-string bio)
  (let lp ((bytes []))
    (let (next (bio-read-u8 bio))
      (if (##fx= next 0)
        (utf8->string (list->u8vector (reverse bytes)))
        (lp (cons next bytes))))))

(def (unmarshal-bytes-rest bio)
  (let* ((count (bio-input-count bio))
         (data (make-u8vector count)))
    (bio-read-bytes data bio)
    data))

(def (unmarshal-string-rest bio)
  (let (count (bio-input-count bio))
    (bio-input-utf8-decode count bio)))

(def (unmarshal-complete bio)
  (let (tag (unmarshal-string bio))
    [tag]))

(def (unmarshal-data-row bio)
  (let (count (bio-read-u16 bio))
    (let lp ((i 0) (r []))
      (if (##fx< i count)
        (let (len (bio-read-s32 bio))
          (if (##fx>= len 0)
            (let (str (bio-input-utf8-decode len bio))
              (lp (##fx+ i 1) (cons str r)))
            (lp (##fx+ i 1) (cons #f r)))) ; NULL
        (reverse r)))))

(def (unmarshal-error-notice bio)
  (let lp ((r []))
    (let (t (bio-read-u8 bio))
      (if (##fx= t 0)
        (let* ((alist (reverse r))
               (msg (assgetq #\M alist)))
          (cons msg alist))
        (let (field (unmarshal-string bio))
          (lp (cons (cons (integer->char t) field) r)))))))

(def (unmarshal-param-description bio)
  (let (count (bio-read-u16 bio))
    (let lp ((i 0) (r []))
      (if (##fx< i count)
        (let (oid (bio-read-u32 bio))
          (lp (##fx+ i 1) (cons oid r)))
        (reverse r)))))

(def (unmarshal-row-description bio)
  (let (count (bio-read-u16 bio))
    (let lp ((i 0) (r []))
      (if (##fx< i count)
        (let* ((field-name (unmarshal-string bio))
               (table-id (bio-read-u32 bio))
               (attr-id (bio-read-u16 bio))
               (type-id (bio-read-u32 bio))
               (type-sz (bio-read-s16 bio))
               (modifier (bio-read-s32 bio))
               (fmt (bio-read-u16 bio)))
          (lp (##fx+ i 1)
              (cons [field-name table-id attr-id type-id type-sz modifier fmt] r)))
        (reverse r)))))

(def (unmarshal-ready bio)
  (let (status (bio-read-u8 bio))
    [(integer->char status)]))

;;; message marshaling
(def (marshal-fail what)
  (lambda (body)
    (raise-io-error 'postgresql-send! "Cannot marshal; unsupported message" (cons what body))))

(def (marshal-empty body)
  '#u8())

(def (marshal-string str bio)
  (bio-write-string str bio)
  (bio-write-u8 0 bio))

(def (marshal-startup body)
  (with ([[param . value] ...] body)
    (let (bio (open-serializer-output-buffer))
      (bio-write-u32 196608 bio) ; Protocol v3.0
      (for-each
        (lambda (param value)
          (marshal-string param bio)
          (marshal-string value bio))
        param value)
      (bio-write-u8 0 bio))))

(def (marshal-bind body)
  (with ([portal-name stmt-name . params] body)
    (let (bio (open-serializer-output-buffer))
      (marshal-string portal-name bio)
      (marshal-string stmt-name bio)
      (bio-write-u16 0 bio)
      (bio-write-u16 (length params) bio)
      (for-each
        (lambda (param)
          (cond
           ((not param)
            (bio-write-s32 -1 bio))
           ((string? param)
            (let (len (string-utf8-length param))
              (bio-write-u32 len bio)
              (bio-write-string param bio)))
           ((u8vector? param)
            (bio-write-u32 (u8vector-length param) bio)
            (bio-write-bytes param bio))
           (else
            (raise-io-error 'postgresql-send! "Cannot marshal; bad parameter" param))))
        params)
      (bio-write-u16 0 bio)
      bio)))

(def (marshal-close body)
  (marshal-describe body))

(def (marshal-describe body)
  (with ([what name] body)
    (let (bio (open-serializer-output-buffer))
      (bio-write-u8 (char->integer what) bio)
      (marshal-string name bio)
      bio)))

(def (marshal-exec body)
  (with ([portal limit] body)
    (let (bio (open-serializer-output-buffer))
      (marshal-string portal bio)
      (bio-write-u32 0 bio)
      bio)))

(def (marshal-parse body)
  (with ([stmt sql] body)
    (let (bio (open-serializer-output-buffer))
      (marshal-string stmt bio)
      (marshal-string sql bio)
      (bio-write-u16 0 bio)
      bio)))

(def (marshal-passwd body)
  (with ([passwd] body)
    (let (bio (open-serializer-output-buffer))
      (marshal-string passwd bio)
      bio)))

(def (marshal-query body)
  (with ([sql] body)
    (let (bio (open-serializer-output-buffer))
      (marshal-string sql bio)
      bio)))

(def (marshal-sasl-initial-reponse body)
  (with ([mechanism data] body)
    (let (bio (open-serializer-output-buffer))
      (marshal-string mechanism bio)
      (if data
        (let (len (string-utf8-length data))
          (bio-write-u32 len bio)
          (bio-write-string data bio))
        (bio-write-s32 -1 bio))
      bio)))

(def (marshal-sasl-response body)
  (with ([data] body)
    (string->utf8 data)))

;;; dispatch tables
(def +backend-messages+
  (make-vector 256 #f))
(def +frontend-messages+
  (make-hash-table-eq))

(defrules defmessage-backend ()
  ((_ (id char unmarshal) ...)
   (begin
     (let (t (char->integer char))
       (vector-set! +backend-messages+ t (cons 'id unmarshal)))
     ...)))

(defrules defmessage-frontend ()
  ((_ (id char marshal) ...)
   (begin
     (let (t (char->integer char))
       (hash-put! +frontend-messages+ 'id (cons t marshal)))
     ...)))

(defmessage-backend
  (AuthenticationRequest    #\R unmarshal-authen-request)
  (BackendKeyData           #\K unmarshal-ignore)
  (BindComplete             #\2 unmarshal-empty)
  (CloseComplete            #\3 unmarshal-empty)
  (CommandComplete          #\C unmarshal-complete)
  (CopyData                 #\d unmarshal-ignore)
  (CopyDone                 #\c unmarshal-ignore)
  (CopyInResponse           #\G unmarshal-ignore)
  (CopyOutResponse          #\H unmarshal-ignore)
  (CopyBothResponse         #\W unmarshal-ignore)
  (DataRow                  #\D unmarshal-data-row)
  (EmptyQueryResponse       #\I unmarshal-empty)
  (ErrorResponse            #\E unmarshal-error-notice)
  (FunctionCallResponse     #\V unmarshal-ignore)
  (NegotiateProtocolVersion #\v unmarshal-ignore)
  (NoData                   #\n unmarshal-empty)
  (NoticeResponse           #\N unmarshal-error-notice)
  (NotificationResponse     #\A unmarshal-ignore)
  (ParameterDescription     #\t unmarshal-param-description)
  (ParameterStatus          #\S unmarshal-ignore)
  (ParseComplete            #\1 unmarshal-empty)
  (PortalSuspended          #\s unmarshal-empty)
  (ReadyForQuery            #\Z unmarshal-ready)
  (RowDescription           #\T unmarshal-row-description))

(defmessage-frontend
  (Bind                     #\B  marshal-bind)
  (Close                    #\C  marshal-close)
  (CopyData                 #\d (marshal-fail 'CopyData))
  (CopyDone                 #\c (marshal-fail 'CopyDone))
  (CopyFail                 #\f (marshal-fail 'CopyFail))
  (Describe                 #\D  marshal-describe)
  (Execute                  #\E  marshal-exec)
  (Flush                    #\H  marshal-empty)
  (FunctionCall             #\F (marshal-fail 'FunctionCall))
  (GSSResponse              #\p (marshal-fail 'GSSResponse))
  (Parse                    #\P  marshal-parse)
  (PasswordMessage          #\p  marshal-passwd)
  (Query                    #\Q  marshal-query)
  (SASLInitialResponse      #\p  marshal-sasl-initial-reponse)
  (SASLResponse             #\p  marshal-sasl-response)
  (Sync                     #\S  marshal-empty)
  (Terminate                #\X  marshal-empty))
