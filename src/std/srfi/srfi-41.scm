; Copyright (C) 2007 by Philip L. Bewig of Saint Louis, Missouri, USA.  All rights
; reserved.  Permission is hereby granted, free of charge, to any person obtaining a copy of
; this software and associated documentation files (the "Software"), to deal in the Software
; without restriction, including without limitation the rights to use, copy, modify, merge,
; publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to
; whom the Software is furnished to do so, subject to the following conditions: The above
; copyright notice and this permission notice shall be included in all copies or substantial
; portions of the Software.  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
; EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
; FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
; HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
; CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR
; THE USE OR OTHER DEALINGS IN THE SOFTWARE.

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; SRFI-9 records

;; (define-syntax define-record-type
;;   (syntax-rules ()
;;     ((define-record-type type
;;        (constructor constructor-tag ...)
;;        predicate
;;        (field-tag accessor . more) ...)
;;      (begin
;;        (define type
;;          (make-record-type 'type '(field-tag ...)))
;;        (define constructor
;;          (record-constructor type '(constructor-tag ...)))
;;        (define predicate
;;          (record-predicate type))
;;        (define-record-field type field-tag accessor . more)
;;        ...))))

;; (define-syntax define-record-field
;;   (syntax-rules ()
;;     ((define-record-field type field-tag accessor)
;;      (define accessor (record-accessor type 'field-tag)))
;;     ((define-record-field type field-tag accessor modifier)
;;      (begin
;;        (define accessor (record-accessor type 'field-tag))
;;        (define modifier (record-modifier type 'field-tag))))))

;; (define record-marker (list 'record-marker))

;; (define real-vector? vector?)

;; (define (vector? x)
;;   (and (real-vector? x)
;;        (or (= 0 (vector-length x))
;; 	   (not (eq? (vector-ref x 0)
;; 		record-marker)))))

;; (define eval
;;   (let ((real-eval eval))
;;     (lambda (exp env)
;;       ((real-eval `(lambda (vector?) ,exp))
;;        vector?))))

;; (define (record? x)
;;   (and (real-vector? x)
;;        (< 0 (vector-length x))
;;        (eq? (vector-ref x 0)
;;             record-marker)))

;; (define (make-record size)
;;   (let ((new (make-vector (+ size 1))))
;;     (vector-set! new 0 record-marker)
;;     new))

;; (define (record-ref record index)
;;   (vector-ref record (+ index 1)))

;; (define (record-set! record index value)
;;   (vector-set! record (+ index 1) value))

;; (define (record-type record)
;;   (record-ref record 0))

;; (define :record-type (make-record 3))
;; (record-set! :record-type 0 :record-type)
;; (record-set! :record-type 1 ':record-type)
;; (record-set! :record-type 2 '(name field-tags))

;; (define (make-record-type name field-tags)
;;   (let ((new (make-record 3)))
;;     (record-set! new 0 :record-type)
;;     (record-set! new 1 name)
;;     (record-set! new 2 field-tags)
;;     new))

;; (define (record-type-name record-type)
;;   (record-ref record-type 1))

;; (define (record-type-field-tags record-type)
;;   (record-ref record-type 2))

;; (define (field-index type tag)
;;   (let loop ((i 1) (tags (record-type-field-tags type)))
;;     (cond ((null? tags)
;;            (error 'field-index "record type has no such field" type tag))
;;           ((eq? tag (car tags))
;;            i)
;;           (else
;;            (loop (+ i 1) (cdr tags))))))

;; (define (record-constructor type tags)
;;   (let ((size (length (record-type-field-tags type)))
;;         (arg-count (length tags))
;;         (indexes (map (lambda (tag)
;;                         (field-index type tag))
;;                       tags)))
;;     (lambda args
;;       (if (= (length args)
;;              arg-count)
;;           (let ((new (make-record (+ size 1))))
;;             (record-set! new 0 type)
;;             (for-each (lambda (arg i)
;; 			(record-set! new i arg))
;;                       args
;;                       indexes)
;;             new)
;;           (error 'record-constructor "wrong number of arguments to constructor" type args)))))

;; (define (record-predicate type)
;;   (lambda (thing)
;;     (and (record? thing)
;;          (eq? (record-type thing)
;;               type))))

;; (define (record-accessor type tag)
;;   (let ((index (field-index type tag)))
;;     (lambda (thing)
;;       (if (and (record? thing)
;;                (eq? (record-type thing)
;;                     type))
;;           (record-ref thing index)
;;           (error 'record-accessor "accessor applied to bad value" type tag thing)))))

;; (define (record-modifier type tag)
;;   (let ((index (field-index type tag)))
;;     (lambda (thing value)
;;       (if (and (record? thing)
;;                (eq? (record-type thing)
;;                     type))
;;           (record-set! thing index value)
;;           (error 'record-modifier "modifier applied to bad value" type tag thing)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; SRFI-23 errors (modified for R6RS)

;; (define (error reason . args)
;;   (display "Error: ")
;;   (display (symbol->string reason))
;;   (for-each (lambda (arg)
;;             (display " ")
;;             (write arg))
;;             args)
;;   (newline)
;;   (scheme-report-environment -1))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; (streams primitive)

  (define-record-type stream-type
    (make-stream box)
    stream?
    (box stream-promise stream-promise!))

  (define-syntax stream-lazy
    (syntax-rules ()
      ((stream-lazy expr)
        (make-stream
          (cons 'lazy (lambda () expr))))))

  (define (stream-eager expr)
    (make-stream
      (cons 'eager expr)))

  (define-syntax stream-delay
    (syntax-rules ()
      ((stream-delay expr)
        (stream-lazy (stream-eager expr)))))

  (define (stream-force promise)
    (let ((content (stream-promise promise)))
      (case (car content)
        ((eager) (cdr content))
        ((lazy)  (let* ((promise* ((cdr content)))
                        (content  (stream-promise promise)))
                   (if (not (eqv? (car content) 'eager))
                       (begin (set-car! content (car (stream-promise promise*)))
                              (set-cdr! content (cdr (stream-promise promise*)))
                              (stream-promise! promise* content)))
                   (stream-force promise))))))

  (define stream-null (stream-delay (cons 'stream 'null)))

  (define-record-type stream-pare-type
    (make-stream-pare kar kdr)
    stream-pare?
    (kar stream-kar)
    (kdr stream-kdr))

  (define (stream-pair? obj)
    (and (stream? obj) (stream-pare? (stream-force obj))))

  (define (stream-null? obj)
    (and (stream? obj)
         (eqv? (stream-force obj)
               (stream-force stream-null))))

  (define-syntax stream-cons
    (syntax-rules ()
      ((stream-cons obj strm)
        (stream-eager (make-stream-pare (stream-delay obj) (stream-lazy strm))))))

  (define (stream-car strm)
    (@contract (stream-car strm)
               (stream? strm)
               (not (stream-null? strm)))
    (stream-force (stream-kar (stream-force strm))))

  (define (stream-cdr strm)
    (@contract (stream-cdr strm)
               (stream? strm)
               (not (stream-null? strm)))
    (stream-kdr (stream-force strm)))

  (define-syntax stream-lambda
    (syntax-rules ()
      ((stream-lambda formals body0 body1 ...)
        (lambda formals (stream-lazy (let () body0 body1 ...))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; (streams derived)

  (define (exists pred? . lists)
    (and (not (null? (car lists)))
         (or (apply pred? (map car lists))
             (apply exists pred? (map cdr lists)))))

  (define-syntax define-stream
    (syntax-rules ()
      ((define-stream (name . formal) body0 body1 ...)
        (define name (stream-lambda formal body0 body1 ...)))))

  (define (list->stream objs)
    (define list->stream
      (stream-lambda (objs)
        (if (null? objs)
            stream-null
            (stream-cons (car objs) (list->stream (cdr objs))))))

    (@contract (list->stream objs)
               (list? objs))
    (list->stream objs))

  (def (port->stream (p (current-input-port)))
    (define port->stream
      (stream-lambda (p)
        (let ((c (read-char p)))
          (if (eof-object? c)
              stream-null
              (stream-cons c (port->stream p))))))

      (@contract (port->stream p)
                 (input-port? p))
      (port->stream p))

  (define-syntax stream
    (syntax-rules ()
      ((stream) stream-null)
      ((stream x y ...) (stream-cons x (stream y ...)))))

  (def* stream->list
    ((strm)
     (stream->list #f strm))
    ((n strm)
     (@contract (stream->list n strm)
                (stream? strm)
                (or (not n) (and (integer? n) (not (negative? n)))))
     (let loop ((n (if n n -1)) (strm strm))
       (if (or (zero? n) (stream-null? strm))
         '()
         (cons (stream-car strm) (loop (- n 1) (stream-cdr strm)))))))

  (define (stream-append . strms)
    (define stream-append
      (stream-lambda (strms)
        (cond ((null? (cdr strms)) (car strms))
              ((stream-null? (car strms)) (stream-append (cdr strms)))
              (else (stream-cons (stream-car (car strms))
                                 (stream-append (cons (stream-cdr (car strms)) (cdr strms))))))))

    (@contract (stream-append :: strms)
               (andmap stream? strms))

    (if (null? strms)
      stream-null
      (stream-append strms)))

  (define (stream-concat strms)
    (define stream-concat
      (stream-lambda (strms)
        (if (stream-null? strms)
          stream-null
          (let (kar (stream-car strms))
            (begin-annotation @runtime-check
              (unless (stream? kar)
                (error "expected stream" kar)))
            (if (stream-null? kar)
              (stream-concat (stream-cdr strms))
              (stream-cons
               (stream-car kar)
               (stream-concat
                (stream-cons (stream-cdr kar) (stream-cdr strms)))))))))

    (@contract (stream-concat strms)
               (stream? strms))
    (stream-concat strms))

  (define stream-constant
    (stream-lambda objs
      (cond ((null? objs) stream-null)
            ((null? (cdr objs)) (stream-cons (car objs) (stream-constant (car objs))))
            (else (stream-cons (car objs)
                               (apply stream-constant (append (cdr objs) (list (car objs)))))))))

  (define (stream-drop n strm)
    (define stream-drop
      (stream-lambda (n strm)
        (if (or (zero? n) (stream-null? strm))
            strm
            (stream-drop (- n 1) (stream-cdr strm)))))

    (@contract (stream-drop n strm)
               (and (integer? n) (not (negative? n)))
               (stream? strm))
    (stream-drop n strm))

  (define (stream-drop-while pred? strm)
    (define stream-drop-while
      (stream-lambda (strm)
        (if (and (stream-pair? strm) (pred? (stream-car strm)))
            (stream-drop-while (stream-cdr strm))
            strm)))

    (@contract (stream-drop-while pred? strm)
               (procedure? pred?)
               (stream? strm))
    (stream-drop-while strm))

  (define (stream-filter pred? strm)
    (define stream-filter
      (stream-lambda (strm)
        (cond ((stream-null? strm) stream-null)
              ((pred? (stream-car strm))
                (stream-cons (stream-car strm) (stream-filter (stream-cdr strm))))
              (else (stream-filter (stream-cdr strm))))))

    (@contract (stream-filter pred? strm)
               (procedure? pred?)
               (stream? strm))
    (stream-filter strm))

  (define (stream-fold proc base strm)
    (@contract (stream-fold proc base strm)
               (procedure? proc)
               (stream? strm))
    (let loop ((base base) (strm strm))
      (if (stream-null? strm)
        base
        (loop (proc base (stream-car strm)) (stream-cdr strm)))))

  (define (stream-for-each proc . strms)
    (define (stream-for-each strms)
      (if (not (exists stream-null? strms))
          (begin (apply proc (map stream-car strms))
                 (stream-for-each (map stream-cdr strms)))))

    (@contract (stream-for-each proc :: strms)
               (procedure? proc)
               (not (null? strms))
               (andmap stream? strms))
    (stream-for-each strms))

  (def (stream-from first (delta 1))
    (define stream-from
      (stream-lambda (first delta)
        (stream-cons first (stream-from (+ first delta) delta))))

    (@contract (stream-from first delta)
               (number? first)
               (number? delta))
    (stream-from first delta))

  (define (stream-iterate proc base)
    (define stream-iterate
      (stream-lambda (base)
        (stream-cons base (stream-iterate (proc base)))))

    (@contract (stream-iterate proc base)
               (procedure? proc))
    (stream-iterate base))

  (define (stream-length strm)
    (@contract (stream-length strm)
               (stream? strm))
    (let loop ((len 0) (strm strm))
      (if (stream-null? strm)
        len
        (loop (+ len 1) (stream-cdr strm)))))

  (define-syntax stream-let
    (syntax-rules ()
      ((stream-let tag ((name val) ...) body1 body2 ...)
       ((letrec ((tag (stream-lambda (name ...) body1 body2 ...))) tag) val ...))))

  (define (stream-map proc . strms)
    (define stream-map
      (stream-lambda (strms)
        (if (exists stream-null? strms)
            stream-null
            (stream-cons (apply proc (map stream-car strms))
                         (stream-map (map stream-cdr strms))))))

    (@contract (stream-map proc :: strms)
               (procedure? proc)
               (not (null? strms))
               (andmap stream? strms))
    (stream-map strms))

  (define-syntax stream-match
    (syntax-rules ()
      ((stream-match strm-expr clause ...)
        (let ((strm strm-expr))
          (cond
            ((not (stream? strm)) (error 'stream-match "non-stream argument"))
            ((stream-match-test strm clause) => car) ...
            (else (error 'stream-match "pattern failure")))))))

  (define-syntax stream-match-test
    (syntax-rules ()
      ((stream-match-test strm (pattern fender expr))
        (stream-match-pattern strm pattern () (and fender (list expr))))
      ((stream-match-test strm (pattern expr))
        (stream-match-pattern strm pattern () (list expr)))))

  (define-syntax stream-match-pattern
    (lambda (x)
      (define (wildcard? x)
        (and (identifier? x)
             (free-identifier=? x (syntax _))))
      (syntax-case x ()
        ((stream-match-pattern strm () (binding ...) body)
          (syntax (and (stream-null? strm) (let (binding ...) body))))
        ((stream-match-pattern strm (w? . rest) (binding ...) body)
          (wildcard? #'w?)
          (syntax (and (stream-pair? strm)
                       (let ((strm (stream-cdr strm)))
                         (stream-match-pattern strm rest (binding ...) body)))))
        ((stream-match-pattern strm (var . rest) (binding ...) body)
          (syntax (and (stream-pair? strm)
                       (let ((temp (stream-car strm)) (strm (stream-cdr strm)))
                         (stream-match-pattern strm rest ((var temp) binding ...) body)))))
        ((stream-match-pattern strm w? (binding ...) body)
          (wildcard? #'w?)
          (syntax (let (binding ...) body)))
        ((stream-match-pattern strm var (binding ...) body)
          (syntax (let ((var strm) binding ...) body))))))

  (define-syntax stream-of
    (syntax-rules ()
      ((stream-of expr rest ...)
        (stream-of-aux expr stream-null rest ...))))

  (define-syntax stream-of-aux
    (syntax-rules (in is)
      ((stream-of-aux expr base)
        (stream-cons expr base))
      ((stream-of-aux expr base (var in stream) rest ...)
        (stream-let loop ((strm stream))
          (if (stream-null? strm)
              base
              (let ((var (stream-car strm)))
                (stream-of-aux expr (loop (stream-cdr strm)) rest ...)))))
      ((stream-of-aux expr base (var is exp) rest ...)
        (let ((var exp)) (stream-of-aux expr base rest ...)))
      ((stream-of-aux expr base pred? rest ...)
        (if pred? (stream-of-aux expr base rest ...) base))))

  (def (stream-range first past (delta (if (< first past) 1 -1)))
    (define stream-range
      (stream-lambda (first past delta lt?)
        (if (lt? first past)
            (stream-cons first (stream-range (+ first delta) past delta lt?))
            stream-null)))

    (@contract (stream-range first past delta)
               (number? first)
               (number? past)
               (number? delta))
    (let ((lt? (if (< 0 delta) < >)))
      (stream-range first past delta lt?)))

  (define (stream-ref strm n)
    (@contract (stream-ref strm n)
               (stream? strm)
               (and (integer? n) (not (negative? n))))
    (let loop ((strm strm) (n n))
      (cond ((stream-null? strm) (error 'stream-ref "beyond end of stream"))
            ((zero? n) (stream-car strm))
            (else (loop (stream-cdr strm) (- n 1))))))

  (define (stream-reverse strm)
    (define stream-reverse
      (stream-lambda (strm rev)
        (if (stream-null? strm)
            rev
            (stream-reverse (stream-cdr strm) (stream-cons (stream-car strm) rev)))))

    (@contract (stream-reverse strm)
               (stream? strm))
    (stream-reverse strm stream-null))

  (define (stream-scan proc base strm)
    (define stream-scan
      (stream-lambda (base strm)
        (if (stream-null? strm)
            (stream base)
            (stream-cons base (stream-scan (proc base (stream-car strm)) (stream-cdr strm))))))

    (@contract (stream-scan proc base strm)
               (procedure? proc)
               (stream? strm))
    (stream-scan base strm))

  (define (stream-take n strm)
    (define stream-take
      (stream-lambda (n strm)
        (if (or (stream-null? strm) (zero? n))
            stream-null
            (stream-cons (stream-car strm) (stream-take (- n 1) (stream-cdr strm))))))

    (@contract (stream-take n strm)
               (stream? strm)
               (and (integer? n) (not (negative? n))))
    (stream-take n strm))

  (define (stream-take-while pred? strm)
    (define stream-take-while
      (stream-lambda (strm)
        (cond ((stream-null? strm) stream-null)
              ((pred? (stream-car strm))
                (stream-cons (stream-car strm) (stream-take-while (stream-cdr strm))))
              (else stream-null))))

    (@contract (stream-take-while pred? strm)
               (procedure? pred?)
               (stream? strm))
    (stream-take-while strm))

  (define (stream-unfold mapper pred? generator base)
    (define stream-unfold
      (stream-lambda (base)
        (if (pred? base)
            (stream-cons (mapper base) (stream-unfold (generator base)))
            stream-null)))

    (@contract (stream-unfold mapper pred? generator base)
               (procedure? mapper)
               (procedure? pred?)
               (procedure? generator))
    (stream-unfold base))

  (define (stream-unfolds gen seed)
    (define (len-values gen seed)
      (call-with-values
        (lambda () (gen seed))
        (lambda vs (- (length vs) 1))))
    (define unfold-result-stream
      (stream-lambda (gen seed)
        (call-with-values
          (lambda () (gen seed))
          (lambda (next . results)
            (stream-cons results (unfold-result-stream gen next))))))
    (define result-stream->output-stream
      (stream-lambda (result-stream i)
        (let ((result (list-ref (stream-car result-stream) (- i 1))))
          (cond ((pair? result)
                  (stream-cons
                    (car result)
                    (result-stream->output-stream (stream-cdr result-stream) i)))
                ((not result)
                  (result-stream->output-stream (stream-cdr result-stream) i))
                ((null? result) stream-null)
                (else (error 'stream-unfolds "can't happen"))))))
    (define (result-stream->output-streams result-stream)
      (let loop ((i (len-values gen seed)) (outputs '()))
        (if (zero? i)
            (apply values outputs)
            (loop (- i 1) (cons (result-stream->output-stream result-stream i) outputs)))))

    (@contract (stream-unfolds gen seed)
               (procedure? gen))
    (result-stream->output-streams (unfold-result-stream gen seed)))

  (define (stream-zip . strms)
    (define stream-zip
      (stream-lambda (strms)
        (if (exists stream-null? strms)
            stream-null
            (stream-cons (map stream-car strms) (stream-zip (map stream-cdr strms))))))

    (@contract (stream-zip :: strms)
               (not (null? strms))
               (andmap stream? strms))
    (stream-zip strms))
