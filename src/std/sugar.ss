;;; -*- Gerbil -*-
;;; (C) vyzo
;;; some standard sugar

(export
  defrule
  catch
  finally
  try
  with-destroy
  defmethod/alias
  using
  using-method
  with-methods
  with-class-methods
  with-class-method
  assert!
  while
  until
  hash
  hash-eq
  hash-eqv
  let-hash
  awhen
  chain
  is
  fn
  )

(defalias fn lambda)
(defrules defrule ()
  ((_ (name args ...) body ...)
   (defrules name () ((name args ...) body ...))))

(defrules catch ())
(defrules finally ())

(defsyntax (try stx)
  (def (generate-thunk body)
    (if (null? body)
      (raise-syntax-error #f "Bad syntax; missing body" stx)
      (with-syntax (((e ...) (reverse body)))
        #'(lambda () e ...))))

  (def (generate-fini thunk fini)
    (with-syntax ((thunk thunk)
                  ((e ...) fini))
      #'(with-unwind-protect thunk (lambda () e ...))))

  (def (generate-catch handlers thunk)
    (with-syntax (($e (genident)))
      (let lp ((rest handlers) (clauses []))
        (match rest
          ([hd . rest]
           (syntax-case hd (=>)
             ((pred => K)
              (lp rest (cons #'(((? pred) $e) => K)
                             clauses)))
             (((pred var) body ...)
              (identifier? #'var)
              (lp rest (cons #'(((? pred) $e) (let ((var $e)) body ...))
                             clauses)))
             (((var) body ...)
              (identifier? #'var)
              (lp rest (cons #'(#t (let ((var $e)) body ...))
                             clauses)))
             ((us body ...)
              (underscore? #'us)
              (lp rest (cons #'(#t (begin body ...))
                             clauses)))))
          (else
           (with-syntax (((clause ...) clauses)
                         (thunk thunk))
             #'(with-catch
                (lambda ($e) (cond clause ... (else (raise $e))))
                thunk)))))))

  (syntax-case stx ()
    ((_ e ...)
     (let lp ((rest #'(e ...)) (body []))
       (syntax-case rest ()
         ((hd . rest)
          (syntax-case #'hd (catch finally)
            ((finally fini ...)
             (if (stx-null? #'rest)
               (generate-fini (generate-thunk body) #'(fini ...))
               (raise-syntax-error #f "Misplaced finally clause" stx)))
            ((catch handler ...)
             (let lp ((rest #'rest) (handlers [#'(handler ...)]))
               (syntax-case rest (catch finally)
                 (((catch handler ...) . rest)
                  (lp #'rest [#'(handler ...) . handlers]))
                 (((finally fini ...))
                  (with-syntax ((body (generate-catch handlers (generate-thunk body))))
                    (generate-fini #'(lambda () body) #'(fini ...))))
                 (()
                  (generate-catch handlers (generate-thunk body))))))
            (_ (lp #'rest (cons #'hd body)))))
         (() ; no clauses, just a begin
          (cons 'begin (reverse body))))))))

(defrule (with-destroy obj body ...)
  (let ($obj obj)
    (try body ... (finally {destroy $obj}))))

(defsyntax (defmethod/alias stx)
  (syntax-case stx (@method)
    ((_ {method (alias ...) type} body ...)
     (and (identifier? #'method)
          (stx-andmap identifier? #'(alias ...))
          (syntax-local-type-info? #'type))
     (with-syntax* (((values klass) (syntax-local-value #'type))
                    (type::t (runtime-type-identifier klass))
                    (method-impl (stx-identifier #'method #'type "::" #'method)))
       #'(begin
           (defmethod {method type} body ...)
           (bind-method! type::t 'alias method-impl) ...)))))

(defrule (using obj method ...)
  (begin (using-method obj method) ...))

(defrules using-method ()
  ((_ obj method)
   (identifier? #'method)
   (def method (checked-bound-method-ref obj 'method)))
  ((_ obj (method method-id))
   (and (identifier? #'method) (identifier? #'method-id))
   (def method (checked-bound-method-ref obj 'method-id))))


(defrule (with-methods o method ...)
  (begin
    (def $klass (object-type o))
    (with-class-methods $klass method ...)))

(defrule (with-class-methods klass method ...)
  (begin (with-class-method klass method) ...))

(defrules with-class-method ()
  ((_ klass (method method-id))
   (and (identifier? #'method) (identifier? #'method-id))
   (def method
     (cond
      ((find-method klass 'method-id))
      (else
       (error "Missing method" klass 'method-id)))))
  ((recur klass method)
   (identifier? #'method)
   (recur klass (method method))))

(defrules assert! ()
  ((_ expr)
   (unless expr
     (error "Assertion failed" 'expr)))
  ((_ expr message)
   (unless expr
     (error "Assertion failed" message 'expr))))

(defrule (while test body ...)
  (let lp ()
    (when test
      body ...
      (lp))))

(defrule (until test body ...)
  (let lp ()
    (unless test
      body ...
      (lp))))

(defrule (hash (key val) ...)
  (~hash-table make-hash-table (key val) ...))

(defrule (hash-eq (key val) ...)
  (~hash-table make-hash-table-eq (key val) ...))

(defrule (hash-eqv (key val) ...)
  (~hash-table make-hash-table-eqv (key val) ...))

(defsyntax (~hash-table stx)
  (syntax-case stx ()
    ((_ make-ht clause ...)
     (with-syntax* ((size (stx-length #'(clause ...)))
                    (((key val) ...) #'(clause ...)))
       #'(let (ht (make-ht size: size))
           (hash-put! ht `key val) ...
           ht)))))

;; the hash deconstructor macro
;; usage: (let-hash a-hash body ...)
;; rebinds %%ref so that identifiers starting with a dot are looked up in the hash:
;;  .x  -> (hash-ref a-hash 'x) ; strong accessor
;;  .?x -> (hash-get a-hash 'x) ; weak accessor
;;  ..x -> (%%ref .x)           ; escape
(defsyntax (let-hash stx)
  (syntax-case stx ()
    ((macro expr body ...)
     (with-syntax ((@ref (stx-identifier #'macro '%%ref)))
       #'(let (ht expr)
           (let-syntax
               ((var-ref
                 (syntax-rules ()
                   ((_ id) (@ref id)))))
             (let-syntax
                 ((@ref
                   (lambda (stx)
                     (syntax-case stx ()
                       ((_ id)
                        (let (str (symbol->string (stx-e #'id)))
                          (def (str->symbol start)
                            (string->symbol (substring str start (string-length str))))
                          (if (eq? (string-ref str 0) #\.) ; hash accessor?
                            (cond
                             ((eq? (string-ref str 1) #\.) ; escape
                              (with-syntax ((sym (str->symbol 1)))
                                #'(var-ref sym)))
                             ((eq? (string-ref str 1) #\?) ; weak
                              (with-syntax ((sym (str->symbol 2)))
                                #'(hash-get ht 'sym)))
                             (else
                              (with-syntax ((sym (str->symbol 1)))
                                #'(hash-ref ht 'sym))))
                            #'(var-ref id))))))))
               body ...)))))))

(defrule (awhen (id test) body ...)
  (let (id test)
    (when id body ...)))

;; chain rewrites passed expressions by passing the previous expression
;; into the position of the <> diamond symbol. In case a previous expression
;; should be used in a sub-expression, or multiple times, the expression can
;; be prefixed with a variable (supports destructuring).
;;
;; When the first expression is a <>, chain will return a unary lambda.
;;
;; Example:
;;  (chain [1 2 3]
;;    ([_ . rest] (map number->string rest))
;;    (v (string-join v ", "))
;;    (string-append <> " :)"))
;; => "2, 3 :)"
(defrules chain (<>)
  ((_ <> exp exp* ...)
    (lambda (init)
      (~chain-wrap-fn init (exp exp* ...))))

  ((_ init exp exp* ...)
    (~chain-wrap-fn init (exp exp* ...)))

  ((_ <>) (lambda (init) init))
  ((_ init) init))

;; ~chain-wrap-fn is an auxiliary macro to wrap unary procedures which
;; have no parentheses around with parentheses: proc -> (proc) to
;; distinguish them later in ~chain-aux.
(defrules ~chain-wrap-fn ()
  ((_ init () previous)
    (~chain-aux previous init))

  ((_ init ((proc arg arg* ...) . more))
    (~chain-wrap-fn init more ((proc arg arg* ...))))

  ((_ init ((proc arg arg* ...) . more) (previous ...))
    (~chain-wrap-fn init more (previous ... (proc arg arg* ...))))

  ((_ init (proc . more))
    (~chain-wrap-fn init more ((proc))))

  ((_ init (proc . more) (previous ...))
    (~chain-wrap-fn init more (previous ... (proc)))))

;; ~chain-aux is an auxiliary macro which takes a list of expressions
;; and the initial chain value. It then loops over the expression list
;; and transforms one expression after the other.
(defrules ~chain-aux (<>)
  ((_ () previous)
    previous)

  ((_ ((var ()) . more) previous)
    (syntax-error "Body expression cannot be empty"))

  ;; variable
  ((_ ((var (body1 body2 . body*)) . more) previous)
    (~chain-aux more
      (~chain-aux-variable (var previous) (body1 body2 . body*))))

  ((_ ((var (body1 body2 . body*) (body-error ...) ...) . more) previous)
    (syntax-error "More than one body expression in chain-variable context"))

  ;; unary procedure
  ((_ ((fn) . more) previous)
    (~chain-aux more (fn previous)))

  ;; diamond
  ((_ ((fn . args) . more) previous)
    (~chain-aux more
      (~chain-aux-diamond (fn . args) () previous))))

;; ~chain-aux-variable is an auxiliary macro that transforms
;; the passed expression into a with-expression.
(defrules ~chain-aux-variable ()
  ((_ (() (fn . args)) body)
    (syntax-error "The variable must be non-empty"))

  ((_ (var previous) body)
    (with ((var previous)) body)))

;; ~chain-aux-diamond is an auxiliary macro that replaces the <> symbol
;; with the previous expressions. There must be only one <> diamond in a row
;; and it must be in the top-level expression.
(defrules ~chain-aux-diamond (<>)
  ((_ () acc)
    acc)

  ((_ () acc previous)
    (syntax-error "No diamond operator in expression"))

  ((_ (<> . more) (acc ...))
    (syntax-error "More than one diamond operator in expression"))

  ((_ (<> . more) (acc ...) previous)
    (~chain-aux-diamond more (acc ... previous)))

  ((_ (v . more) (acc ...) . previous) ; previous is not set after <> was replaced
    (~chain-aux-diamond more (acc ... v) . previous)))

;; is converts a given value into a predicate testing for the presence of the
;; given value. Optionally a transforming procedure can prefix the value, which
;; can in this case also be a procedure. This allows to 'get' a value out of a
;; compound data structure before comparison (first map, then test).
;; For numbers, char and string specialized procedures are used automatically
;; if passed to the macro as value and not as variable. Alternatively, the
;; test: keyword can be used to supply a test, the default is equal?.
;;
;; Example:
;;  (find (is cdr 5) '((a . 2) (b . 5) (c . 6)))
;; => (b . 5)
;;
;;  (filter (is file-type 'regular) (directory-files))
;; => ("Documents" "Pictures" "Videos" "Music")
(defrules is ()
  ((_ proc n)
   (stx-number? #'n)
   (~is-helper proc number? = n))
  ((_ proc c)
   (stx-char? #'c)
   (lambda (v) (eqv? c (proc v))))
  ((_ proc s)
   (stx-string? #'s)
   (~is-helper proc string? string=? s))
  ((_ proc other)
   (if (procedure? other)
     (lambda (v) (other (proc v)))
     (lambda (v) (equal? other (proc v)))))
  ((_ proc other test: test)
   (if (procedure? other)
     (lambda (v) (other (proc v)))
     (lambda (v) (test other (proc v)))))
  ((_ n)
   (stx-number? #'n)
   (~is-helper number? = n))
  ((_ c)
   (stx-char? #'c)
   (lambda (v) (eqv? c v)))
  ((_ s)
   (stx-string? #'s)
   (~is-helper string? string=? s))
  ((_ v1)
   (lambda (v2) (equal? v1 v2)))
  ((_ v1 test: test)
   (lambda (v2) (test v1 v2))))

(defrules ~is-helper ()
  ((_ proc type-test value-test arg)
   (chain <>
    (proc <>)
    (v (and (type-test v) (value-test arg v)))))
  ((_ type-test value-test arg)
   (chain <>
    (v (and (type-test v) (value-test arg v))))))
