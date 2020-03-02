;;; -*- Gerbil -*-
;;; (C) vyzo at hackzen.org
;;; format and friends

(export format printf fprintf eprintf)
(import
  :std/contract
  (only-in :gerbil/gambit/ports
           open-output-string
           get-output-string
           with-output-to-string
           force-output)
  (only-in :gerbil/gambit/misc
           pretty-print)
  (only-in :gerbil/gambit/bits
           integer-length)
  (only-in :std/misc/repr
           print-representation))

(def/c (format fmt . args)
  (@contract (string? fmt))
  (let (out (open-output-string))
    (dofmt out fmt args)
    (get-output-string out)))

(def (printf fmt . args)
  (apply fprintf (current-output-port) fmt args))

(def/c (fprintf port fmt . args)
  (@contract (output-port? port)
             (string? fmt))
  (dofmt port fmt args))

(def (eprintf fmt . args)
  (apply fprintf (current-error-port) fmt args)
  (force-output (current-error-port)))

;;; implementation
;; mostly srfi-48-style format strings, except the brain damage.
;; departures:
;;   lower-case synonyms for all format specifiers
;;   ~u/~U for unicode hex char print (for #\uXXXX)
;;   ~f/~F means "float" and does non-exp fp (C-style %f more or less)
;;   ~r/~R means "repr" and works with `:std/misc/repr` and the `:pr` method
;;   ~w{spec} does generic fixed width
;; not implemented: ~& ~H wtfs
;; TODO: ~g/~e for C-style %g/%e

;; format dispatch loop
(def (dofmt port fmt args)
  (def len (##string-length fmt))

  (parameterize ((current-output-port port)
                 (current-format-string fmt)
                 (current-format-args args))
    (let K ((xi 0) (rest args))
      (if (##fx< xi len)
        (let ((next (##string-ref fmt xi))
              (xi (##fx+ xi 1)))
          (if (eq? next #\~)
            (if (##fx< xi len)
              (let ((next (##string-ref fmt xi))
                    (xi (##fx+ xi 1)))
                (cond
                 ((hash-get dispatch-table next)
                  => (cut <> next K xi rest))
                 (else
                  (error "Unknown format specifier" fmt next))))
              (error "Bad format string" fmt))
            (begin
              (write-char next)
              (K xi rest))))
        (unless (null? rest)
          (error "Too many arguments for format string" fmt args))))))

;; format parameters
(def current-format-string
  (make-parameter #f))
(def current-format-args
  (make-parameter #f))

;; format methods
(def dispatch-table
  (make-hash-table-eq))

(defrules with-args ()
  ((_ rest (arg . rest-args) body ...)
   (match rest
     ([arg . rest-args]
      body ...)
     (else
      (error "Missing format argument"
        (current-format-string) (current-format-args))))))

(defrules defdispatch ()
  ((_ (char ...) proc)
   (begin (hash-put! dispatch-table char proc) ...)))

(defrules defdispatch-e ()
  ((_ (char ...) dispatch-e)
   (defdispatch (char ...)
     (lambda (_ K xi rest)
       (with-args rest (arg . rest)
         (dispatch-e arg)
         (K xi rest))))))

(defrules defdispatch-q ()
  ((_ (char ...) expr)
   (defdispatch (char ...)
     (lambda (_ K xi rest)
       expr
       (K xi rest)))))

(defdispatch-e (#\a #\A)
  display)

(defdispatch-e (#\s #\S)
  write)

(defdispatch-e (#\c #\C)
  write-char)

(defdispatch-e (#\u #\U)
  (lambda (arg)
    (let (i (char->integer arg))
      (cond
       ((##fx< i #xf) (display "000"))
       ((##fx< i #xff) (display "00"))
       ((##fx< i #xfff) (display "0")))
      (display (number->string i 16)))))

(defdispatch-e (#\b #\B)
  (lambda (arg)
    (display (number->string arg 2))))

(defdispatch-e (#\o #\O)
  (lambda (arg)
    (display (number->string arg 8))))

(defdispatch-e (#\d #\D)
  (lambda (arg)
    (display (number->string arg 10))))

(defdispatch-e (#\x #\X)
  (lambda (arg)
    (let ((str (number->string arg 16))
          (nbytes (ceiling (/ (integer-length arg) 8))))
      (if (zero? nbytes)
          (display "00")
          (display (pad-string str (* 2 nbytes) #\0))))))

(defdispatch-e (#\y #\Y)
  pretty-print)

(defdispatch-e (#\r #\R)
  print-representation)

(defdispatch-q (#\% #\n)
  (newline))

(defdispatch-q (#\~)
  (write-char #\~))

(defdispatch-q (#\t #\T)
  (write-char #\tab))

(defdispatch-q (#\_)
  (write-char #\space))

;; recursive format
(defdispatch (#\? #\k #\K)
  (lambda (_ K xi rest)
    (with-args rest (re-fmt re-args . rest)
      (display (apply format re-fmt re-args))
      (K xi rest))))

;; fixed width specifiers
(defdispatch (#\f #\F)
  (lambda (_ K xi rest)
    (format-fixed-float #f #f K xi rest)))

(defdispatch (#\0 #\1 #\2 #\3 #\4 #\5 #\6 #\7 #\8 #\9)
  (lambda (char K xi rest)
    (let* ((str (current-format-string))
           (len (##string-length str)))

      (defrules bad-format-string ()
        ((_)
         (error "Bad format string; malformed fixed width specifier"
           str (current-format-args))))

      (let lp ((xi xi) (width [char]))
        (if (##fx< xi len)
          (let ((next (##string-ref str xi))
                (xi (##fx+ xi 1)))
            (case next
              ((#\f #\F)
               (format-fixed-float (chars->number (reverse width))
                                   #f K xi rest))
              ((#\,)
               (let lp2 ((xi xi) (digits []))
                 (if (##fx< xi len)
                   (let ((next (##string-ref str xi))
                         (xi (##fx+ xi 1)))
                     (cond
                      ((char-numeric? next)
                       (lp2 xi (cons next digits)))
                      ((and (memq next '(#\f #\F))
                            (not (null? digits)))
                       (format-fixed-float (chars->number (reverse width))
                                           (chars->number (reverse digits))
                                           K xi rest))
                      (else
                       (bad-format-string))))
                   (bad-format-string))))
              (else
               (cond
                ((char-numeric? next)
                 (lp xi (cons next width)))
                ((hash-get dispatch-table next)
                 => (lambda (f)
                      (format-fixed-generic (chars->number (reverse width))
                                            f next xi rest K)))
                 (else
                  (error "Unknown format specifier" str next))))))
          (bad-format-string))))))

(def (format-fixed-generic width f next xi rest K)
  (let* ((xi* #f)
         (rest* #f)
         (K*
          (lambda (xi rest)
            (set! xi* xi)
            (set! rest* rest)))
         (str
          (with-output-to-string []
            (lambda () (f next K* xi rest)))))
    (display (pad-string str width))
    (K xi* rest*)))

(def (format-fixed-float width digits K xi rest)
  (def (format-fixed arg digits)
    (cond
     ((number? arg)
      (let ((real (real-part arg))
            (imag (imag-part arg)))
        (cond
         ((not (zero? imag))
          (string-append
           (format-fixed real digits)
           (if (and (finite? imag) (positive? imag)) "+" "")
           (format-fixed imag digits)
           "i"))
         ((not (finite? real))
          (number->string real))
         (digits
          (let* ((shift (expt 10 digits))
                 (num (round (* (inexact->exact real) shift)))
                 (absnum (abs num))
                 (pre-str (number->string (quotient absnum shift)))
                 (pre-str
                  (if (negative? num)
                    (string-append "-" pre-str)
                    pre-str))
                 (frac-str (number->string (remainder absnum shift))))
            (compose-float digits pre-str frac-str)))
         (else
          (pad-zeros (number->string (exact->inexact arg)))))))
     (else
      (error "Bad argument for float format; expected number"
        (current-format-string) (current-format-args) arg))))

  (def (compose-float digits pre-str frac-str)
    (let (frac-len (string-length frac-str))
      (cond
       ((##fx< frac-len digits)
        (string-append pre-str "." (make-string (##fx- digits frac-len) #\0)
                       frac-str))
       ((##fx= frac-len digits)
        (string-append pre-str "." frac-str))
       ((##fx= digits 0)
        (if (equal? pre-str "-0") "0" pre-str))
       (else
        (error "BUG: compose-float" digits pre-str frac-str)))))

  ;; ensure there is a leading zero for sub-1 magnitude floats
  ;; ensure there is a fractional part
  (def (pad-zeros str)
    (let ((dot (string-index str #\.))
          (len (string-length str)))
      (cond
       ((not dot) str)
       ((##fxzero? dot)
        (string-append "0" str))
       ((and (##fx= dot 1) (eq? (##string-ref str 0) #\-))
        (string-append "-0" (substring str 1 len)))
       ((##fx= (##fx+ dot 1) len)
        (string-append str "0"))
       (else str))))

  (let (width (or width 0))
    (with-args rest (arg . rest)
      (display (pad-string (format-fixed arg digits) width))
      (K xi rest))))

(def (chars->number chars)
  (string->number (apply string chars)))

(def (pad-string str width (char #\space))
  (let (len (string-length str))
    (if (##fx< len width)
      (string-append (make-string (##fx- width len) char) str)
      str)))
