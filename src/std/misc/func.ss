;;; -*- Gerbil -*-
;;; © t.brandscheid@gmail.com
;;; © vyzo
;;; Utility procedures

(import :std/contract)
(export
  repeat always
  compose1 compose compose/values
  @compose1 @compose @compose/values
  rcompose1 rcompose rcompose/values
  @rcompose1 @rcompose @rcompose/values)

;; Repeat value or call function N times and return the result as list.
;; (repeat 2 5)                  -> (2 2 2 2 2)  ; repeat the value 2
;; (repeat random-interger 3 10) -> (8 3 5)      ; repeated function call with passed argument
(def/c (repeat v-or-fn n-times . args)
  (@contract (fixnum? n-times))
  (declare (fixnum) (not safe))
  (if (procedure? v-or-fn)
    (let ((fn (if (null? args)
		        v-or-fn
		        (lambda () (apply v-or-fn args)))))
      (let lp ((i 0)
               (acc []))
	    (if (< i n-times)
	      (lp (1+ i)
	          (cons (fn) acc))
	      (reverse acc))))
    (let lp ((i 0)
             (acc []))
      (if (< i n-times)
	    (lp (1+ i)
	        (cons v-or-fn acc))
	    acc))))

;; Creates a lambda which returns the same value or calls always the
;; same function with the same arguments.
;; (always 5)                 -> proc which takes no arguments and returns 5
;; (always random-integer 10) -> proc which takes one arguments and computes a random integer
(def (always v-or-fn . args)
  (lambda ()
    (if (procedure? v-or-fn)
      (apply v-or-fn args)
      v-or-fn)))


;; composes a sequence of unary functions; per the mathematical function composition
;; the value flows right to left.
(def* compose1
  (() identity)
  ((f) f)
  ((f1 f2)
   (lambda (x) (f1 (f2 x))))
  ((f1 f2 . rest)
   ;; this results in more efficient code when there are non-local exits
   (apply rcompose1 (reverse [f1 f2 . rest]))))

;; like compose1, but with the values flowing left-to-right
(def* rcompose1
  (() identity)
  ((f) f)
  ((f1 f2)
   (lambda (x) (f2 (f1 x))))
  ((f1 f2 . rest)
   (rcompose1 f1 (apply rcompose1 f2 rest))))

;; composes a sequence of functions right-to-left, where the first function accepts
;; an arbitrary number of arguments and each successive function returns a single value.
;; Note: if you are composing unary functions use compose1 as it avoids allocation for
;; capturing and the arguments and applying.
(def* compose
  (() identity)
  ((f) f)
  ((f1 f2)
   (lambda args (f1 (apply f2 args))))
  ((f1 f2 . rest)
   ;; this results in more efficient code when there are non-local exits
   (apply rcompose (reverse [f1 f2 . rest]))))

;; like compose, but with the values flowing left-to-right
(def* rcompose
  (() identity)
  ((f) f)
  ((f1 f2)
   (lambda args (f2 (apply f1 args))))
  ((f1 f2 . rest)
   (rcompose f1 (apply rcompose f2 rest))))

;; like compose, but multiple value returns are turned into arguments for the next function
(def* compose/values
  (() values)
  ((f) f)
  ((f1 f2)
   (lambda args
     (call-with-values (lambda () (apply f2 args)) f1)))
  ((f1 f2 . rest)
   ;; this results in more efficient code when there are non-local exits
   (apply rcompose/values (reverse [f1 f2 . rest]))))

;; like compose/values, but with arguments flowing left-to-right
(def* rcompose/values
  (() values)
  ((f) f)
  ((f1 f2)
   (lambda args
     (call-with-values (lambda () (apply f1 args)) f2)))
  ((f1 f2 . rest)
   (rcompose/values f1 (apply rcompose/values f2 rest))))

;;; macro versions of function composition
(defrules @compose1 ()
  ((_) identity)
  ((_ f) f)
  ((_ f1 f2 rest ...)
   (lambda (x) (@compose1~ x f1 f2 rest ...))))

(defrules @compose1~ ()
  ((_ x f) (f x))
  ((recur x f rest ...)
   (f (recur x rest ...))))

(defrules @rcompose1 ()
  ((_) identity)
  ((_ f) f)
  ((_ f1 f2 rest ...)
   (lambda (x)
     (@rcompose1~ (f1 x) f2 rest ...))))

(defrules @rcompose1~ ()
  ((_ f) f)
  ((recur f ... fn)
   (fn (recur f ...))))

(defrules @compose ()
  ((_) identity)
  ((_ f) f)
  ((_ f1 f2 rest ...)
   (lambda args
     (@compose~ args f1 f2 rest ...))))

(defrules @compose~ ()
  ((_ args f) (apply f args))
  ((recur args f rest ...)
   (f (recur args rest ...))))

(defrules @rcompose ()
  ((_) identity)
  ((_ f) f)
  ((_ f1 f2 rest ...)
   (lambda args
     (@rcompose~ (apply f1 args) f2 rest ...))))

(defrules @rcompose~ ()
  ((_ f) f)
  ((recur f ... fn)
   (fn (recur f ...))))

(defrules @compose/values ()
  ((_) values)
  ((_ f) f)
  ((_ f1 f2 rest ...)
   (lambda args
     (@compose/values~ args f1 f2 rest ...))))

(defrules @compose/values~ ()
  ((_ args f)
   (apply f args))
  ((recur args f rest ...)
   (call-with-values (lambda () (recur args rest ...)) f)))

(defrules @rcompose/values ()
  ((_) values)
  ((_ f) f)
  ((_ f1 f2 rest ...)
   (lambda args
     (@rcompose/values~ (apply f1 args) f2 rest ...))))

(defrules @rcompose/values~ ()
  ((_ f) f)
  ((recur f ... fn)
   (call-with-values (lambda () (recur f ...)) fn)))
