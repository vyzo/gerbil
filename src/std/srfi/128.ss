;;; -*- Gerbil -*-
;;; (c) vyzo at hackzen.org
;;; SRFI-128: Comparator library

(import :gerbil/gambit/hash
        :gerbil/gambit/bits
        :std/generic)
(export
  comparator? comparator-ordered? comparator-hashable?
  make-comparator make-pair-comparator make-list-comparator make-vector-comparator make-eq-comparator make-eqv-comparator make-equal-comparator
  boolean-hash char-hash char-ci-hash string-hash string-ci-hash symbol-hash number-hash
  hash-bound hash-salt
  make-default-comparator default-hash comparator-register-default!
  comparator-type-test-predicate comparator-equality-predicate comparator-ordering-predicate comparator-hash-function comparator-test-type comparator-check-type comparator-hash
  =? <? >? <=? >=?
  comparator-if<=>

  ;; non-standard: the generic implementing the default comparator order
  :less
  )

(defstruct comparator (testf eqf orderf hashf)
  final: #t)

(def (comparator-ordered? c)
  (and (comparator-orderf c) #t))

(def (comparator-hashable? c)
  (and (comparator-hashf c) #t))

(def (no-orderf a b)
  (error "Comparator does not provide an ordering function" a b))

(def (no-hashf o)
  (error "Comparator does not provide a hash function" o))

(defalias comparator-type-test-predicate comparator-testf)
(defalias comparator-equality-predicate comparator-eqf)

(def (comparator-ordering-predicate c)
  (or (comparator-orderf c) no-orderf))

(def (comparator-hash-function c)
  (or (comparator-hashf c) no-hashf))

(def (comparator-test-type c o)
  ((comparator-testf c) o))

(def (comparator-check-type c o)
  (begin-annotation @runtime-check
    (or (comparator-test-type c o)
        (error "Invalid argument" c o))))

(def (comparator-hash c o)
  ((comparator-hash-function c) o))

(def (make-pair-comparator carc cdrc)
  (def (testf o)
    (match o
      ([a . b]
       (and (comparator-test-type carc a)
            (comparator-test-type cdrc b)))
      (else #f)))
  (def (eqf a b)
    (match* (a b)
      (([a1 . a2] [b1 . b2])
       (and ((comparator-eqf carc) a1 b1)
            ((comparator-eqf cdrc) a2 b2)))))
  (def (orderf a b)
    (match* (a b)
      (([a1 . a2] [b1 . b2])
       (if ((comparator-eqf carc) a1 b1)
         (if ((comparator-eqf cdrc) a2 b2)
           #f
           ((comparator-ordering-predicate cdrc) a2 b2))
         ((comparator-ordering-predicate carc) a1 b1)))))
  (def (hashf o)
    (match o
      ([a . b]
       (bitwise-xor (comparator-hash carc a) (comparator-hash cdrc b)))))
  (make-comparator testf eqf orderf hashf))

(def (make-list-comparator elc type-test empty? head tail)
  (def (testf o)
    (and (type-test o)
         (let lp ((o o))
           (if (empty? o)
             #t
             (and (comparator-test-type elc (head o))
                  (lp (tail o)))))))
  (def (eqf a b)
    (cond
     ((empty? a)
      (empty? b))
     ((empty? b) #f)
     (else
      (and ((comparator-eqf elc) (head a) (head b))
           (eqf (tail a) (tail b))))))
  (def (orderf a b)
    (cond
     ((empty? a)
      (not (empty? b)))
     ((empty? b)
      #f)
     (else
      (or ((comparator-orderf elc) (head a) (head b))
          (orderf (tail a) (tail b))))))
  (def (hashf o)
    (let lp ((rest o) (h 0))
      (if (empty? o)
        h
        (lp (tail o) (bitwise-xor h (comparator-hash elc (head o)))))))
  (make-comparator testf eqf orderf hashf))

(def (make-vector-comparator elc type-test length ref)
  (def (testf o)
    (and (type-test o)
         (let ((len (length o))
               (test (comparator-testf elc)))
           (let lp ((i 0))
             (if (fx< i len)
               (and (test (ref o i))
                    (lp (fx1+ i)))
               #t)))))
  (def (eqf a b)
    (let ((len (length a))
          (lenb (length b))
          (eq (comparator-eqf elc)))
      (and (fx= len lenb)
           (let lp ((i 0))
             (if (fx< i len)
               (and (eq (ref a i) (ref a b))
                    (lp (fx1+ i)))
               #t)))))
  (def (orderf a b)
    (let ((len (length a))
          (lenb (length b))
          (order (comparator-ordering-predicate elc)))
      (cond
       ((fx< len lenb)
        #t)
       ((fx= len lenb)
        (let lp ((i 0))
          (and (fx< i len)
               (or (order (ref a i) (ref b i))
                   (lp (fx1+ i))))))
       (else #f))))
  (def (hashf o)
    (let ((len (length o))
          (hash (comparator-hash-function elc)))
      (let lp ((i 0) (h 0))
        (if (fx< i len)
          (lp (fx1+ i) (bitwise-xor (hash (ref o i))))
          h))))
  (make-comparator testf eqf orderf hashf))

(def *eq-comparator*
  (make-comparator true eq? #f eq?-hash))

(def (make-eq-comparator)
  *eq-comparator*)

(def *eqv-comparator*
  (make-comparator true eqv? #f eqv?-hash))

(def (make-eqv-comparator)
  *eqv-comparator*)

(def *equal-comparator*
  (make-comparator true equal? #f equal?-hash))

(def (make-equal-comparator)
  *equal-comparator*)

(def (boolean-hash o)
  (if o 1 0))

(def (char-hash o)
  (eq?-hash o))

(def (char-ci-hash o)
  (eq?-hash (char-upcase o)))

(defalias string-hash string=?-hash)
(defalias string-ci-hash string-ci=?-hash)
(defalias number-hash eqv?-hash)
(defalias default-hash equal?-hash)

(defrules hash-bound ()
  ((_) 536870911))

(defrules hash-salt ()
  ((_) 0))

(def (default-order a b)
  (:less a b))

(def *default-comparator*
  (make-comparator true equal? default-order equal?-hash))

(def (make-default-comparator)
  *default-comparator*)

(def *moar-comparators* [])

(def (comparator-register-default! cmp)
  (set! *moar-comparators* (cons cmp *moar-comparators*)))

(defgeneric :less
  (lambda (a b)
    (let lp ((rest *moar-comparators*))
      (match rest
        ([cmp . rest]
         (let (testf (comparator-testf cmp))
           (if (and (testf a) (testf b))
             ((comparator-ordering-predicate cmp) a b)
             (lp rest))))
        (else
         (string<? (symbol->string (type-of a)) (symbol->string (type-of b))))))))

(defmethod (:less (a <null>) (b <pair>))
  #t)

(defmethod (:less (a <pair>) (b <null>))
  #f)

(defmethod (:less (a <pair>) (b <pair>))
  (let lp ((a a) (b b))
    (match* (a b)
      (([a1 . b1] [a2 . b2])
       (if (equal? a1 a2)
         (lp b1 b2)
         (default-order a1 a2)))
      (else
       (if (pair? a) #f (not (null? b)))))))

(defmethod (:less (a <boolean>) (b <boolean>))
  (if a #f b))

(defmethod (:less (a <char>) (b <char>))
  (char<? a b))

(defmethod (:less (a <string>) (b <string>))
  (string<? a b))

(defmethod (:less (a <symbol>) (b <symbol>))
  (string<? (symbol->string a) (symbol->string b)))

(defmethod (:less (a <keyword>) (b <keyword>))
  (string<? (keyword->string a) (keyword->string b)))

(defmethod (:less (a <vector>) (b <vector>))
  (let ((len (##vector-length a))
        (lenb (##vector-length b)))
    (if (##fx= len lenb)
      (let lp ((i 0))
        (and (##fx< i len)
             (or (default-order (##vector-ref a i) (##vector-ref b i))
                 (lp (##fx+ i 1)))))
      (##fx< len lenb))))

(defmethod (:less (a <u8vector>) (b <u8vector>))
  (let ((len (##u8vector-length a))
        (lenb (##u8vector-length b)))
    (if (##fx= len lenb)
      (let lp ((i 0))
        (and (##fx< i len)
             (or (default-order (##u8vector-ref a i) (##u8vector-ref b i))
                 (lp (##fx+ i 1)))))
      (##fx< len lenb))))

(defmethod (:less (a <number>) (b <number>))
  (let ((ra (real-part a)) (rb (real-part b)))
    (cond
     ((< ra rb) #t)
     ((= ra rb)
      (< (imag-part a) (imag-part b)))
     (else #f))))

(def (=? cmp o . rest)
  (let (eqf (comparator-eqf cmp))
    (let lp ((rest rest) (o1 o))
      (match rest
        ([o2 . rest]
         (and (eqf o1 o2)
              (lp rest o2)))
        (else #t)))))

(def (<? cmp o . rest)
  (let (orderf (comparator-ordering-predicate cmp))
    (let lp ((rest rest) (o1 o))
      (match rest
        ([o2 . rest]
         (and (orderf o1 o2)
              (lp rest o2)))
        (else #t)))))

(def (<=? cmp o . rest)
  (let ((eqf (comparator-eqf cmp))
        (orderf (comparator-ordering-predicate cmp)))
    (let lp ((rest rest) (o1 o))
      (match rest
        ([o2 . rest]
         (and (or (eqf o1 o2) (orderf o1 o2))
              (lp rest o2)))
        (else #t)))))

(def (>? cmp . args)
  (apply <? cmp (reverse args)))

(def (>=? cmp . args)
  (apply <=? cmp (reverse args)))

(defrules comparator-if<=> ()
  ((_ cmp e1 e2 less equal greater)
   (let ((c cmp) (o1 e1) (o2 e2))
     (if ((comparator-ordering-predicate c) o1 o2)
       less
       (if ((comparator-eqf c) o1 o2)
         equal
         greater))))
  ((recur o1 o2 less equal greater)
   (recur (default-comparator) o1 o2 less equal greater)))
