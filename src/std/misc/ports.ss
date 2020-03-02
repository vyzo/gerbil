;;; -*- Gerbil -*-
;;; (C) vyzo at hackzen.org
;;; miscellaneous port utilities

(import :gerbil/gambit/ports
        :std/sugar
        :std/contract)
(export copy-port
        read-all-as-string
        read-file-string
        read-all-as-lines
        read-file-lines
        read-all-as-u8vector
        read-file-u8vector)

;; _gambit#.scm
(extern namespace: #f
  macro-type-port
  macro-byte-port?
  macro-character-port?
  macro-port-mutex-lock!
  macro-port-mutex-unlock!
  macro-character-port-rlo
  macro-character-port-rlo-set!
  macro-character-port-rhi
  macro-character-port-rbuf
  macro-character-port-rbuf-fill
  macro-character-port-peek-eof?
  macro-character-port-peek-eof?-set!
  macro-byte-port-rlo
  macro-byte-port-rlo-set!
  macro-byte-port-rhi
  macro-byte-port-rbuf
  macro-byte-port-rbuf-fill
  )

(bind-method! (macro-type-port) 'destroy close-port)

;; Copy all data from port in to port out
(def/c (copy-port in out)
  (@contract (input-port? in)
             (output-port? out))
  (cond
   ((macro-byte-port? in)
    (cond
     ((macro-byte-port? out)
      (try-copy-byte-port in out))
     ((macro-character-port? out)
      (copy-character-port in out))
     (else
      (copy-object-port in out))))
   ((macro-character-port? in)
    (if (macro-character-port? out)
      (copy-character-port in out)
      (copy-object-port in out)))
   (else
    (copy-object-port in out))))

(def (try-copy-byte-port in out)
  (macro-port-mutex-lock! in)
  (if (or (##fx< (macro-character-port-rlo in)
                 (macro-character-port-rhi in))  ; has unread characters
          (macro-character-port-peek-eof? in))   ; eof is coming
    (copy-character-port/lock in out)
    (copy-byte-port/lock in out)))

(def (copy-character-port in out)
  (macro-port-mutex-lock! in)
  (copy-character-port/lock in out))

(def (copy-byte-port/lock in out)
  (def (loop)
    (let ((rlo (macro-byte-port-rlo in))
          (rhi (macro-byte-port-rhi in)))
      (if (##fx< rlo rhi)
        (let (rbuf (macro-byte-port-rbuf in))
          (try
           (when (eq? in out)
             (macro-port-mutex-unlock! in))
           (write-subu8vector rbuf rlo rhi out)
           (when (eq? in out)
             (macro-port-mutex-lock! in))
           (catch (e)
             (unless (eq? in out)
               (macro-port-mutex-unlock! in))
             (raise e)))
          (macro-byte-port-rlo-set! in rhi)
          (rbuf-fill))
        (rbuf-fill))))

  (def (rbuf-fill)
    (let* ((rbuf (macro-byte-port-rbuf in))
           (res ((macro-byte-port-rbuf-fill in) in
                 (##u8vector-length rbuf) #t)))
      (cond
       ((eq? res ##err-code-EAGAIN)     ; timeout -> eof, we are done
        (macro-port-mutex-unlock! in))
       ((fixnum? res)                   ; error
        (macro-port-mutex-unlock! in)
        (##raise-os-io-exception in #f res copy-port in out))
       (res                             ; bytes were added
        (loop))
       (else                            ; no bytes were added, eof
        (macro-port-mutex-unlock! in)))))

  (loop))

(def (copy-character-port/lock in out)
  (def (loop)
    (let ((rlo (macro-character-port-rlo in))
          (rhi (macro-character-port-rhi in)))
      (cond
       ((##fx< rlo rhi)
        (let (rbuf (macro-character-port-rbuf in))
          (try
           (when (eq? in out)
             (macro-port-mutex-unlock! in))
           (write-substring rbuf rlo rhi out)
           (when (eq? in out)
             (macro-port-mutex-lock! in))
           (catch (e)
             (unless (eq? in out)
               (macro-port-mutex-unlock! in))
             (raise e)))
          (macro-character-port-rlo-set! in rhi)
          (rbuf-fill)))
       ((macro-character-port-peek-eof? in)
        (macro-character-port-peek-eof?-set! in #f)
        (macro-port-mutex-unlock! in))
       (else
        (rbuf-fill)))))

  (def (rbuf-fill)
    (let* ((rbuf (macro-character-port-rbuf in))
           (res ((macro-character-port-rbuf-fill in) in
                 (##string-length rbuf) #t)))
      (cond
       ((eq? res ##err-code-EAGAIN)     ; timeout -> eof
        (macro-port-mutex-unlock! in))
       ((fixnum? res)
        (macro-port-mutex-unlock! in)
        (##raise-os-io-exception in #f res copy-port in out))
       (res                             ; some chars were added
        (loop))
       (else                            ; no chars were added, eof
        (macro-port-mutex-unlock! in)))))

  (loop))

(def (copy-object-port in out)
  (let lp ((next (read in)))
    (unless (eof-object? next)
      (write next out)
      (lp (read in)))))

;; Read all the contents of a port as a string
(def (read-all-as-string port)
  (let ((string (read-line port #f)))
    (if (string? string) string ""))) ;; if it's an eof-object? or whatelse, return ""

;; Read the contents of a file into a string
(def (read-file-string file settings: (settings '()))
  (call-with-input-file (cons* path: file settings) read-all-as-string))

;; Read all the contents of a port as a list of strings, one per line
(def (read-all-as-lines
      port
      separator: (separator #\newline)
      include-separator?: (include-separator? #f))
  (let loop ((lines '()))
    (let ((line (read-line port separator include-separator?)))
      (if (string? line)
        (loop (cons line lines))
        (reverse lines)))))

;; Read the contents of a file into a list of lines
(def (read-file-lines file settings: (settings '()))
  (call-with-input-file (cons* path: file settings) read-all-as-lines))

(def (read-all-as-u8vector port (bufsize 8192))
  (let lp ((buf (make-u8vector bufsize))
           (u8s []))
    (let (len (read-subu8vector buf 0 bufsize port))
      (if (= len bufsize)
        (lp (make-u8vector bufsize) (cons buf u8s))
        (begin
          (u8vector-shrink! buf len)
          (append-u8vectors (reverse (cons buf u8s))))))))

(def (read-file-u8vector file settings: (settings '()) bufsize: (bufsize 8192))
  (call-with-input-file (cons* path: file settings)
    (cut read-all-as-u8vector <> bufsize)))
