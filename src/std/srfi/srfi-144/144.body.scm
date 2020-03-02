;;; Copyright (C) William D Clinger (2016).
;;;
;;; Permission is hereby granted, free of charge, to any person
;;; obtaining a copy of this software and associated documentation
;;; files (the "Software"), to deal in the Software without
;;; restriction, including without limitation the rights to use,
;;; copy, modify, merge, publish, distribute, sublicense, and/or
;;; sell copies of the Software, and to permit persons to whom the
;;; Software is furnished to do so, subject to the following
;;; conditions:
;;;
;;; The above copyright notice and this permission notice shall be
;;; included in all copies or substantial portions of the Software.
;;;
;;; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
;;; EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
;;; OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
;;; NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
;;; HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
;;; WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
;;; FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
;;; OTHER DEALINGS IN THE SOFTWARE.

;;; References
;;;
;;; Milton Abramowitz and Irene A Stegun [editors].
;;; Handbook of Mathematical Functions With Formulas, Graphs, and
;;; Mathematical Tables.  United States Department of Commerce.
;;; National Bureau of Standards Applied Mathematics Series, 55,
;;; June 1964.  Fifth Printing, August 1966, with corrections.
;;;
;;; R W Hamming.  Numerical Methods for Scientists and Engineers.
;;; McGraw-Hill, 1962.
;;;
;;; Donald E Knuth.  The Art of Computer Programming, Volume 2,
;;; Seminumerical Algorithms, Second Edition.  Addison-Wesley, 1981.
;;;
;;; J N Newman.  Approximations for the Bessel and Struve Functions.
;;; Mathematics of Computation, 43(168), October 1984, pages 551-556.

;;; I have deliberately avoided recent references, and have also
;;; avoided looking at any code or pseudocode for these or similar
;;; functions.

;;; Quick-and-dirty implementation of a draft of SRFI 144 (flonums),
;;; as specified at http://vrici.lojban.org/~cowan/temp/srfi-144.html
;;; as of 4 June 2017.
;;;
;;; FIXME: not as accurate as it should be
;;; FIXME: not as fast as it should be
;;; FIXME: assumes IEEE arithmetic or similar
;;; FIXME: assumes all inexact reals are flonums
;;; FIXME: assumes (scheme inexact)

;;; Mathematical Constants
;;;
;;; The mathematical constants are now defined in 144.constants.scm


;; Implementation Constants

(define fl-greatest
  (let loop ((x (- (expt 2.0 precision-bits) 1.0)))
    (if (finite? (* 2.0 x))
        (loop (* 2.0 x))
        x)))

(define fl-least
  (let loop ((x 1.0))
    (if (> (/ x 2.0) 0.0)
        (loop (/ x 2.0))
        x)))

(define fl-epsilon
  (let loop ((eps 1.0))
    (if (= 1.0 (+ 1.0 eps))
        (* 2.0 eps)
        (loop (/ eps 2.0)))))

(define fl-integer-exponent-zero                ; arbitrary
  (exact (- (log fl-least 2.0) 1.0)))

(define fl-integer-exponent-nan                 ; arbitrary
  (- fl-integer-exponent-zero 1))

;;; Constructors

; Implements post-finalization note 1
(define (flonum x)
  (if (real? x)
      (inexact x)
      +nan.0))

(define fladjacent
  (flop2 'fladjacent
         (lambda (x y)
           (define (loop y)
             (let* ((y3 (fl+ (fl* 0.999755859375 x) (fl* 0.000244140625 y))))
               (cond ((fl<? x y3 y)
                      (loop y3))
                     ((fl<? y y3 x)
                      (loop y3))
                     (else
                      (loop2 y)))))
           (define (loop2 y)
             (let* ((y2 (fl/ (fl+ x y) 2.0))
                    (y2 (if (flinfinite? y2)
                            (fl+ (fl* 0.5 x) (fl* 0.5 y))
                            y2)))
               (cond ((fl=? x y2)
                      y)
                     ((fl=? y y2)
                      y)
                     (else
                      (loop2 y2)))))
           (cond ((flinfinite? x)
                  (cond ((fl<? x y) (fl- fl-greatest))
                        ((fl>? x y) fl-greatest)
                        (else x)))
                 ((fl=? x y)
                  x)
                 ((flzero? x)
                  (if (flpositive? y)
                      fl-least
                      (fl- fl-least)))
                 ((fl<? x y)
                  (loop (flmin y
                               fl-greatest
                               (flmax (* 2.0 x)
                                      (* 0.5 x)))))
                 ((fl>? x y)
                  (loop (flmax y
                               (fl- fl-greatest)
                               (flmin (* 2.0 x)
                                      (* 0.5 x)))))
                 (else    ; x or y is a NaN
                  x)))))

(define flcopysign
  (flop2 'flcopysign
         (lambda (x y)
           (if (= (flsign-bit x) (flsign-bit y))
               x
               (fl- x)))))

(define (make-flonum x n)
  (begin-annotation @runtime-check
      (when (or (not (flonum? x))
                (not (exact-integer? n)))
        (error "bad arguments to make-flonum" x n)))
  (let ((y (expt 2.0 n)))
    (if (finite? y)
      (* x y)
      (inexact (* (exact x) (expt 2 n))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Accessors

(define (flinteger-fraction x)
  (check-flonum! 'flinteger-fraction x)
  (let* ((result1 (fltruncate x))
         (result2 (fl- x result1)))
    (values result1 result2)))

(define (flexponent x)
  (floor (fllog2 (flabs x))))

(define (flinteger-exponent x)
  (exact (flexponent x)))

(define (flnormalized-fraction-exponent x)
  (define (return result1 result2)
    (cond ((fl<? result1 0.5)
           (values (fl* 2.0 result1) (- result2 1)))
          ((fl>=? result1 1.0)
           (values (fl* 0.5 result1) (+ result2 1)))
          (else
           (values result1 result2))))
  (check-flonum! 'flnormalized-fraction-exponent x)
  (cond ((flnan? x)    ; unspecified for NaN
         (values x 0))
        ((fl<? x 0.0)
         (call-with-values
          (lambda () (flnormalized-fraction-exponent (fl- x)))
          (lambda (y n)
            (values (fl- y) n))))
        ((fl=? x 0.0)    ; unspecified for 0.0
         (values 0.0 0))
        ((flinfinite? x)
         (values 0.5 (+ 3 (exact (round (fllog2 fl-greatest))))))
        ((flnormalized? x)
         (let* ((result2 (exact (flround (fllog2 x))))
                (result2 (if (integer? result2)
                             result2
                             (round result2)))
                (two^result2 (inexact (expt 2.0 result2))))
           (if (flinfinite? two^result2)
               (call-with-values
                (lambda () (flnormalized-fraction-exponent (fl/ x 4.0)))
                (lambda (y n)
                  (values y (+ n 2))))
               (return (fl/ x two^result2) result2))))
        (else
         (let* ((k (+ 2 precision-bits))
                (two^k (expt 2 k)))
           (call-with-values
            (lambda ()
              (flnormalized-fraction-exponent (fl* x (inexact two^k))))
            (lambda (y n)
              (return y (- n k))))))))

(define (flsign-bit x)
  (check-flonum! 'flsign-bit x)
  (cond ((fl<? x 0.0)
         1)
        ((eqv? x -0.0)
         1)
        (else
         0)))


;;; Predicates

;(define flonum? R6RS)               ; defined by (rnrs arithmetic flonums)
;(define fl=? R6RS)                  ; defined by (rnrs arithmetic flonums)
;(define fl<? R6RS)                  ; defined by (rnrs arithmetic flonums)
;(define fl>? R6RS)                  ; defined by (rnrs arithmetic flonums)
;(define fl<=? R6RS)                 ; defined by (rnrs arithmetic flonums)
;(define fl>=? R6RS)                 ; defined by (rnrs arithmetic flonums)

(define (flunordered? x y)
  (or (flnan? x) (flnan? y)))

;;; incompatible with (rnrs arithmetic flonums) in zero-argument case

#;(define flmax
  (let ((flmax2 (flop2 'flmax max)))
    (lambda args
      (cond ((null? args)
             -inf.0)
            ((null? (cdr args))
             (car args))
            ((null? (cddr args))
             (flmax2 (car args) (cadr args)))
            (else
             (flmax2 (flmax2 (car args) (cadr args))
                     (apply flmax (cddr args))))))))

;;; incompatible with (rnrs arithmetic flonums) in zero-argument case

#;(define flmin
  (let ((flmin2 (flop2 'flmin min)))
    (lambda args
      (cond ((null? args)
             +inf.0)                 ; spec says fl-least, but that's wrong
            ((null? (cdr args))
             (car args))
            ((null? (cddr args))
             (flmin2 (car args) (cadr args)))
            (else
             (flmin2 (flmin2 (car args) (cadr args))
                     (apply flmin (cddr args))))))))

;(define flinteger? R6RS)            ; defined by (rnrs arithmetic flonums)
;(define flzero? R6RS)               ; defined by (rnrs arithmetic flonums)
;(define flpositive? R6RS)           ; defined by (rnrs arithmetic flonums)
;(define flnegative? R6RS)           ; defined by (rnrs arithmetic flonums)
;(define flodd? R6RS)                ; defined by (rnrs arithmetic flonums)
;(define fleven? R6RS)               ; defined by (rnrs arithmetic flonums)
;(define flfinite? R6RS)             ; defined by (rnrs arithmetic flonums)
;(define flinfinite? R6RS)           ; defined by (rnrs arithmetic flonums)
;(define flnan? R6RS)                ; defined by (rnrs arithmetic flonums)

(define flnormalized?
  (lambda (x)
    (check-flonum! 'flnormalized? x)
    (let ((x (flabs x)))
      (and (flfinite? x)
           (fl<? (fl/ fl-greatest) x)))))

(define fldenormalized?
  (lambda (x)
    (check-flonum! 'fldenormalized? x)
    (let ((x (flabs x)))
      (and (flfinite? x)
           (fl<? 0.0 x)
           (fl<=? x (fl/ fl-greatest))))))

;;; Arithmetic

;(define fl+ R6RS)                   ; defined by (rnrs arithmetic flonums)
;(define fl* R6RS)                   ; defined by (rnrs arithmetic flonums)

;;; Spec says "as if to infinite precision and rounded only once".

(define fl+*
  (flop3 'fl+*
         (lambda (x y z)
           (cond (c-functions-are-available
                  (fma x y z))
                 ((and (flfinite? x) (flfinite? y))
                  (if (flfinite? z)
                      (let ((x (exact x))
                            (y (exact y))
                            (z (exact z)))
                        (flonum (+ (* x y) z)))
                      z))
                 (else
                  (fl+ (fl* x y) z))))))

;(define fl- R6RS)                   ; defined by (rnrs arithmetic flonums)
;(define fl/ R6RS)                   ; defined by (rnrs arithmetic flonums)
;(define flabs R6RS)                 ; defined by (rnrs arithmetic flonums)

(define (flabsdiff x y)
  (flabs (fl- x y)))

(define (flposdiff x y)
  (let ((diff (fl- x y)))
    (if (flnegative? diff)
        0.0
        diff)))

(define (flsgn x)
  (flcopysign 1.0 x))

;;; (flnumerator +nan.0) and (fldenominator +nan.0) must be NaNs, which
;;; is not required by the R6RS specification of (rnrs arithmetic flonums).

(define flnumerator
  (flop1 'flnumerator
         (lambda (x)
           (if (flnan? x)
               x
               (r6rs:flnumerator x)))))

(define fldenominator
  (flop1 'fldenominator
         (lambda (x)
           (if (flnan? x)
               x
               (r6rs:fldenominator x)))))

;(define flfloor R6RS)               ; defined by (rnrs arithmetic flonums)
;(define flceiling R6RS)             ; defined by (rnrs arithmetic flonums)
;(define flround R6RS)               ; defined by (rnrs arithmetic flonums)
;(define fltruncate R6RS)            ; defined by (rnrs arithmetic flonums)

;;; Exponents and logarithms

;(define flexp R6RS)                 ; defined by (rnrs arithmetic flonums)

(define flexp2 (flop1 'flexp2 (lambda (x) (flexpt 2.0 x))))

;;; e^x = \sum_n (z^n / (n!))
;;;
;;; FIXME: the number of terms and the constant 0.5 seem reasonable
;;; for IEEE double precision, but the number of terms might need
;;; to be increased for higher precisions.

(define flexp-1
  (flop1 'flexp-1
         (let ((coefs (cons 0.0
                            (map fl/
                                 (map factorial
                                      '(1.0 2.0 3.0 4.0 5.0
                                        6.0 7.0 8.0 9.0 10.0
                                        11.0 12.0 13.0 14.0 15.0))))))
           (lambda (x)
             (cond ((fl<? (flabs x) 0.5)    ; FIXME
                    (polynomial-at x coefs))
                   (else
                    (fl- (flexp x) 1.0)))))))

(define flsquare (flop1 'flsquare (lambda (x) (fl* x x))))

;(define flsqrt R6RS)                ; defined by (rnrs arithmetic flonums)

(define flcbrt
  (flop1 'flcbrt
         (lambda (x)
           (cond ((flnegative? x)
                  (fl- (flcbrt (fl- x))))
                 (else
                  (flexpt x (fl/ 3.0)))))))

(define flhypot
  (flop2 'flhypot
         (lambda (x y)
           (cond ((flzero? x) (flabs y))
                 ((flzero? y) (flabs x))
                 ((or (flinfinite? x) (flinfinite? y)) +inf.0)
                 ((flnan? x) x)
                 ((flnan? y) y)
                 ((fl>? y x) (flhypot y x))
                 (else
                  (let* ((y/x (fl/ y x))
                         (root (flsqrt (fl+ 1.0 (fl* y/x y/x)))))
                    (fl* (flabs x) root)))))))

;(define flexpt R6RS)                ; defined by (rnrs arithmetic flonums)
;(define fllog R6RS)                 ; defined by (rnrs arithmetic flonums)

;;; Returns log(x+1), as in C99 log1p.

;;; See

;;; https://stat.ethz.ch/pipermail/r-devel/2003-August/027396.html
;;; https://books.google.com/books?id=OjUyDwAAQBAJ&pg=PA290&lpg=PA290&dq=beebe+log1p&source=bl&ots=VLxmiSk1fA&sig=ACfU3U0_8tqKemomSjKW73iJ0zUO1u3p3Q&hl=en&sa=X&ved=2ahUKEwjfxZbE8LvhAhVNm-AKHWScB7w4ChDoATAAegQICRAB#v=onepage&q=beebe%20log1p&f=false

;;; for justification


(define fllog1+
  (flop1 'fllog1+
         (lambda (x)
           (let ((u (fl+ 1.0 x)))
             (cond ((fl=? u 1.0)
                    x) ;; gets sign of zero result correct
                   ((fl=? u x)
                    (fllog u)) ;; large arguments and infinities
                   (else
                    (fl* (fllog u) (fl/ x (fl- u 1.0)))))))))


(define fllog2 (flop1 'fllog2 (lambda (x) (log x 2.0))))

(define fllog10 (flop1 'fllog10 (lambda (x) (log x 10.0))))

(define (make-fllog-base base)
  (check-flonum! 'make-fllog-base base)
  (if (fl>? base 1.0)
      (flop1 'procedure-created-by-make-fllog-base
             (lambda (x) (log x base)))
      (error "argument to make-fllog-base must be greater than 1.0" base)))

;;; Trigonometric functions

;(define flsin R6RS)                 ; defined by (rnrs arithmetic flonums)
;(define flcos R6RS)                 ; defined by (rnrs arithmetic flonums)
;(define fltan R6RS)                 ; defined by (rnrs arithmetic flonums)
;(define flasin R6RS)                ; defined by (rnrs arithmetic flonums)
;(define flacos R6RS)                ; defined by (rnrs arithmetic flonums)
;(define flatan R6RS)                ; defined by (rnrs arithmetic flonums)

(define flsinh
  (flop1 'flsinh
         (lambda (x)
           (cond ((not (flfinite? x)) x)
                 ((fl<? (flabs x) 0.75)
                  (fl/ (fl- (flexp-1 x) (flexp-1 (fl- x))) 2.0))
                 (else
                  (fl/ (fl- (flexp x) (flexp (fl- x))) 2.0))))))

(define flcosh
  (flop1 'flcosh
         (lambda (x)
           (cond ((not (flfinite? x)) (flabs x))
                 ((fl<? (flabs x) 0.75)
                  (fl+ 1.0 (fl/ (fl+ (flexp-1 x) (flexp-1 (fl- x))) 2.0)))
                 (else
                  (fl/ (fl+ (flexp x) (flexp (fl- x))) 2.0))))))

(define fltanh
  (flop1 'fltanh
         (lambda (x)
           (cond ((flinfinite? x) (flcopysign 1.0 x))
                 ((flnan? x) x)
                 (else
                  (let ((a (flsinh x))
                        (b (flcosh x)))
                    (cond ((fl=? a b)
                           1.0)
                          ((fl=? a (fl- b))
                           -1.0)
                          (else
                           (fl/ (flsinh x) (flcosh x))))))))))

;;; inverse hyperbolic functions

(define flasinh
  (flop1 'flasinh
         (lambda (x)
           (define (eqn4.6.31 x^2 c k k0)
             (if (> k 45) ; FIXME
                 c
                 (fl+ c
                      (fl* x^2
                           (eqn4.6.31 x^2
                                      (fl- (fl/ (fl* c k0 k0)
                                                (fl* (fl+ k0 1.0)
                                                     (fl+ k0 2.0))))
                                      (+ k 2)
                                      (fl+ k0 2.0))))))
           (cond ((flzero? x) x)
                 ((not (flfinite? x)) x)
                 ((fl<? x 0.0)
                  (fl- (flasinh (fl- x))))
                 ((fl<? x 0.5)
                  (fl* x (eqn4.6.31 (fl* x x) 1.0 1 1.0)))
                 (else
                  (let* ((x^2+1 (fl+ (fl* x x) 1.0))
                         (root (if (flfinite? x^2+1)
                                   (flsqrt x^2+1)
                                   x))
                         (a (fl+ x root)))
                    (if (flfinite? a)
                        (fllog a)
                        (fl+ fl-log-2 (fllog x)))))))))

(define flacosh
  (flop1 'flacosh
         (lambda (x)
           (if (fl<=? x 0.5)
               +nan.0
               (let* ((x^2-1 (fl- (fl* x x) 1.0))
                      (root (if (flfinite? x^2-1)
                                (flsqrt x^2-1)
                                x))
                      (a (fl+ x root)))
                 (if (flfinite? a)
                     (fllog a)
                     (fl+ fl-log-2 (fllog x))))))))

(define flatanh
  (flop1 'flatanh
         (lambda (x)
           (define (eqn4.6.33 x^2 k k0)
             (if (> k 50) ; FIXME
                 (fl/ k0)
                 (fl+ (fl/ k0)
                      (fl* x^2
                           (eqn4.6.33 x^2 (+ k 2) (+ k0 2.0))))))
           (cond ((flzero? x) x)
                 ((not (flfinite? x)) x)
                 ((fl<? x 0.0)
                  (fl- (flatanh (fl- x))))
                 ((fl<? x 0.5)
                  (fl* x (eqn4.6.33 (fl* x x) 1 1.0)))
                 (else
                  (fl* 0.5 (fllog (fl/ (fl+ 1.0 x) (fl- 1.0 x)))))))))

;;; Integer division

(define flquotient
  (flop2 'flquotient
         (lambda (x y)
           (fltruncate (fl/ x y)))))

;;; FIXME: should probably implement the following part of the C spec:
;;; "If the returned value is 0, it will have the same sign as x."

(define flremainder
  (flop2 'flremainder
         (lambda (x y)
           (fl- x (fl* y (flquotient x y))))))

(define (flremquo x y)
  (check-flonum! 'flremquo x)
  (check-flonum! 'flremquo y)
  (let* ((quo (flround (fl/ x y)))
         (rem (fl- x (fl* y quo))))
    (values rem
            (exact quo))))

;; Special functions are defined in 144.special.scm

; eof
