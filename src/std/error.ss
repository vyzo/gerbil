;;; -*- Gerbil -*-
;;; (C) vyzo
;;; Gerbil error objects

(export #t)

(defsyntax exception
  (make-runtime-struct-info
   runtime-identifier: (quote-syntax exception::t)))

(defsyntax <error>
  (make-runtime-struct-info
   runtime-identifier: (quote-syntax error::t)))

(defmethod {display-exception <error>}
  (lambda (self port)
    (parameterize ((current-output-port port))
      (cond
       ((error-trace self)
        => (lambda (where) (display* where ": "))))
      (display* "[" (##type-name (object-type self)) "] ")
      (displayln (error-message self))
      (let (irritants (error-irritants self))
        (unless (null? irritants)
          (displayln "--- irritants: ")
          (for-each
            (lambda (obj) (display "--- ") (write obj) (newline))
            irritants))))))

(defstruct (io-error <error>) ())
(defstruct (timeout-error <error>) ())

(def (raise-io-error where what . irritants)
  (raise (make-io-error what irritants where)))

(def (raise-timeout where what . irritants)
  (raise (make-timeout-error what irritants where)))
