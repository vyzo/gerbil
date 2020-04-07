;;; -*- Gerbil -*-
;;; (C) vyzo
;;; textual template related utilities

(import :std/format
        (for-syntax :std/misc/ports
                    :std/format
                    :std/stxutil
                    :std/sugar))
(export include-text
        quasistring    include-quasistring
        quasistring*   include-quasistring*)

;; compile-time include a file as text (a string)
(defsyntax (include-text stx)
  (syntax-case stx ()
    ((_ path)
     (stx-string? #'path)
     (let (path (gx#core-resolve-path #'path (stx-source stx)))
       (with-syntax ((txt (call-with-input-file path read-all-as-string)))
         #'(quote txt))))))

;; quasistring utility functions
(begin-syntax
  (def qs-err-missing-close "Malformed quasistring: closing } required after s-exp")

  (def (stx-format stx)
    (if (stx-string? stx) ;; don't format strings
      stx
      (with-syntax ((stx stx))
        #'(format "~a" stx))))

  (def (map-format stx)
    (stx-map stx-format stx))

  ;; custom eval to capture the proper variables
  (def (eval** stx ctx)
    (parameterize ((current-expander-phi (1+ (current-expander-phi))))
      (let (stx (datum->syntax ctx stx))
        (eval-syntax stx #t))))

  (def (parse-quasistring stx ctx rt-symbol-proc output-proc (expansion-time-eval #f))
    ;; rt-symbol-proc wraps sexp if sexp is a run time symbol
    ;; output-proc is what we return from the macro
    ;; if expansion-time-eval is #t, allow for ##{} template variables
    (def (lp (port (open-input-string (stx-e stx)))
             (c    (read-char port))
             (ops  [])  ;; arguments of string-append
             (str  "")) ;; container to concatenate strings
      (cond
       ((eq? c #\#)
        (let (c+1 (read-char port))
          (cond
           ((eq? c+1 #\{) ;; run time template variables
            (let ((sexp (read port))
                  (c+2  (read-char port)))
              (if (eq? c+2 #\})
                (if (symbol? sexp)
                  (lp port (read-char port) (cons* (rt-symbol-proc sexp) str ops) "")
                  (lp port (read-char port) (cons* (datum->syntax ctx sexp) str ops) ""))
                (lp port (read-char port) ops (string-append str (list->string [c c+1 c+2]))))))
           ((eq? c+1 #\#) ;; expansion time template variables
            (if expansion-time-eval
              (let (c+2 (read-char port))
                (if (eq? c+2 #\{)
                  (let* ((sexp     (read port))
                         (sexp-str (format "~a" (eval** sexp ctx)))
                         (c+3      (read-char port)))
                    (if (eq? c+3 #\})
                      ;; allow for nested templates
                      (let* ((rest (read-all-as-string port))
                             (tmp  (string-append sexp-str rest))
                             (new-port (open-input-string tmp)))
                        (close-input-port port)
                        (lp new-port (read-char new-port) ops str))
                      (lp port (read-char port) ops (string-append str (list->string [c c+1 c+2 c+3])))))
                  (lp port (read-char port) ops (string-append str (list->string [c c+1 c+2])))))
              (lp port (read-char port) ops (string-append str (list->string [c c+1])))))
           (else
            (lp port (read-char port) ops (string-append str (list->string [c c+1])))))))
       ((eq? c #!eof)
        (close-input-port port)
        (with-syntax (((ops ...) (datum->syntax ctx (map-format (reverse (cons* str ops))))))
          (output-proc #'(ops ...))))
       (else
        (lp port (read-char port) ops (string-append str (list->string [c]))))))
    (lp)))

(defsyntax (defquasiparser stx)
  (syntax-case stx ()
    ((_ id rt-symbol-proc output-proc expand-time-eval)
     #'(defsyntax (id stx*)
         (syntax-case stx* ()
           ((macro s)
            (if (stx-string? (syntax s))
              (with-syntax ((ps (parse-quasistring
                                 (syntax s)
                                 (syntax macro)
                                 rt-symbol-proc
                                 output-proc
                                 expand-time-eval)))
                (syntax ps))
              ;; if not a string, eval the sexp
              (with-syntax* ((s* (eval** (syntax s) (syntax macro)))
                             (ps (parse-quasistring
                                  (syntax s*)
                                  (syntax macro)
                                  rt-symbol-proc
                                  output-proc
                                  expand-time-eval)))
                (syntax ps))))
           ((macro s ctx)
            (if (stx-string? (syntax s))
              (with-syntax ((ps (parse-quasistring
                                 (syntax s)
                                 (syntax ctx)
                                 rt-symbol-proc
                                 output-proc
                                 expand-time-eval)))
                (syntax ps))
              ;; if not a string, eval the sexp
              (with-syntax* ((s* (eval** (syntax s) (syntax ctx)))
                             (ps (parse-quasistring
                                  (syntax s*)
                                  (syntax ctx)
                                  rt-symbol-proc
                                  output-proc
                                  expand-time-eval)))
                (syntax ps)))))))))

(defsyntax (defincludes stx)
  (def (include-proc id ctx)
    (with-syntax* ((id* (datum->syntax #f id))
                   (proc (format-id #'id* "include-~a" #'id*)))
      #'(defsyntax (proc stx)
          (syntax-case stx ()
            ((macro path)
             (stx-string? (syntax path))
             (let (path (gx#core-resolve-path (syntax path) (stx-source stx)))
               (with-syntax ((tmp (call-with-input-file path read-all-as-string)))
                 (syntax (id* tmp macro)))))))))
  
  (syntax-case stx ()
    ((macro id ...) 
     (stx-andmap identifier? #'(id ...))
     (with-syntax (((procs ...) (map (cut include-proc <> #'macro) #'(id ...))))
       #'(begin procs ...)))))

;; only allow run time template variables
(defquasiparser quasistring
  (lambda (sym) sym)
  (lambda (ops)
    (with-syntax (((ops ...) ops))
      #'(string-append ops ...)))
  #f)

;; allow run and expand time template variables
(defquasiparser quasistring*
  (lambda (sym) sym)
  (lambda (ops)
    (with-syntax (((ops ...) ops))
      #'(string-append ops ...)))
  #t)

(defincludes quasistring quasistring*)
