;;; -*- Gerbil -*-
;;; (C) vyzo at hackzen.org
;;; json library

;;; JSON - scheme correspondence:
;;; JSON encoding: the following objects can be converted to json:
;;;  - booleans
;;;  - void (corresponding to js's null)
;;;  - real numbers
;;;  - strings
;;;  - proper lists
;;;  - vectors (encoded as lists)
;;;  - hashes with symbolic or string keys mapping to json encodable objects
;;;  - any object that defines a :json method producing a json encodable objects
;;; JSON decoding produces JSON-encodable objects with the following.
;;; Note that JSON null is decoded as #!void and JSON lists are decoded as
;;;  Scheme lists
(import :gerbil/gambit/ports
        :gerbil/gambit/bits
        :gerbil/gambit/exact
        :std/error
        :std/contract
        (only-in :std/srfi/1 reverse!))
(export read-json write-json
        string->json-object json-object->string
        json-symbolic-keys)
(declare (not safe))

(def/c (read-json (port (current-input-port)))
  (@contract (input-port? port))
  (read-json-object port #f))

(def/c (string->json-object str)
  (@contract (string? str))
  (read-json-object (open-input-string str) #f))

(def/c (write-json obj (port (current-output-port)))
  (@contract (output-port? port))
  (write-json-object obj port))

(def (json-object->string obj)
  (let (port (open-output-string))
    (write-json-object obj port)
    (get-output-string port)))

;; should decoded hashes have symbols as keys?
(def json-symbolic-keys
  (make-parameter #t))

;;; implementation
(def (raise-invalid-token port char)
  (if (eof-object? char)
    (raise-io-error 'read-json "Incomplete JSON object; EOF reached" port)
    (raise-io-error 'read-json "Invalid JSON token" port char)))

(def (read-json-object port (raise-eof? #t))
  (skip-whitespace port)
  (let (char (peek-char port))
    (if (eof-object? char)
      (if raise-eof?
        (raise-io-error 'read-json "EOF reached" port)
        #!eof)
      (case char
        ((#\{) (read-json-hash port))
        ((#\[) (read-json-list port))
        ((#\") (read-json-string port))
        ((#\t) (read-json-true port))
        ((#\f) (read-json-false port))
        ((#\n) (read-json-null port))
        ((#\- #\0 #\1 #\2 #\3 #\4 #\5 #\6 #\7 #\8 #\9)
         (read-json-number port))
        (else
         (raise-invalid-token port char))))))

(def (skip-whitespace port)
  (let (char (peek-char port))
    (unless (eof-object? char)
      (when (char-whitespace? char)
        (read-char port)
        (skip-whitespace port)))))

(def (skip-chars chars port)
  (let lp ((rest chars))
    (match rest
      ([char . rest]
       (let (next (read-char port))
         (if (eq? next char)
           (lp rest)
           (raise-invalid-token port next))))
      (else (void)))))

(def (read-json-hash port)
  (read-char port)
  (let (obj (if (json-symbolic-keys)
              (make-hash-table-eq)
              (make-hash-table)))
    (let lp ()
      (let (key (read-json-hash-key port))
        (if key
          ;; If you see a duplicate key, it's as likely an attack as a bug. #LangSec
          (if (hash-key? obj key)
            (error "Duplicate hash key in JSON input" key)
            (let (val (read-json-object port))
              (hash-put! obj key val)
              (skip-whitespace port)
              (let (char (peek-char port))
                (case char
                  ((#\,)
                   (read-char port)
                   (lp))
                  ((#\})
                   (read-char port)
                   obj)
                  (else
                   (raise-invalid-token port char))))))
          obj)))))                   ; empty or trailing #\, [liberal]

(def (read-json-hash-key port)
  (skip-whitespace port)
  (let (char (peek-char port))
    (case char
      ((#\")
       (let (key (read-json-string port))
         (skip-whitespace port)
         (let (char (peek-char port))
           (case char
             ((#\:)
              (read-char port)
              (if (json-symbolic-keys)
                (string->symbol key)
                key))
             (else
              (raise-invalid-token port char))))))
      ((#\})
       (read-char port)
       #f)
      (else
       (raise-invalid-token port char)))))

(def (read-json-list port)
  (read-char port)
  (let lp ((els []))
    (let (next (read-json-list-next port))
      (if next
        (lp (cons next els))
        (reverse! els)))))

(def (read-json-list-next port)
  (skip-whitespace port)
  (let (char (peek-char port))
    (case char
      ((#\])
       (read-char port)
       #f)
      (else
       (let (obj (read-json-object port))
         (skip-whitespace port)
         (let (char (peek-char port))
           (case char
             ((#\,)
              (read-char port)
              obj)
             ((#\])
              obj)
             (else
              (raise-invalid-token port char)))))))))

(def hexes "0123456789abcdef")
(def HEXES "0123456789ABCDEF")
(def hextab
  (let (ht (make-hash-table-eq))
    (def (put str)
      (let (len (string-length str))
        (let lp ((k 0))
          (when (##fx< k len)
            (hash-put! ht (##string-ref str k) k)
            (lp (##fx+ k 1))))))
    (put hexes)
    (put HEXES)
    ht))

(def (read-json-string port)
  (def (read-escape-char port)
    (let (char (read-char port))
      (case char
        ((#\" #\\ #\/) char)
        ((#\b) #\backspace)
        ((#\n) #\newline)
        ((#\f) #\page)
        ((#\r) #\return)
        ((#\t) #\tab)
        ((#\u) (read-escape-unicode port))
        (else
         (raise-invalid-token port char)))))

  (def (read-escape-unicode port)
    (let lp ((n 0) (chars []))
      (if (##fx< n 4)
        (lp (##fx+ n 1) (cons (read-char port) chars))
        (let lp ((rest chars) (val 0) (shift 0))
          (match rest
            ([char . rest]
             (let (n (##fxarithmetic-shift (hex-value char) shift))
               (lp rest (bitwise-ior n val) (##fx+ shift 4))))
            (else
             (if (and (##fx< val ##max-char)
                      (or (##fx< val #xd800)
                          (##fx< #xdfff val)))
               (##integer->char val)
               ;; invalid unicode point; use utf8 replacement instead of bombing
               #\xfffd)))))))

  (def (hex-value char)
    (cond
     ((hash-get hextab char) => values)
     (else
      (raise-invalid-token port char))))

  (read-char port)
  (let lp ((chars []))
    (let (char (read-char port))
      (case char
        ((#\")
         (list->string (reverse! chars)))
        ((#\\)
         (lp (cons (read-escape-char port) chars)))
        (else
         (if (eof-object? char)
           (raise-invalid-token port char)
           (lp (cons char chars))))))))

(def (read-json-number port)
  ;; descend parsing terminals: #\] #\} #\, whitespace
  ;; read until a terminal is encountered and let string->number
  ;; parse it liberally
  (def (parse chars)
    (let (str (list->string (reverse! chars)))
      (or (string->number str)
          (raise-invalid-token port str))))

  (let lp ((chars [(read-char port)]))
    (let (char (peek-char port))
      (if (or (eof-object? char)
              (memq char '(#\] #\} #\,))
              (char-whitespace? char))
        (parse chars)
        (lp (cons (read-char port) chars))))))

(def (read-json-true port)
  (skip-chars '(#\t #\r #\u #\e) port)
  #t)

(def (read-json-false port)
  (skip-chars '(#\f #\a #\l #\s #\e) port)
  #f)

(def (read-json-null port)
  (skip-chars '(#\n #\u #\l #\l) port)
  #!void)

(def (write-json-object obj port)
  (cond
   ((number? obj)
    (cond
     ((exact-integer? obj)
      (write-string (number->string obj) port))
     ((inexact? obj)
      (write-json-inexact obj port))
     ((rational? obj)
      (write-json-inexact (exact->inexact obj) port))
     (else
      (error "Bad JSON object" obj))))
   ((string? obj)
    (write-json-string obj port))
   ((symbol? obj)
    (write-json-string (symbol->string obj) port))
   ((keyword? obj)
    (write-json-string (keyword->string obj) port))
   ((list? obj)
    (write-json-list obj port))
   ((vector? obj)
    (write-json-vector obj port))
   ((hash-table? obj)
    (write-json-hash obj port))
   ((eq? #t obj)
    (write-string "true" port))
   ((eq? #f obj)
    (write-string "false" port))
   ((void? obj)
    (write-string "null" port))
   (else
    (write-json-object {:json obj} port))))

(def (write-json-inexact obj port)
  (let* ((mag (abs obj))
         (str (number->string mag)))
    (when (flnegative? obj)
      (write-char #\- port))
    (when (eq? (string-ref str 0) #\.)
      (write-char #\0 port))
    (write-string str port)
    (when (eq? (string-ref str (##fx- (string-length str) 1)) #\.)
      (write-char #\0 port))))

(def (write-json-list obj port)
  (write-char #\[ port)
  (let lp ((rest obj))
    (match rest
      ([val]                            ; last one
       (write-json-object val port)
       (write-char #\] port))
      ([val . rest]
       (write-json-object val port)
       (write-char #\, port)
       (lp rest))
      ([]                               ; empty
       (write-char #\] port)))))

(def (write-json-vector obj port)
  (let (len (vector-length obj))
    (if (##fxpositive? len)
      (let (last (##fx- len 1))
        (begin
          (write-char #\[ port)
          (let lp ((n 0))
            (if (##fx= n last)
              (begin
                (write-json-object (##vector-ref obj n) port)
                (write-char #\] port))
              (begin
                (write-json-object (##vector-ref obj n) port)
                (write-char #\, port)
                (lp (##fx+ n 1)))))))
      (write-string "[]" port))))

(def (write-json-hash obj port)
  (def (string-e key)
    (cond
     ((string? key) key)
     ((symbol? key)
      (symbol->string key))
     ((keyword? key)
      (keyword->string key))
     (else
      (error "Illegal hash key; must be symbol, keyword or string" obj key))))

  (write-char #\{ port)
  (let (lst (hash->list obj))
    (let lp ((rest lst))
      (match rest
        ([[key . val]]                  ; last one
         (write (string-e key) port)
         (write-char #\: port)
         (write-json-object val port)
         (write-char #\} port))
        ([[key . val] . rest]
         (write (string-e key) port)
         (write-char #\: port)
         (write-json-object val port)
         (write-char #\, port)
         (lp rest))
        ([]                             ; empty
         (write-char #\} port))))))

(def (write-json-string obj port)
  (def escape
    '((#\" . #\")
      (#\\ . #\\)
      (#\backspace . #\b)
      (#\newline . #\n)
      (#\page . #\f)
      (#\return . #\r)
      (#\tab . #\t)))

  (def (printable-char? char)
    (let (n (char->integer char))
      (cond
       ((##fx< n 32) #f)                ; unprintable ascii
       ((##fx= n 127) #f)               ; ascii DEL
       (else #t))))

  (def (write-uchar char port)
    (let (int (char->integer char))
      (write-string "\\u" port)
      (let lp ((n 0) (mask #xf000) (shift -12))
        (when (##fx< n 4)
          (let (char (string-ref hexes (arithmetic-shift (bitwise-and int mask) shift)))
            (write-char char port)
            (lp (##fx+ n 1) (arithmetic-shift mask -4) (##fx+ shift 4)))))))

  (def (write-str obj port)
    (let (len (string-length obj))
      (let lp ((n 0))
        (when (##fx< n len)
          (let (char (string-ref obj n))
            (cond
             ((assq char escape)
              => (lambda (esc)
                   (write-char #\\ port)
                   (write-char (cdr esc) port)))
             ((printable-char? char)
              (write-char char port))
             (else
              (write-uchar char port)))
            (lp (##fx+ n 1)))))))

  (write-char #\" port)
  (write-str obj port)
  (write-char #\" port))
