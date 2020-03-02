;;; -*- Gerbil -*-
;;; (c) vyzo at hackzen.org
;;; srfi implementation support libraries (mostly for Olin's code)

(export #t)

(defrules check-arg ()
  ((_ pred val caller)
   (if (begin-annotation @runtime-check (pred val)) val
       (error "Bad argument" val 'pred 'caller))))

(defrules let-optionals ()
  ((_ args opt-spec . body)
   (apply (lambda opt-spec . body) args)))

(defrules :optional ()
  ((_ rest default-exp)
   (let ((maybe-arg rest))
     (cond
      ((null? maybe-arg) default-exp)
      ((null? (cdr maybe-arg)) (car maybe-arg))
      (else (error "too many optional arguments" maybe-arg)))))
  ((_ rest default-exp check-proc)
   (let ((maybe-arg rest))
     (cond
      ((null? maybe-arg) default-exp)
      ((null? (cdr maybe-arg))
       (let ((val (car maybe-arg)))
         (if (begin-annotation @runtime-check (check-proc val)) val
             (error "argument out of domain" val))))
      (else (error "too many optional arguments" maybe-arg))))))

(defrules really-let-optionals* ()
  ((recur args ((var1 default1 typecheck ...) etc ...)
          body1 ...)
   (identifier? #'var1)
   (call-with-values (lambda () (if (null? args)
                             (values default1 '())
                             (values (car args) (cdr args))))
     (lambda (var1 rest)
       (if (begin-annotation @runtime-check (and typecheck ...))
         (recur rest (etc ...)
                body1 ...)
         (error "argument out of domain" var1)))))
  ((_ args (((var ...) proc)) body1 ...)
   (stx-andmap identifier? #'(var ...))
   (call-with-values (lambda () (proc args))
     (lambda (temp var ...) body1 ...)))
  ((_ args (rest) body1 ...)
   (identifier? #'rest)
   (let ((rest args)) body1 ...))
  ((_ args () body1 ...)
   (if (null? args) (let () body1 ...)
       (error "Too many optional arguments." args))))

(defrules let-optionals* ()
  ((_ args vars&defaults body1 ...)
   (let ((rest args))
     (really-let-optionals* rest vars&defaults body1 ...))))
