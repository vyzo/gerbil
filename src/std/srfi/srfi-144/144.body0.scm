;;; Private but portable code.

(define FIXME 'FIXME)

(define precision-bits    ; IEEE double has 53 bits of precision
  (let loop ((bits 0)
             (x 1.0))
    (if (= x (+ x 1.0))
        bits
        (loop (+ bits 1)
              (* 2.0 x)))))

(define (check-flonum! name x)
  (begin-annotation @runtime-check
    (if (not (flonum? x))
      (error (string-append "non-flonum argument passed to "
                            (symbol->string name))
        x))))

;;; Given a symbol naming a flonum procedure and a generic operation,
;;; returns a flonum procedure that restricts the generic operation
;;; to flonum arguments and result.

(define (flop1 name op)
  (lambda (x)
    (check-flonum! name x)
    (let ((result (op x)))
      (begin-annotation @runtime-check
        (if (not (flonum? result))
          (error (string-append "non-flonum result from "
                                (symbol->string name))
            result)))
      result)))

(define (flop2 name op)
  (lambda (x y)
    (check-flonum! name x)
    (check-flonum! name y)
    (let ((result (op x y)))
      (begin-annotation @runtime-check
        (if (not (flonum? result))
          (error (string-append "non-flonum result from "
                                (symbol->string name))
            result)))
      result)))

(define (flop3 name op)
  (lambda (x y z)
    (check-flonum! name x)
    (check-flonum! name y)
    (check-flonum! name z)
    (let ((result (op x y z)))
      (begin-annotation @runtime-check
        (if (not (flonum? result))
          (error (string-append "non-flonum result from "
                                (symbol->string name))
            result)))
      result)))

;;; Given a flonum x and a list of flonum coefficients for a polynomial,
;;; in order of increasing degree, returns the value of the polynomial at x.

(define (polynomial-at x coefs)
  (if (null? coefs)
      0.0
#;    (fma x (polynomial-at x (cdr coefs)) (car coefs)) ; doesn't help
      (fl+ (car coefs)
           (fl* x (polynomial-at x (cdr coefs))))))

;;; This uses Simpson's rule.

(define (definite-integral lower upper f . rest)
  (let* ((range (fl- upper lower))
         (kmax (if (or (null? rest)
                       (not (and (exact-integer? (car rest))
                                 (even? (car rest))
                                 (positive? (car rest)))))
                   1024 ; FIXME: must be even, should be power of 2
                   (car rest)))
         (n2 (inexact kmax))
         (h (fl/ range n2)))
    (define (loop k n sum)    ; n = (inexact k)
      (cond ((= k 0)
             (loop 1 1.0 (f lower)))
            ((= k kmax)
             (fl+ sum (f upper)))
            (else
             (let ((fn (f (+ lower (fl/ (fl* n range) n2)))))
               (loop (+ k 1)
                     (fl+ n 1.0)
                     (fl+ sum (fl* (if (even? k) 2.0 4.0) fn)))))))
    (fl/ (fl* h (loop 0 0.0 0.0))
         3.0)))

;;; Given x between x0 and x1, interpolates between f0 and f1.
;;; Can also extrapolate.

(define (interpolate x x0 x1 f0 f1)
  (let ((delta (fl- x1 x0)))
    (fl+ (fl* (fl/ (fl- x1 x) delta) f0)
         (fl* (fl/ (fl- x x0) delta) f1))))

(define (iota n)
  (do ((n (- n 1) (- n 1))
       (x '() (cons n x)))
      ((< n 0) x)))

;;; Given a exact non-negative integer, returns its factorial.

(define (fact x)
  (if (zero? x)
      1
      (* x (fact (- x 1)))))

;;; Given a non-negative integral flonum x, returns its factorial.

(define (factorial x)
  (if (flzero? x)
      1.0
      (fl* x (factorial (fl- x 1.0)))))

; eof
