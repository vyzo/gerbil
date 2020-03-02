;;; -*- Gerbil -*-
;;; (C) vyzo
;;; websocket client

(import :gerbil/gambit/threads
        :gerbil/gambit/ports
        :gerbil/gambit/os
        :gerbil/gambit/bits
        :std/srfi/13
        :std/error
        :std/contract
        :std/sugar
        :std/logger
        :std/crypto/digest
        :std/crypto/etc
        :std/misc/queue
        :std/misc/timeout
        :std/net/request
        :std/text/utf8
        :std/text/base64)
(export open-websocket-client
        websocket?
        websocket-recv websocket-read
        websocket-send websocket-write
        websocket-close
        set-websocket-max-frame-size!
        set-websocket-max-message-size!)

(def wsmagic "258EAFA5-E914-47DA-95CA-C5AB0DC85B11")

(def (open-websocket-client url
                            redirect: (redirect #t)
                            headers:  (headers #f)
                            cookies:  (cookies #f)
                            params:   (params #f))
  (let* ((url (url->request-url url))
         (nonce (random-bytes 16))
         (nonce64 (base64-encode nonce))
         (headers (cons* ["Upgrade" . "websocket"]
                         ["Connection" . "Upgrade"]
                         ["Sec-WebSocket-Key" . nonce64]
                         ["Sec-WebSocket-Version" . 13]
                         (or headers [])))
         (req (http-get url
                        redirect: redirect
                        headers: headers
                        cookies: cookies
                        params: params)))
    (try
     (let (status (request-status req))
       (unless (##fx= status 101)
         (raise-io-error 'open-websocket-client
                         "Unexpected server response"
                         url status)))

     (let* ((rheaders (request-headers req))
            (Connection (assoc "Connection" rheaders))
            (Upgrade (assoc "Upgrade" rheaders))
            (Sec-WebSocket-Accept (assoc "Sec-Websocket-Accept" rheaders))
            (Sec-WebSocket-Extensions (assoc "Sec-Websocket-Extensions" rheaders))
            (Sec-WebSocket-Protocol (assoc "Sec-Websocket-Protocol" rheaders)))

       (unless (and Connection (equal? (string-downcase (cdr Connection)) "upgrade"))
         (raise-io-error 'open-websocket-client
                         "Bad server response; no connection upgrade"
                         url Connection))

       (unless (and Upgrade (equal? (string-downcase (cdr Upgrade)) "websocket"))
         (raise-io-error 'open-websocket-client
                         "Bad server response; no websocket upgrade"
                         url Upgrade))

       (let* ((accept64 (and Sec-WebSocket-Accept (cdr Sec-WebSocket-Accept)))
              (digest (make-digest digest::sha1))
              (_ (digest-update! digest (string->utf8 nonce64)))
              (_ (digest-update! digest (string->utf8 wsmagic)))
              (verify (digest-final! digest))
              (verify64 (base64-encode verify)))
         (unless (equal? accept64 verify64)
           (raise-io-error 'open-websocket-client
                           "Bad server response; nonce verification failure"
                           url nonce64 accept64 verify64)))

       (when Sec-WebSocket-Extensions
         (raise-io-error 'open-websocket-client
                         "Bad server response; includes unsupported exensions"
                         url Sec-WebSocket-Extensions))

       (when Sec-WebSocket-Protocol
         (let* ((proto (cdr Sec-WebSocket-Protocol))
                (uproto (assoc "Sec-WebSocket-Protocol" headers))
                (uproto (string-split (and uproto (cdr uproto)) #\,)))
           (unless (member proto uproto)
             (raise-io-error 'open-websocket-client
                             "Bad server response; unexpected protocol"
                             url Sec-WebSocket-Protocol)))))

     (make-websocket-client (request-port req))

     (catch (e)
       (request-close req)
       (raise e)))))

(def (url->request-url url)
  (let* (colon (string-index url #\:))
    (if colon
      (let (scheme (substring url 0 colon))
        (case scheme
          (("ws")
           (string-append "http" (substring url colon (string-length url))))
          (("wss")
           (string-append "https" (substring url colon (string-length url))))
          (else url)))
      url)))

(defstruct websocket (port rd wr cs q mx cv)
  constructor: :init!
  final: #t)

(defmethod {:init! websocket}
  (lambda (self port)
    (struct-instance-init! self port
      #f #f #f                          ; reader writer closed status
      (make-queue)
      (make-mutex)
      (make-condition-variable))))

(def (make-websocket-client port)
  (start-logger!)
  (let* ((ws (make-websocket port))
         (reader (spawn/name 'websocket-reader websocket-reader ws))
         (writer (spawn/name 'websocket-writer websocket-writer ws)))
    (set! (websocket-rd ws)
      reader)
    (set! (websocket-wr ws)
      writer)
    ws))

(def/c (websocket-send ws bytes type)
  (@contract (u8vector? bytes)
             (or (eq? type 'binary)
                 (eq? type 'text)))
  (cond
   ((websocket-cs ws)
    => (lambda (how)
         (raise-io-error 'websocket-send "Websocket has been closed" ws how)))
   (else
    (thread-send (websocket-wr ws) (cons type bytes)))))

(def (websocket-write ws obj)
  (cond
   ((string? obj)
    (websocket-send ws (string->utf8 obj) 'text))
   ((u8vector? obj)
    (websocket-send ws obj 'binary))
   (else
    (error "Bad argument; expected bytes or string" obj))))

(def (websocket-recv ws (timeo #f) (raise? #t))
  (let (timeo (make-timeout timeo))
    (with ((websocket _ _ _ _ q mx cv) ws)
      (let lp ()
        (mutex-lock! mx)
        (cond
         ((not (queue-empty? q))
          (with ([type . data] (dequeue! q))
            (mutex-unlock! mx)
            (values data type)))
         ((websocket-cs ws)
          => (lambda (how)
               (mutex-unlock! mx)
               (if raise?
                 (raise-io-error 'websocket-recv "Websocket has been closed" ws how)
                 #!eof)))
         ((mutex-unlock! mx cv timeo)
          (lp))
         (raise?
          (raise-timeout 'websocket-recv "timeout" ws))
         (else #f))))))

(def (websocket-read ws (timeo #f) (raise? #f))
  (match (websocket-recv ws timeo raise?)
    ((values data 'binary)
     data)
    ((values data 'text)
     (utf8->string data))
    (r r)))

(def (websocket-close ws (how 1000) hard: (hard? #f))
  (with ((websocket port _ writer cs q mx cv) ws)
    (when hard?
      (close-port port))
    (unless cs
      (mutex-lock! mx)
      (if (websocket-cs ws)
        (mutex-unlock! mx)
        (let (how (if hard? 'abort how))
          (set! (websocket-cs ws) how)
          (thread-send writer (cons 'close how))
          (condition-variable-broadcast! cv)
          (mutex-unlock! mx))))))

;; Base Framing Protocol [rfc6455]
;;
;;  0                   1                   2                   3
;;  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
;; +-+-+-+-+-------+-+-------------+-------------------------------+
;; |F|R|R|R| opcode|M| Payload len |    Extended payload length    |
;; |I|S|S|S|  (4)  |A|     (7)     |             (16/64)           |
;; |N|V|V|V|       |S|             |   (if payload len==126/127)   |
;; | |1|2|3|       |K|             |                               |
;; +-+-+-+-+-------+-+-------------+ - - - - - - - - - - - - - - - +
;; |     Extended payload length continued, if payload len == 127  |
;; + - - - - - - - - - - - - - - - +-------------------------------+
;; |                               |Masking-key, if MASK set to 1  |
;; +-------------------------------+-------------------------------+
;; | Masking-key (continued)       |          Payload Data         |
;; +-------------------------------- - - - - - - - - - - - - - - - +
;; :                     Payload Data continued ...                :
;; + - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - +
;; |                     Payload Data continued ...                |
;; +---------------------------------------------------------------+
;;

(def max-frame-size (expt 2 20))        ; 1MB
(def max-message-size (expt 2 20))      ; 1MB

(def (set-websocket-max-frame-size! sz)
  (set! max-frame-size sz))

(def (set-websocket-max-message-size! sz)
  (set! max-message-size sz))

;; reader thread -- reads frames, assembles messages and enques them
;; in the websocket queue.
(def (websocket-reader ws)
  (def buf (make-u8vector 1024))

  (def (skip-to-eof port)
    (let (len (u8vector-length buf))
      (let lp ()
        (let (rd (read-subu8vector buf 0 len port))
          (when (##fx= len rd)
            (lp))))))

  (def (skip-payload port plen)
    (let (len (u8vector-length buf))
      (let lp ((need plen))
        (cond
         ((##fxzero? need))
         ((##fx<= need len)
          (let (rd (read-subu8vector buf 0 need port))
            (when (##fx< rd need)
              (read-eof))))
         (else
          (let (rd (read-subu8vector buf 0 len port))
            (if (##fx< rd len)
              (read-eof)
              (lp (##fx- need len)))))))))

  ;; => (values fin opcode mask plen)
  (def (read-header port)
    (let* ((b0 (read-u8 port))
           (_ (when (eof-object? b0)
                (read-eof)))
           (b1 (read-u8 port))
           (_ (when (eof-object? b1)
                (read-eof))))
      (values (##fxand b0 #x80)
              (##fxand b0 #x0f)
              (##fxand b1 #x80)
              (##fxand b1 #x7f))))

  (def (read-payload port plen)
    (if (##fxzero? plen)
      '#u8()
      (let* ((data (make-u8vector plen))
             (rd (read-subu8vector data 0 plen port)))
        (if (##fx< rd plen)
          (read-eof)
          data))))

  (def (read-u16 port)
    (let* ((b0 (read-u8 port))
           (_ (when (eof-object? b0)
                (read-eof)))
           (b1 (read-u8 port))
           (_ (when (eof-object? b1)
                (read-eof))))
      (##fxior (##fxarithmetic-shift b0 8) b1)))

  (def (read-u64 port)
    (let (rd (read-subu8vector buf 0 8 port))
      (if (##fx= rd 8)
        (let lp ((k 0) (r 0))
          (if (##fx< k 8)
            (lp (##fx+ k 1)
                (bitwise-ior (arithmetic-shift r 8)
                             (##u8vector-ref buf k)))
            r))
        (read-eof))))

  (def (read-eof)
    (raise 'eof))

  (with ((websocket port _ writer _ q mx cv) ws)
    (def (receive type data)
      (mutex-lock! mx)
      (if (websocket-cs ws)
        (begin
          ;; the websocket has been closed; abort and close the input port.
          ;; strictly speaking this is out of spec, as we are supposed to
          ;; wait for a close from the server; however:
          ;; - we are no longer interested in new messages.
          ;; - buggy servers in the wild may take a long time to respond
          ;;   to the close, if at all, while still sending us stuff that
          ;;   fills the queue with no backpressure and keeps the socket
          ;;   open.
          ;; - so damn the torpedoes, just abort.
          (mutex-unlock! mx)
          (raise 'abort))
        (begin
          (enqueue! q (cons type data))
          (condition-variable-broadcast! cv)
          (mutex-unlock! mx))))

    (try
     (let lp ((type #f) (frags []))
      (let* (((values fin opcode mask plen)
              (read-header port))
             (plen
              (case plen
                ((126) (read-u16 port))
                ((127) (read-u64 port))
                (else plen))))
        (cond
         ((not (##fxzero? mask))
          (warning "server sent masked frame; closing websocket connection")
          (websocket-close ws 1002)
          (skip-to-eof port))
         ((> plen max-frame-size)
          (warning "frame size ~a exceeds max frame size; closing websocket connection"
                   plen)
          (websocket-close ws 1009)
          (skip-to-eof port))
         (else
          (case opcode
            ((#x0)                      ; continuation frame
             (let (dlen (foldl ##fx+ plen (map u8vector-length frags)))
               (cond
                ((not type)
                 (warning "unexpected continuation frame from server; closing websocket connection")
                 (websocket-close ws 1002)
                 (skip-to-eof port))
                ((##fx> dlen max-message-size)
                 (warning "message length ~a exceeds max message size; closing websocket connection"
                          dlen)
                 (websocket-close ws 1009)
                 (skip-to-eof port))
                ((##fxzero? fin)
                 (if (##fxzero? plen)
                   (lp type frags)      ; empty frame, skip
                   (let (data (read-payload port plen))
                     (lp type (cons data frags)))))
                (else
                 (let* ((data (read-payload port plen))
                        (message (append-u8vectors (reverse (cons data frags)))))
                   (receive type message)
                   (lp #f []))))))
            ((#x1 #x2)                  ; text or binary frame
             (let (xtype (if (##fx= opcode #x1) 'text 'binary))
               (cond
                (type                   ; receiving cont frames
                 (warning "unexpected frame ~x from server; closing websocket connection"
                          opcode)
                 (websocket-close ws 1002)
                 (skip-to-eof port))
                ((##fxzero? fin)        ; first fragment
                 (let (data (read-payload port plen))
                   (lp xtype [data])))
                (else                   ; unfragmented msg
                 (let (data (read-payload port plen))
                   (receive xtype data)
                   (lp #f []))))))
            ((#x8)                      ; connection close
             (let (how (read-u16 port))
               (websocket-close ws how)
               (skip-to-eof port)))
            ((#x9)                      ; ping
             (let (data (read-payload port plen))
               (thread-send writer (cons 'pong data))
               (lp type frags)))
            ((#xA)                      ; pong
             (skip-payload port plen)
             (lp type frags))
            (else
             (warning "unexpected frame ~x from server; closing websocket connection"
                      opcode)
             (websocket-close ws 1002)
             (skip-to-eof port)))))))
     (catch (e)
       (case e
         ((eof)
          (websocket-close ws 'eof))
         ((abort)
          (void))
         (else
          (log-error "unhandled exception" e)
          (websocket-close ws 'abort)
          (raise e)))
       e)
     (finally
      (with-catch void (cut close-input-port port))))))

(def (websocket-writer ws)
  (def buf (make-u8vector 65535))
  (def mask-bytes (make-u8vector 4))

  (def (write-u16 plen port)
    (write-u8 (##fxand (##fxarithmetic-shift plen -8) #xff) port)
    (write-u8 (##fxand plen #xff) port))

  (def (write-payload mask data start end port)
    (let lp ((k start) (x 0))
      (if (##fx< k end)
        (begin
          (##u8vector-set! buf x
                           (##fxxor (##u8vector-ref data k)
                                    (##u8vector-ref mask (##fxmodulo x 4))))
          (lp (##fx+ k 1) (##fx+ x 1)))
        (write-subu8vector buf 0 x port))))

  (def (send-frame port fin opcode data start end)
    (let* ((plen (##fx- end start))
           (fin (##fxarithmetic-shift fin 7))
           (b0 (##fxior fin opcode))
           (mask (##fxarithmetic-shift 1 7))
           (b1 (##fxior mask (if (##fx< plen 126) plen 126))))
      (random-bytes! mask-bytes)
      (write-u8 b0 port)
      (write-u8 b1 port)
      (unless (##fx< plen 126)
        (write-u16 plen port))
      (write-subu8vector mask-bytes 0 4 port)
      (write-payload mask-bytes data start end port)
      (force-output port)))

  (def (send port opcode data)
    (let (end (u8vector-length data))
      (let lp ((start 0) (opcode opcode))
        (let (have (##fx- end start))
          (if (##fx< have 65536)
            (send-frame port 1 opcode data start end)
            (let (xend (##fx+ start 65535))
              (send-frame port 0 opcode data start xend)
              (lp xend #x0)))))))

  (with ((websocket port) ws)
    (try
     (let lp ()
       (match (thread-receive)
         (['text . data]
          (send port #x1 data)
          (lp))
         (['binary . data]
          (send port #x2 data)
          (lp))
         (['pong . data]
          (send port #xA data)
          (lp))
         (['close . how]
          (when (fixnum? how)
            (let (bytes (make-u8vector 2))
              (##u8vector-set! bytes 0 (##fxand (##fxarithmetic-shift how -8) #xff))
              (##u8vector-set! bytes 1 (##fxand how #xff))
              (send port #x8 bytes))))
         (bogus
          (warning "unexpected message ~a" bogus)
          (lp))))
     (catch (e)
       (log-error "unhandled exception" e)
       (websocket-close ws 'abort)              ; notify receivers
       (with-catch void (cut close-port port))) ; unblock reader
     (finally
      (with-catch void (cut close-output-port port))))))
