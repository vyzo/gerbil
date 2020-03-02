;;; -*- Gerbil -*-
;;; (C) vyzo
;;; embedded HTTP/1.1 server; request handler

(import :gerbil/gambit/os
        :std/foreign
        :std/net/socket
        :std/net/socket/buffer
        :std/net/bio
        :std/text/utf8
        :std/logger
        :std/sugar
        :std/error
        :std/contract
        :std/pregexp
        (only-in :std/srfi/1 reverse!))
(export http-request-handler
        http-request?
        http-request-method http-request-url http-request-path http-request-params
        http-request-proto http-request-client http-request-headers
        http-request-body
        http-request-timeout-set!
        http-response?
        http-response-write
        http-response-begin http-response-chunk http-response-end
        http-response-force-output
        http-response-timeout-set!
        set-httpd-request-timeout!
        set-httpd-response-timeout!
        set-httpd-max-request-headers!
        set-httpd-max-token-length!
        set-httpd-max-request-body-length!
        set-httpd-input-buffer-size!
        set-httpd-output-buffer-size!)

(declare (not safe))

(defstruct http-request (buf client method url path params proto headers data)
  final: #t unchecked: #t)
(defstruct http-response (buf output close?)
  final: #t unchecked: #t)

(def (http-request-handler get-handler sock addr)
  (def ibuf (get-input-buffer sock))
  (def obuf (get-output-buffer sock))

  (def (loop)
    (let ((req (make-http-request ibuf addr #f #f #f #f #f #f #!void))
          (res (make-http-response obuf #f #f)))

      (set! (ssocket-input-buffer-timeout ibuf)
        request-timeout)
      (set! (ssocket-output-buffer-timeout obuf)
        response-timeout)

      (try
       (read-request! req)
       (catch (timeout-error? e)
         (log-error "request error" e)
         (set! (&http-response-close? res) #t)
         (http-response-write res 408 [] #f)
         (raise 'abort))
       (catch (io-error? e)
         (log-error "request error" e)
         (set! (&http-response-close? res) #t)
         (http-response-write res 400 [] #f)
         (raise 'abort)))

      (let* ((method  (&http-request-method req))
             (path    (&http-request-path req))
             (proto   (&http-request-proto req))
             (headers (&http-request-headers req))
             (host    (header-e "Host" headers))
             (close?
              (case proto
                (("HTTP/1.1")
                 (equal? (header-e "Connection" headers) "close"))
                (("HTTP/1.0")
                 (not (equal? (header-e "Connection" headers) "Keep-Alive")))
                (else #t))))

        (when close?
          (set! (&http-response-close? res) #t))

        (cond
         ((not (member proto '("HTTP/1.1" "HTTP/1.0")))
          (http-response-write res 505 [] #f))
         ((not (symbol? method))
          (http-response-write res 501 [] #f))
         ((and (eq? method 'OPTIONS) (equal? path "*"))
          (http-response-write res 200 [] #f))
         ((eq? method 'TRACE)
          (http-response-trace res req))
         ((get-handler host path)
          => (lambda (handler)
               (if (procedure? handler)
                 (try
                  (handler req res)
                  (catch (io-error? e)
                    (log-error "request i/o error" e)
                    (unless (&http-response-output res)
                      (set! (&http-response-close? res) #t)
                      (http-response-write res 500 [] #f))
                    (raise 'abort))
                  (catch (e)
                    (log-error "request handler error" e)
                    (if (&http-response-output res)
                      ;; if there was output from the handler, the connection
                      ;; is unusable; abort
                      (raise 'abort)
                      (http-response-write res 500 [] #f))))
                 (begin
                   (warning "request handler is not a procedure: ~a ~a ~a" host path handler)
                   (http-response-write res 500 [] #f)))))
         (else
          (http-response-write res 404 [] #f)))

        (unless close?
          (http-request-skip-body req)
          (loop)))))

  (try
   (loop)
   (catch (e)
     (unless (memq e '(abort eof))
       (log-error "unhandled exception" e)
       (raise e))
     e)
   (finally
    (ssocket-close sock)
    (put-input-buffer! ibuf)
    (put-output-buffer! obuf))))

;;; handler interface
;; request
(def (http-request-body req)
  (with ((http-request ibuf _ method _ _ _ _ headers data) req)
    (if (void? data)
      (case method
        ((POST PUT)
         (let (data (read-request-body ibuf headers))
           (set! (&http-request-data req)
             data)
           data))
        (else
         (http-request-skip-body req)
         #f))
      data)))

(def (http-request-timeout-set! req timeo)
  (with ((http-request ibuf) req)
    (set! (ssocket-input-buffer-timeout ibuf)
      timeo)))

;; response
;; write a full response
(def (http-response-write res status headers body)
  (with ((http-response obuf output close?) res)
    (when output
      (error "duplicate response" res))
    (set! (&http-response-output res) 'END)
    (let* ((len
            (cond
             ((u8vector? body)
              (u8vector-length body))
             ((string? body)
              (string-utf8-length body))
             ((not body)
              0)
             (else
              (error "Bad response body; expected string, u8vector, or #f" body))))
           (headers
            (cons (cons "Content-Length" (number->string len)) headers))
           (headers
            (if close?
              (cons '("Connection" . "close") headers)
              headers))
           (headers
            (cons (cons "Date" (http-date)) headers)))
      (write-response-line obuf status)
      (write-response-headers obuf headers)
      (write-crlf obuf)
      (cond
       ((u8vector? body)
        (bio-write-bytes body obuf))
       ((string? body)
        (bio-write-string body obuf)))
      (bio-force-output obuf))))

;; begin a chunked response
(def (http-response-begin res status headers)
  (with ((http-response obuf output close?) res)
    (when output
      (error "duplicate response" res))
    (set! (&http-response-output res) 'CHUNK)
    (let* ((headers (cons '("Transfer-Encoding" . "chunked") headers))
           (headers (if close?
                      (cons '("Connection" . "close") headers)
                      headers))
           (headers
            (cons (cons "Date" (http-date)) headers)))
      (write-response-line obuf status)
      (write-response-headers obuf headers)
      (write-crlf obuf))))

;; write the next chunk in the response
(def (http-response-chunk res chunk (start 0) (end #f))
  (with ((http-response obuf output) res)
    (unless (eq? output 'CHUNK)
      (error "illegal response; not writing chunks" res output))
    (write-chunk obuf chunk start end)))

;; end chunked response
(def (http-response-end res)
  (with ((http-response obuf output) res)
    (unless (eq? output 'CHUNK)
      (error "illegal response; not writing chunks" res output))
    (set! (&http-response-output res) 'END)
    (write-last-chunk obuf)
    (bio-force-output obuf)))

;; force output of current chunks
(def (http-response-force-output res)
  (bio-force-output (http-response-buf res)))

(def (http-response-timeout-set! res timeo)
  (with ((http-response obuf) res)
    (set! (ssocket-output-buffer-timeout obuf)
      timeo)))

;;; server internal
(def (header-e key lst)
  (let lp ((rest lst))
    (match rest
      ([hd . rest]
       (if (##string-equal? key (car hd))
         (cdr hd)
         (lp rest)))
      (else #f))))

(def (http-request-skip-body req)
  (when (void? (&http-request-data req))
    (set! (&http-request-data req) #f)
    (skip-request-body (&http-request-buf req) (&http-request-headers req))))

(def (http-response-trace res req)
  (with ((http-request _ _ method url _ _ proto headers) req)
    (let (xbuf (open-chunked-output-buffer))
      (bio-write-string (symbol->string method) xbuf)
      (bio-write-u8 SPC xbuf)
      (bio-write-string url xbuf)
      (bio-write-u8 SPC xbuf)
      (bio-write-string proto xbuf)
      (write-crlf xbuf)
      (write-response-headers xbuf headers)
      (write-crlf xbuf)
      (let (chunks (chunked-output-chunks xbuf))
        (http-response-begin res 200 '(("Content-Type". "message/http")))
        (for-each (cut http-response-chunk res <>) chunks)
        (http-response-end res)))))


(begin-ffi (http-date)
  (c-declare #<<END-C
#include <time.h>
#include <string.h>
__thread char buf[64];
static char *ffi_httpd_date () {
 struct tm tm;
 time_t t = time(NULL);
 asctime_r (gmtime_r (&t, &tm), buf);
 // clobber newline
 buf[strlen(buf)-1] = 0;
 return buf;
}
END-C
)
  (define-c-lambda http-date () char-string
    "ffi_httpd_date"))

;;; i/o helpers
;; limits
(def request-timeout 60)
(def response-timeout 120)
(def max-request-headers 256)
(def max-token-length 1024)
(def max-request-body-length (expt 2 20)) ; 1MB
(def input-buffer-size 4096)
(def output-buffer-size 4096)

(defrules defsetter ()
  ((_ (setf id) pred)
   (def/c (setf val)
     (@contract (? pred val))
     (set! id val))))

(defsetter (set-httpd-request-timeout! request-timeout)
  (or not real? time?))
(defsetter (set-httpd-response-timeout! response-timeout)
  (or not real? time?))
(defsetter (set-httpd-max-request-headers! max-request-headers)
  (and fixnum? fxpositive?))
(defsetter (set-httpd-max-token-length! max-token-length)
  (and fixnum? fxpositive?))
(defsetter (set-httpd-max-request-body-length! max-request-body-length)
  (and fixnum? fxpositive?))
(defsetter (set-httpd-input-buffer-size! input-buffer-size)
  (and fixnum? fxpositive?))
(defsetter (set-httpd-output-buffer-size! output-buffer-size)
  (and fixnum? fxpositive?))

(def (read-request! req)
  (let* ((ibuf (&http-request-buf req))
         ((values method url proto)
          (read-request-line ibuf))
         ((values path params)
          (split-request-url url))
         (headers (read-request-headers ibuf)))
    (set! (&http-request-method req)
      method)
    (set! (&http-request-url req)
      url)
    (set! (&http-request-path req)
      path)
    (set! (&http-request-params req)
      params)
    (set! (&http-request-proto req)
      proto)
    (set! (&http-request-headers req)
      headers)))

(def split-request-url-rx
  (pregexp "^[^/]+://[^/]*(/.*)$"))

(def (split-request-url url)
  (cond
   ((string-index url #\:)              ; absolute uri
    => (lambda (ix)
         (match (pregexp-match split-request-url-rx url)
           ([_ base]
            (split-request-url base))
           (else
            (raise-io-error 'http-read-request "invalid url" url)))))
   ((string-index url #\?)             ; parameters
    => (lambda (ix)
         (values (substring url 0 ix) (substring url (fx1+ ix) (string-length url)))))
   (else
    (values url #f))))

(def (read-request-line ibuf)
  (let* ((_ (read-skip* ibuf CR LF))
         (method (read-token ibuf SPC))
         (url (read-token ibuf SPC))
         (proto (read-token ibuf CR))
         (_ (read-skip ibuf LF))
         (method
          (or (hash-get +http-request-methods+ method)
              method)))
    (values method url proto)))

(def (read-request-headers ibuf)
  (let lp ((headers []) (count 0))
    (let (next (bio-peek-u8 ibuf))
      (cond
       ((eof-object? next)
        (raise 'eof))
       ((eq? next CR)
        (read-skip ibuf CR LF)
        (reverse! headers))
       ((fx< count max-request-headers)
        (let (hdr (read-header ibuf))
          (lp (cons hdr headers) (fx1+ count))))
       (else
        (raise-io-error 'http-read-request "too many headers" count))))))

(def (read-header ibuf)
  (let* ((key (read-token ibuf COL))
         (_ (header-titlecase! key))
         (_ (read-skip* ibuf SPC))
         (val (read-token ibuf CR))
         (_ (read-skip ibuf LF)))
    (cons key val)))

(def (header-titlecase! str)
  (let (len (string-length str))
    (let lp ((i 0) (upcase? #t))
      (if (fx< i len)
        (let* ((char (string-ref str i))
               (int (char->integer char)))
          (cond
           ((fx<= 97 int 122)           ; a-z
            (when upcase?
              (let (char (integer->char (fx- int 32)))
                (string-set! str i char)))
            (lp (fx1+ i) #f))
           ((fx<= 65 int 90)            ; A-Z
            (unless upcase?
              (let (char (integer->char (fx+ int 32)))
                (string-set! str i char)))
            (lp (fx1+ i) #f))
           (else
            (lp (fx1+ i) #t))))
        str))))

(def (read-token ibuf sep)
  (def tbuf (get-token-buffer))
  (let lp ((count 0))
    (let (next (bio-read-u8 ibuf))
      (cond
       ((eof-object? next)
        (put-token-buffer! tbuf)
        (raise 'eof))
       ((eq? next sep)
        (let (token (##substring tbuf 0 count))
          (put-token-buffer! tbuf)
          token))
       ((fx< count max-token-length)
        (let (char (integer->char next))
          (string-set! tbuf count char)
          (lp (fx1+ count))))
       (else
        (put-token-buffer! tbuf)
        (raise-io-error 'http-read-request "Maximum token length exceeded" count))))))

(def* read-skip
  ((ibuf c)
   (let (next (bio-read-u8 ibuf))
    (unless (eq? c next)
      (raise-io-error 'http-read-request "Unexpected character" next))))
  ((ibuf c1 c2)
   (read-skip ibuf c1)
   (read-skip ibuf c2)))

(def* read-skip*
  ((ibuf c)
   (let lp ()
     (let (next (bio-peek-u8 ibuf))
       (when (eq? next c)
         (bio-read-u8 ibuf)
         (lp)))))
  ((ibuf c1 c2)
   (let lp ()
     (let (next (bio-peek-u8 ibuf))
       (when (eq? next c1)
         (bio-read-u8 ibuf)
         (read-skip ibuf c2)
         (lp))))))

(def (read-request-body ibuf headers)
  (def (read-simple-body)
    (cond
     ((header-e "Content-Length" headers)
      => (lambda (len)
           (let* ((len (string->number len))
                  (_ (unless (fx<= len max-request-body-length)
                       (raise-io-error 'http-request-body "Maximum body length exceeded" len)))
                  (bytes (make-u8vector len)))
             (bio-read-bytes bytes ibuf)
             bytes)))
     (else #f)))

  (cond
   ((header-e "Transfer-Encoding" headers)
    => (lambda (tenc)
         (if (not (equal? "identity" tenc))
           (read-request-chunks ibuf)
           (read-simple-body))))
   (else
    (read-simple-body))))

(def (read-request-chunks ibuf)
  (let lp ((chunks []) (count 0))
    (let* ((next (read-token ibuf CR))
           (_ (read-skip ibuf LF))
           (len (string->number next 16)))
      (if (fx> len 0)
        (let (count (fx+ count len))
          (if (fx<= count max-request-body-length)
            (let (chunk (make-u8vector len))
              (bio-read-bytes chunk ibuf)
              (read-skip ibuf CR LF)
              (lp (cons chunk chunks) count))
            (raise-io-error 'http-request-body "Maximum body length exceeded" count len)))
        (append-u8vectors (reverse! chunks))))))

(def (skip-request-body ibuf headers)
  (def (skip-simple-body)
    (alet (clen (header-e "Content-Length" headers))
      (let (len (string->number clen))
        (if (fixnum? len)
          (bio-input-skip len ibuf)
          (raise-io-error 'http-request-skip-body "Illegal body length" clen)))))

  (cond
   ((header-e "Transfer-Encoding" headers)
    => (lambda (tenc)
         (if (not (equal? "identity" tenc))
           (skip-request-chunks ibuf)
           (skip-simple-body))))
   (else
    (skip-simple-body))))

(def (skip-request-chunks ibuf)
  (let* ((next (read-token ibuf CR))
         (_ (read-skip ibuf LF))
         (len (string->number next 16)))
    (when (fx> len 0)
      (bio-input-skip len ibuf)
      (read-skip ibuf CR LF)
      (skip-request-chunks ibuf))))

(def (write-response-line obuf status)
  (let (text
        (cond
         ((hash-get +http-response-codes+ status)
          => values)
         (else "Gremlins!")))
    (bio-write-string "HTTP/1.1" obuf)
    (bio-write-u8 SPC obuf)
    (bio-write-string (number->string status) obuf)
    (bio-write-u8 SPC obuf)
    (bio-write-string text obuf)
    (write-crlf obuf)))

(def (write-response-headers obuf headers)
  (def (write-header hdr)
    (with ([key . val] hdr)
      (if (string? key)
        (if (string? val)
          (begin
            (bio-write-string key obuf)
            (bio-write-u8 COL obuf)
            (bio-write-u8 SPC obuf)
            (bio-write-string val obuf)
            (write-crlf obuf))
          (error "Bad header value; expected string" hdr val))
        (error "Bad header key; expected string" hdr key))))
  (for-each write-header headers))

(def (write-crlf obuf)
  (bio-write-u8 CR obuf)
  (bio-write-u8 LF obuf))

(def (write-chunk obuf chunk start end)
  (let* ((end
          (cond
           (end end)
           ((u8vector? chunk)
            (u8vector-length chunk))
           ((string? chunk)
            (string-length chunk))
           ((not chunk) 0)
           (else
            (error "Bad chunk; expected u8vector or string" chunk))))
         (len
          (cond
           ((u8vector? chunk)
            (fx- end start))
           ((string? chunk)
            (string-utf8-length chunk start end))
           (else
            0))))
    (when (fx> len 0)
      (bio-write-string (number->string len 16) obuf)
      (write-crlf obuf)
      (cond
       ((u8vector? chunk)
        (bio-write-subu8vector chunk start end obuf))
       ((string? chunk)
        (bio-write-substring chunk start end obuf)))
      (write-crlf obuf))))

(def (write-last-chunk obuf)
  (bio-write-u8 C0 obuf)
  (write-crlf obuf)
  (write-crlf obuf))

(def C0 (char->integer #\0))
(def CR (char->integer #\return))
(def LF (char->integer #\linefeed))
(def COL (char->integer #\:))
(def SPC (char->integer #\space))
(def QMARK (char->integer #\?))

(def +http-request-methods+
  (hash ("GET"     'GET)
        ("HEAD"    'HEAD)
        ("POST"    'POST)
        ("PUT"     'PUT)
        ("DELETE"  'DELETE)
        ("TRACE"   'TRACE)
        ("OPTIONS" 'OPTIONS)))

(def +http-response-codes+
  (hash-eq (100 "Continue")
           (101 "Switching Protocols")
           (200 "OK")
           (201 "Created")
           (202 "Accepted")
           (203 "Non-Authoritative Information")
           (204 "No Content")
           (205 "Reset Content")
           (206 "Partial Content")
           (300 "Multiple Choices")
           (301 "Moved Permanently")
           (302 "Found")
           (303 "See Other")
           (304 "Not Modified")
           (305 "Use Proxy")
           (307 "Temporary Redirect")
           (400 "Bad Request")
           (401 "Unauthorized")
           (402 "Payment Required")
           (403 "Forbidden")
           (404 "Not Found")
           (405 "Method Not Allowed")
           (406 "Not Acceptable")
           (407 "Proxy Authentication Required")
           (408 "Request Timeout")
           (409 "Conflict")
           (410 "Gone")
           (411 "Length Required")
           (412 "Precondition Failed")
           (413 "Request Entity Too Large")
           (414 "Request-URI Too Long")
           (415 "Unsupported Media Type")
           (416 "Requested Range Not Satisfiable")
           (417 "Expectation Failed")
           (500 "Internal Server Error")
           (501 "Not Implemented")
           (502 "Bad Gateway")
           (503 "Service Unavailable")
           (504 "Gateway Timeout")
           (505 "HTTP Version Not Supported")))

;;; buffer management
(cond-expand
  (gerbil-smp
   (import :gerbil/gambit/threads)
   (def +input-buffers+ [])
   (def +input-buffers-mx+
     (make-mutex 'httpd-input-buffer))

   (def +output-buffers+ [])
   (def +output-buffers-mx+
     (make-mutex 'httpd-output-buffer))

   (def +token-buffers+ [])
   (def +token-buffers-mx+
     (make-mutex 'httpd-token-buffer))

   (defrules defgetbuf ()
     ((_ (id . args) buffers mx reset! alloc)
      (def (id . args)
        (declare (not interrupts-enabled))
        (mutex-lock! mx)
        (match buffers
          ([buf . rest]
           (set! buffers rest)
           (mutex-unlock! mx)
           (reset! buf . args)
           buf)
          (else
           (mutex-unlock! mx)
           alloc)))))

   (defrules defputbuf ()
     ((_ id buffers mx release!)
      (def (id buf)
        (declare (not interrupts-enabled))
        (release! buf)
        (mutex-lock! mx)
        (set! buffers (cons buf buffers))
        (mutex-unlock! mx))))

   (defgetbuf (get-input-buffer sock) +input-buffers+ +input-buffers-mx+
     ssocket-input-buffer-reset! (open-ssocket-input-buffer sock input-buffer-size))
   (defputbuf put-input-buffer! +input-buffers+ +input-buffers-mx+
     ssocket-input-buffer-release!)

   (defgetbuf (get-output-buffer sock) +output-buffers+ +output-buffers-mx+
     ssocket-output-buffer-reset! (open-ssocket-output-buffer sock output-buffer-size))
   (defputbuf put-output-buffer! +output-buffers+ +output-buffers-mx+
     ssocket-output-buffer-release!)

   (defgetbuf (get-token-buffer) +token-buffers+ +token-buffers-mx+
     void (make-string max-token-length))
   (defputbuf put-token-buffer! +token-buffers+ +token-buffers-mx+
     void))

  (else
   (def +input-buffers+ [])
   (def +output-buffers+ [])
   (def +token-buffers+ [])

   (def (get-input-buffer sock)
     (declare (not interrupts-enabled))
     (match +input-buffers+
       ([buf . rest]
        (set! +input-buffers+ rest)
        (ssocket-input-buffer-reset! buf sock)
        buf)
       (else
        (open-ssocket-input-buffer sock input-buffer-size))))

   (def (put-input-buffer! buf)
     (declare (not interrupts-enabled))
     (ssocket-input-buffer-release! buf)
     (set! +input-buffers+ (cons buf +input-buffers+)))

   (def (get-output-buffer sock)
     (declare (not interrupts-enabled))
     (match +output-buffers+
       ([buf . rest]
        (set! +output-buffers+ rest)
        (ssocket-output-buffer-reset! buf sock)
        buf)
       (else
        (open-ssocket-output-buffer sock output-buffer-size))))

   (def (put-output-buffer! buf)
     (declare (not interrupts-enabled))
     (ssocket-output-buffer-release! buf)
     (set! +output-buffers+ (cons buf +output-buffers+)))

   (def (get-token-buffer)
     (declare (not interrupts-enabled))
     (match +token-buffers+
       ([buf . rest]
        (set! +token-buffers+ rest)
        buf)
       (else
        (make-string max-token-length))))

   (def (put-token-buffer! buf)
     (declare (not interrupts-enabled))
     (set! +token-buffers+ (cons buf +token-buffers+)))
  ))
