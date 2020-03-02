;;; -*- Gerbil -*-
;;; (C) vyzo at hackzen.org
;;; URI support; rfc3986

(import (only-in :gerbil/gambit/ports
                 with-output-to-string
                 with-output-to-u8vector write-u8)
        :std/text/utf8
        :std/contract)

(export uri-encode uri-decode form-url-encode form-url-decode
        make-uri-encoding-table
        uri-unreserved-chars uri-gendelim-chars uri-subdelim-chars)

;; rfc3986 unreserved chars: ALPHA / DIGIT / "-" / "." / "_" / "~"
(def uri-unreserved-chars
  "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
(def uri-gendelim-chars
  ":/?#[]@")
(def uri-subdelim-chars
  "!$&'()*+,;=")

(def (make-uri-encoding-table self-chars (sub-chars []))
  (let ((vt (make-vector 256 #f))
        (len (string-length self-chars)))
    (let lp ((n 0))
      (when (##fx< n len)
        (let (char (##string-ref self-chars n))
          (vector-set! vt (char->integer char) char)
          (lp (##fx+ n 1)))))
    (for-each (match <>
                ([char . sub] (vector-set! vt (char->integer char) sub)))
              sub-chars)
    vt))

(def uri-encoding
  (make-uri-encoding-table uri-unreserved-chars))

;; uri-encoding with space as #\+
(def uri-space-encoding
  (make-uri-encoding-table uri-unreserved-chars '((#\space . #\+))))

;; uri-encode: string => string
(def/c (uri-encode str (vt uri-encoding))
  (@contract (and(vector? vt) (fx= (vector-length vt) 256)))
  (with-output-to-string []
    (lambda ()
      (write-uri-encoded str vt))))

;; form-url-encode: [[string . string/#f] ...] => string
;; if +space is t, #\space is encoded as #\+ (otherwise %20)
(def (form-url-encode fields (+space? #t))
  (def encoding
    (if +space? uri-space-encoding uri-encoding))

  (def (encode-field field)
    (match field
      ([key . val]
       (write-uri-encoded key encoding)
       (when val
         (write-char #\=)
         (write-uri-encoded val encoding)))))

  (match fields
    ([first . rest]
     (with-output-to-string []
       (lambda ()
         (encode-field first)
         (for-each (lambda (field) (write-char #\&) (encode-field field))
                   rest))))
    ([] "")))

(def (write-uri-encoded str encoding)
  (def (write-hex n)
    (write-char (##string-ref "0123456789ABCDEF" n)))

  (let* ((utf8 (string->utf8 str))
         (len  (u8vector-length utf8)))
    (let lp ((n 0))
      (when (##fx< n len)
        (let (byte (##u8vector-ref utf8 n))
          (cond
           ((##vector-ref encoding byte) => write-char)
           (else
            (write-char #\%)
            (write-hex (##fxand (##fxarithmetic-shift byte -4) #xf))
            (write-hex (##fxand byte #xf))))
          (lp (##fx+ n 1)))))))

;; uri-decode: string => string
(def hex-bytes
  (let (ht (make-hash-table-eq))
    (for-each
      (lambda (n)
        (let (char (##string-ref "0123456789ABCDEF" n))
          (hash-put! ht char n)
          (hash-put! ht (char-downcase char) n)))
      (iota 16))
    ht))

(def/c (uri-decode str (encoding #f))
  (@contract (or (not encoding) (and (vector? encoding) (fx= (vector-length encoding) 256))))

  (def (hex-byte byte)
    (let (char (integer->char byte))
      (cond
       ((hash-get hex-bytes char) => values)
       (else
        (error "Malformed uri encoding" char)))))

  (let* ((utf8 (string->utf8 str))
         (len  (u8vector-length utf8))
         (pct  (char->integer #\%)))
    (utf8->string
     (with-output-to-u8vector []
       (lambda ()
         (let lp ((n 0))
           (when (##fx< n len)
             (let (next (##u8vector-ref utf8 n))
               (cond
                ((and encoding (##vector-ref encoding next))
                 => (lambda (char)
                      (write-char char)
                      (lp (##fx+ n 1))))
                ((eq? next pct)
                 (let (n (##fx+ n 1))
                   (if (##fx< (##fx+ n 1) len)
                     (let ((hi (##u8vector-ref utf8 n))
                           (lo (##u8vector-ref utf8 (##fx+ n 1))))
                       (write-u8 (##fxior (##fxarithmetic-shift (hex-byte hi) 4)
                                          (hex-byte lo)))
                       (lp (##fx+ n 2)))
                     (error "Malformed uri component"))))
                (else
                 (write-u8 next)
                 (lp (##fx+ n 1))))))))))))

(def uri-space-decoding
  (make-uri-encoding-table "" '((#\+ . #\space))))

;; form-url-decode: string => [[string . string] ...]
(def (form-url-decode str)
  (filter-map
   (lambda (part)
     (and (not (string-empty? part))
          (match (string-split part #\=)
            ([key val]
             (cons (uri-decode key uri-space-decoding)
                   (uri-decode val uri-space-decoding)))
            ([key]
             (cons (uri-decode key uri-space-decoding) #f))
            (else
             (error "Malformed form component" part)))))
   (string-split str #\&)))
