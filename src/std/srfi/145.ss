;;; -*- Gerbil -*-
;;; (c) vyzo at hackzen.org
;;; SRFI-145: Assumptions

(export assume)

(defrules assume ()
  ((_ expr message ...)
   (begin-annotation @runtime-check
     (unless expr
       (error message ...)))))
