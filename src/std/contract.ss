;;; -*- Gerbil -*-
;;; © vyzo
;;; Gerbil contract constructs

(import :std/error)
(export #t)

(defstruct (contract-violation <error>) ())

(def (raise-contract-violation where what . irritants)
  (raise (make-contract-violation what irritants where)))

;; contract assertions, that can be turned off with -O2/-no-runtime-checks.
(defrules @contract ()
  ((_ (where . args) assertion ...)
   (identifier? #'where)
   (begin-annotation @runtime-check
     (begin
       (unless assertion
         (raise-contract-violation 'where "Contract violation"
                                   (@list 'where . args) 'assertion))
       ...)))
  ((_ where assertion ...)
   (identifier? #'where)
   (begin-annotation @runtime-check
     (begin
       (unless assertion
         (raise-contract-violation 'where "Contract violation" 'assertion))
       ...))))

(begin-syntax
  (def (symbol-e id)
    (symbol->keyword (stx-e id)))
  (def (procedure-args hd)
    (let lp ((rest hd) (r []))
      (syntax-case rest ()
        ((id . rest)
         (identifier? #'id)
         (with-syntax ((xid (symbol-e #'id)))
           (lp #'rest (cons* #'id #'(quote xid) r))))
        (((id opt) . rest)
         (identifier? #'id)
         (with-syntax ((xid (symbol-e #'id)))
           (lp #'rest (cons* #'id #'(quote xid) r))))
        ((kw id . rest)
         (and (stx-keyword? #'kw)
              (identifier? #'id))
         (with-syntax ((xid (symbol-e #'id)))
           (lp #'rest (cons* #'id #'(quote xid) r))))
        ((kw (id opt) . rest)
         (and (stx-keyword? #'kw)
              (identifier? #'id))
         (with-syntax ((xid (symbol-e #'id)))
           (lp #'rest (cons* #'id #'(quote xid) r))))
        ((#!key _ . rest)
         (lp #'rest r))
        (tail
         (identifier? #'tail)
         (with-syntax ((xid (symbol-e #'tail)))
           (reverse (cons* #'tail ':: #'(quote xid) r))))
        (()
         (reverse r))))))

;; defines a procedure with an attached contract
(defsyntax (def/c stx)
  (syntax-case stx (@contract)
    ((_ (id . args) (@contract assertion ...) body ...)
     (with-syntax ((xargs (procedure-args #'args)))
       (syntax/loc stx
         (def (id . args)
           (@contract (id . xargs) assertion ...)
           body ...))))))

;; defines a case-lambda procedure with attached contracts
(defsyntax (def*/c stx)
  (syntax-case stx (@contract)
    ((_ id (hd (@contract assertion ...) body ...) ...)
     (with-syntax (((xargs ...) (map procedure-args #'(hd ...))))
       (syntax/loc stx
         (def* id
           (hd (@contract (id . xargs) assertion ...) body ...)
           ...))))))
