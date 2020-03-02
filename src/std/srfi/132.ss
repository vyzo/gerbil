;;; -*- Gerbil -*-
;;; (c) vyzo at hackzen.org
;;; SRFI-132: Sorting Library

(import :gerbil/gambit/random
        :gerbil/gambit/exact)
(export list-sorted?               vector-sorted?
        list-sort                  vector-sort
        list-stable-sort           vector-stable-sort
        list-sort!                 vector-sort!
        list-stable-sort!          vector-stable-sort!
        list-merge                 vector-merge
        list-merge!                vector-merge!
        list-delete-neighbor-dups  vector-delete-neighbor-dups
        list-delete-neighbor-dups! vector-delete-neighbor-dups!
        vector-find-median         vector-find-median!
        vector-select!             vector-separate!
        )

(defrules assert ()
  ((_ x)
   (begin-annotation @runtime-check
     (unless x
       (error "assertion failure")))))

(def (r7rs-vector-copy v start end)
  (subvector v start end))

(def (r7rs-vector-copy! v start v2 (start2 0) (end2 (vector-length v2)))
  (subvector-move! v start v2 start2 end2))

(def (r7rs-vector-fill! v val start end)
  (let (len (vector-length v))
    (let lp ((i start))
      (when (fx< i end)
        (vector-set! v i val)
        (lp (fx1+ i))))))

(include "srfi-132/delndups.scm")     ; list-delete-neighbor-dups etc
(include "srfi-132/lmsort.scm")       ; list-merge, list-merge!
(include "srfi-132/sortp.scm")        ; list-sorted?, vector-sorted?
(include "srfi-132/vector-util.scm")
(include "srfi-132/vhsort.scm")
(include "srfi-132/visort.scm")
(include "srfi-132/vmsort.scm")       ; vector-merge, vector-merge!
(include "srfi-132/vqsort2.scm")
(include "srfi-132/vqsort3.scm")
(include "srfi-132/sort.scm")
(include "srfi-132/select.scm")
