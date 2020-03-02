;;; -*- Gerbil -*-
;;; (C) vyzo at hackzen.org
;;;     belmarca
;;; miscellaneous bytes utilities

(import (for-syntax :std/stxutil)
        :gerbil/gambit/exact
        :gerbil/gambit/bits
        :gerbil/gambit/fixnum
        :std/text/hex
        :std/foreign
        :std/contract)
(export
  ;; Endianness
  endianness big little native native-endianness
  ;; Primitives
  bytevector-u8-ref
  bytevector-u8-set!

  u8vector-s8-ref bytevector-s8-ref
  u8vector-s8-set! bytevector-s8-set!

  u8vector-uint-ref bytevector-uint-ref
  u8vector-uint-set! bytevector-uint-set!
  u8vector-sint-ref bytevector-sint-ref
  u8vector-sint-set! bytevector-sint-set!

  u8vector->uint-list bytevector->uint-list
  u8vector->sint-list bytevector->sint-list
  uint-list->u8vector uint-list->bytevector
  sint-list->u8vector sint-list->bytevector

  u8vector-u16-ref bytevector-u16-ref
  u8vector-u16-native-ref bytevector-u16-native-ref
  u8vector-u16-set! bytevector-u16-set!
  u8vector-u16-native-set! bytevector-u16-native-set!

  u8vector-s16-ref bytevector-s16-ref
  u8vector-s16-native-ref bytevector-s16-native-ref
  u8vector-s16-set! bytevector-s16-set!
  u8vector-s16-native-set! bytevector-s16-native-set!

  u8vector-u32-ref bytevector-u32-ref
  u8vector-u32-native-ref bytevector-u32-native-ref
  u8vector-u32-set! bytevector-u32-set!
  u8vector-u32-native-set! bytevector-u32-native-set!

  u8vector-s32-ref bytevector-s32-ref
  u8vector-s32-native-ref bytevector-s32-native-ref
  u8vector-s32-set! bytevector-s32-set!
  u8vector-s32-native-set! bytevector-s32-native-set!

  u8vector-u64-ref bytevector-u64-ref
  u8vector-u64-native-ref bytevector-u64-native-ref
  u8vector-u64-set! bytevector-u64-set!
  u8vector-u64-native-set! bytevector-u64-native-set!

  u8vector-s64-ref bytevector-s64-ref
  u8vector-s64-native-ref bytevector-s64-native-ref
  u8vector-s64-set! bytevector-s64-set!
  u8vector-s64-native-set! bytevector-s64-native-set!

  u8vector-float-ref bytevector-ieee-single-ref
  u8vector-float-set! bytevector-ieee-single-set!
  u8vector-float-native-ref bytevector-ieee-single-native-ref
  u8vector-float-native-set! bytevector-ieee-single-native-set!
  u8vector-double-ref bytevector-ieee-double-ref
  u8vector-double-set! bytevector-ieee-double-set!
  u8vector-double-native-ref bytevector-ieee-double-native-ref
  u8vector-double-native-set! bytevector-ieee-double-native-set!

  ;; Utilities
  u8vector-swap! bytevector-swap!
  u8vector-reverse bytevector-reverse
  u8vector-reverse! bytevector-reverse!
  u8vector->bytestring bytevector->bytestring
  bytestring->u8vector bytestring->bytevector
  u8vector->uint bytevector->uint
  uint->u8vector uint->bytevector

  ;; uhchecked operations
  &u8vector-s8-ref
  &u8vector-s8-set!

  &u8vector-uint-ref/be
  &u8vector-uint-ref/le
  &u8vector-uint-set!/be
  &u8vector-uint-set!/le
  &u8vector-sint-ref/be
  &u8vector-sint-ref/le
  &u8vector-sint-set!/be
  &u8vector-sint-set!/le

  &u8vector-u16-ref/native
  &u8vector-u16-set!/native
  &u8vector-s16-ref/native
  &u8vector-s16-set!/native
  &u8vector-u32-ref/native
  &u8vector-u32-set!/native
  &u8vector-s32-ref/native
  &u8vector-s32-set!/native
  &u8vector-u64-ref/native
  &u8vector-u64-set!/native
  &u8vector-s64-ref/native
  &u8vector-s64-set!/native

  &u8vector-float-ref/native
  &u8vector-float-set!/native
  &u8vector-double-ref/native
  &u8vector-double-set!/native

  &u8vector-swap!
  )

;;; Endianness

(def big 'big)
(def little 'little)
(def native 'native)

(defrules endianness (big little native)
  ((_ big) big)
  ((_ little) little)
  ((_ native) native)
  ((_ unknown)
   (syntax-error "Unknown endianness" unknown)))

;;; Primitives

(defalias bytevector-u8-ref u8vector-ref)
(defalias bytevector-u8-set! u8vector-set!)
(defalias bytevector-s8-ref u8vector-s8-ref)
(defalias bytevector-s8-set! u8vector-s8-set!)
(defalias bytevector-uint-ref u8vector-uint-ref)
(defalias bytevector-uint-set! u8vector-uint-set!)
(defalias bytevector-sint-ref u8vector-sint-ref)
(defalias bytevector-sint-set! u8vector-sint-set!)
(defalias bytevector->uint-list u8vector->uint-list)
(defalias bytevector->sint-list u8vector->sint-list)
(defalias uint-list->bytevector uint-list->u8vector)
(defalias sint-list->bytevector sint-list->u8vector)

(defrules check-int-ref ()
  ((_ where v k size)
   (@contract where
              (u8vector? v)
              (and (fixnum? k)
                   (fx<= 0 k (fx1- (u8vector-length v))))
              (and (fixnum? size)
                   (fx<= 0 size (fx- (u8vector-length v) k)))))
  ((_ where v size)
   (@contract where
              (u8vector? v)
              (and (fixnum? size)
                   (fx> size 0)
                   (fxzero? (fxremainder (u8vector-length v) size))))))

(defrules do-endianness ()
  ((_ endianness do-big do-little)
   (case endianness
     ((big) do-big)
     ((little) do-little)
     ((native)
      (if (eq? native-endianness little)
        do-little
        do-big))
     (else
      (error "Bad endianness" endianness))))
  ((_ endianness do-big do-little do-native)
   (if (eq? endianness native-endianness)
     do-native
     (case endianness
       ((big) do-big)
       ((little) do-little)
       ((native) do-native)
       (else
        (error "Bad endianness" endianness))))))

(def (u8vector-s8-ref v i)
  (check-int-ref (u8vector-s8-ref v i) v i 1)
  (&u8vector-s8-ref v i))

(def (&u8vector-s8-ref v i)
  (declare (not safe))
  (let (u8 (u8vector-ref v i))
    (if (fx> u8 127)
      (fx- u8 256)
      u8)))

(def (u8vector-s8-set! v i s8)
  (check-int-ref (u8vector-s8-set! v i s8) v i 1)
  (unless (fixnum? s8)
    (error "expected fixnum" s8))
  (&u8vector-s8-set! v i s8))

(def (&u8vector-s8-set! v i s8)
  (declare (not safe))
  (let (u8 (if (fx< s8 0)
             (fx+ s8 256)
             s8))
    (u8vector-set! v i u8)))

(def (u8vector-uint-ref v k endianness size)
  (check-int-ref (u8vector-uint-ref v k endianness size) v k size)
  (do-endianness endianness
     (&u8vector-uint-ref/be v k size)
     (&u8vector-uint-ref/le v k size)))

(def (&u8vector-uint-ref/be v k size)
  (declare (not safe))
  (let (k+size (fx+ k size))
    (let lp ((i k) (r 0))
      (if (fx< i k+size)
        (let (u8 (u8vector-ref v i))
          (lp (fx1+ i)
              (bitwise-ior (arithmetic-shift r 8) u8)))
        r))))

(def (&u8vector-uint-ref/le v k size)
  (declare (not safe))
  (let (k+size-1 (fx1- (fx+ k size)))
    (let lp ((i k+size-1) (r 0))
      (if (fx>= i k)
        (let (u8 (u8vector-ref v i))
          (lp (fx1- i)
              (bitwise-ior (arithmetic-shift r 8) u8)))
        r))))

(def (u8vector-uint-set! v k uint endianness size)
  (check-int-ref (u8vector-uint-set! v k uint endianness size) v k size)
  (do-endianness endianness
   (&u8vector-uint-set!/be v k uint size)
   (&u8vector-uint-set!/le v k uint size)))

(def (&u8vector-uint-set!/be v k uint size)
  (declare (not safe))
  (let (k+size-1 (fx1- (fx+ k size)))
    (let lp ((i k+size-1) (uint uint))
      (when (fx>= i k)
        (let (u8 (bitwise-and uint #xff))
          (u8vector-set! v i u8)
          (lp (fx1- i) (arithmetic-shift uint -8)))))))

(def (&u8vector-uint-set!/le v k uint size)
  (declare (not safe))
  (let (k+size (fx+ k size))
    (let lp ((i k) (uint uint))
      (when (fx< i k+size)
        (let (u8 (bitwise-and uint #xff))
          (u8vector-set! v i u8)
          (lp (fx1+ i) (arithmetic-shift uint -8)))))))

(def (u8vector-sint-ref v k endianness size)
  (check-int-ref (u8vector-sint-ref v k endianness size) v k size)
  (do-endianness endianness
     (&u8vector-sint-ref/be v k size)
     (&u8vector-sint-ref/le v k size)))

(defrules do-sint-ref ()
  ((_ size getq)
   (let (uint getq)
     (if (> uint (1- (expt 2 (1- (fx* size 8)))))
      (- uint (expt 2 (fx* size 8)))
      uint))))

(def (&u8vector-sint-ref/be v k size)
  (do-sint-ref size (&u8vector-uint-ref/be v k size)))

(def (&u8vector-sint-ref/le v k size)
  (do-sint-ref size (&u8vector-uint-ref/le v k size)))

(def (u8vector-sint-set! v k sint endianness size)
  (check-int-ref (u8vector-sint-set! v k sint endianness size) v k size)
  (do-endianness endianness
     (&u8vector-sint-set!/be v k sint size)
     (&u8vector-sint-set!/le v k sint size)))

(defrules do-sint-set! ()
  ((_ size sint uint setq)
   (let (uint (if (< sint 0)
                (+ sint (expt 2 (fx* size 8)))
                sint))
     setq)))

(def (&u8vector-sint-set!/be v k sint size)
  (do-sint-set! size sint uint (&u8vector-uint-set!/be v k uint size)))

(def (&u8vector-sint-set!/le v k sint size)
  (do-sint-set! size sint uint (&u8vector-uint-set!/le v k uint size)))

(def (u8vector->uint-list v endianness size)
  (check-int-ref (u8vector->uint-list v endianness size) v size)
  (do-endianness endianness
    (&u8vector->int-list v size &u8vector-uint-ref/be)
    (&u8vector->int-list v size &u8vector-uint-ref/le)))

(def (u8vector->sint-list v endianness size)
  (check-int-ref (u8vector->sint-list v endianness size) v size)
  (do-endianness endianness
    (&u8vector->int-list v size &u8vector-sint-ref/be)
    (&u8vector->int-list v size &u8vector-sint-ref/le)))

(def (&u8vector->int-list v size getf)
  (declare (fixnum) (not safe))
  (let (len (u8vector-length v))
    (let lp ((i 0) (r []))
      (if (< i len)
        (let (next (getf v i size))
          (lp (+ i size) (cons next r)))
        (reverse r)))))

(defrules check-int-list ()
  ((_ lst size)
   (begin
     (unless (and (list? lst) (andmap exact-integer? lst))
       (error "Expected list of exact integers" lst))
     (unless (and (fixnum? size) (fx> size 0))
       (error "Bad size" size)))))

(def (uint-list->u8vector lst endianness size)
  (check-int-list lst size)
  (do-endianness endianness
    (&int-list->u8vector lst size &u8vector-uint-set!/be)
    (&int-list->u8vector lst size &u8vector-uint-set!/le)))

(def (sint-list->u8vector lst endianness size)
  (check-int-list lst size)
  (do-endianness endianness
    (&int-list->u8vector lst size &u8vector-sint-set!/be)
    (&int-list->u8vector lst size &u8vector-sint-set!/le)))

(def (&int-list->u8vector lst size setf)
  (declare (fixnum) (not safe))
  (let* ((len (* (length lst) size))
         (v (make-u8vector len)))
    (let lp ((rest lst) (i 0))
      (match rest
        ([int . rest]
         (setf v i int size)
         (lp rest (+ i size)))
        (else v)))))

(defsyntax (defintprocs stx)
  (def (make-def int size &int-ref &int-set!)
    (with-syntax ((size size)
                  (&int-ref/be      (format-id &int-ref "~a/be" &int-ref))
                  (&int-ref/le      (format-id &int-ref "~a/le" &int-ref))
                  (&int-ref/native  (format-id int "&u8vector-~a-ref/native" int))
                  (&int-set!/be     (format-id &int-set! "~a/be" &int-set!))
                  (&int-set!/le     (format-id &int-set! "~a/le" &int-set!))
                  (&int-set!/native (format-id int "&u8vector-~a-set!/native" int))
                  (int-ref          (format-id int "u8vector-~a-ref" int))
                  (int-native-ref   (format-id int "u8vector-~a-native-ref" int))
                  (int-set!         (format-id int "u8vector-~a-set!" int))
                  (int-native-set!  (format-id int "u8vector-~a-native-set!" int))
                  (bv-ref           (format-id int "bytevector-~a-ref" int))
                  (bv-native-ref    (format-id int "bytevector-~a-native-ref" int))
                  (bv-set!          (format-id int "bytevector-~a-set!" int))
                  (bv-native-set!   (format-id int "bytevector-~a-native-set!" int)))
      #'(begin
          (def (int-ref v k endianness)
            (check-int-ref (int-ref v k endianness) v k size)
            (do-endianness endianness
              (&int-ref/be v k size)
              (&int-ref/le v k size)
              (&int-ref/native v k)))
          (defalias bv-ref int-ref)
          (def (int-set! v k n endianness)
            (check-int-ref (int-set! v k n endianness) v k size)
            (do-endianness endianness
              (&int-set!/be v k n size)
              (&int-set!/le v k n size)
              (&int-set!/native v k n)))
          (defalias bv-set! int-set!)
          (def (int-native-ref v k)
            (check-int-ref (int-native-ref v k) v k size)
            (&int-ref/native v k))
          (defalias bv-native-ref int-native-ref)
          (def (int-native-set! v k n)
            (check-int-ref (int-native-set! v k n) v k size)
            (&int-set!/native v k n))
          (defalias bv-native-set! int-native-set!))))

  (syntax-case stx ()
    ((_ (int size &int-ref &int-set!) ...)
     (with-syntax (((defs ...)
                    (map make-def
                         #'(int ...)
                         #'(size ...)
                         #'(&int-ref ...)
                         #'(&int-set! ...))))
       #'(begin defs ...)))))

(defintprocs
  (u16 2 &u8vector-uint-ref &u8vector-uint-set!)
  (s16 2 &u8vector-sint-ref &u8vector-sint-set!)
  (u32 4 &u8vector-uint-ref &u8vector-uint-set!)
  (s32 4 &u8vector-sint-ref &u8vector-sint-set!)
  (u64 8 &u8vector-uint-ref &u8vector-uint-set!)
  (s64 8 &u8vector-sint-ref &u8vector-sint-set!))

(defalias bytevector-ieee-single-ref u8vector-float-ref)
(defalias bytevector-ieee-single-set! u8vector-float-set!)
(defalias bytevector-ieee-single-native-ref u8vector-float-native-ref)
(defalias bytevector-ieee-single-native-set! u8vector-float-native-set!)
(defalias bytevector-ieee-double-ref u8vector-double-ref)
(defalias bytevector-ieee-double-set! u8vector-double-set!)
(defalias bytevector-ieee-double-native-ref u8vector-double-native-ref)
(defalias bytevector-ieee-double-native-set! u8vector-double-native-set!)

(defrules do-float-ref ()
  ((_ v k endianness size native-ref)
   (if (or (eq? endianness native-endianness)
           (eq? endianness native))
     (native-ref v k)
     (let (v* (make-u8vector size))
       (declare (fixnum) (not safe))
       (do ((i (1- (+ k size)) (1- i))
            (j 0 (1+ j)))
           ((= j size))
         (u8vector-set! v* j (u8vector-ref v i)))
       (native-ref v* 0)))))

(defrules do-float-set! ()
  ((_ v k x endianness size native-set!)
   (if (or (eq? endianness native-endianness)
           (eq? endianness native))
     (native-set! v k x)
     (begin
       (native-set! v k x)
       (&u8vector-reverse! v k size)))))

(def (u8vector-float-ref v k endianness)
  (check-int-ref (u8vector-float-ref v k endianness) v k 4)
  (do-float-ref v k endianness 4 &u8vector-float-ref/native))

(def (u8vector-float-set! v k x endianness)
  (check-int-ref (u8vector-float-set! v k x endianness) v k 4)
  (do-float-set! v k x endianness 4 &u8vector-float-set!/native))

(def (u8vector-float-native-ref v k)
  (check-int-ref (u8vector-float-native-ref v k) v k 4)
  (&u8vector-float-ref/native v k))

(def (u8vector-float-native-set! v k x)
  (check-int-ref (u8vector-float-native-set! v k x) v k 4)
  (&u8vector-float-set!/native v k x))

(def (u8vector-double-ref v k endianness)
  (check-int-ref (u8vector-double-ref v k endianness) v k 8)
  (do-float-ref v k endianness 8 &u8vector-double-ref/native))

(def (u8vector-double-set! v k x endianness)
  (check-int-ref (u8vector-double-set! v k x endianness) v k 8)
  (do-float-set! v k x endianness 8 &u8vector-double-set!/native))

(def (u8vector-double-native-ref v k)
  (check-int-ref (u8vector-double-native-ref v k) v k 8)
  (&u8vector-double-ref/native v k))

(def (u8vector-double-native-set! v k x)
  (check-int-ref (u8vector-double-native-set! v k x) v k 8)
  (&u8vector-double-set!/native v k x))

;;; Utilities

(defalias bytevector-swap! u8vector-swap!)
(defalias bytevector-reverse! u8vector-reverse!)
(defalias bytevector-reverse u8vector-reverse)
(defalias bytevector->bytestring u8vector->bytestring)
(defalias bytestring->bytevector bytestring->u8vector)
(defalias bytevector->uint u8vector->uint)
(defalias uint->bytevector uint->u8vector)

(def/c (u8vector-swap! v j k)
  (@contract (u8vector? v)
             (fx<= 0 j (fx1- (u8vector-length v)))
             (fx<= 0 k (fx1- (u8vector-length v))))
  (&u8vector-swap! v j k))

(def (&u8vector-swap! v j k)
  (declare (not safe))
  (let ((j-val (u8vector-ref v j))
        (k-val (u8vector-ref v k)))
    (u8vector-set! v j k-val)
    (u8vector-set! v k j-val)))

(def/c (u8vector-reverse! v)
  (@contract (u8vector? v))
  (&u8vector-reverse! v 0 (u8vector-length v)))

(def (&u8vector-reverse! v k size)
  (declare (fixnum) (not safe))
  (do ((left-index k (1+ left-index))
       (right-index (1- (+ k size)) (1- right-index)))
      ((<= right-index left-index))
    (&u8vector-swap! v left-index right-index)))

(def/c (u8vector-reverse v)
  (@contract (u8vector? v))
  (declare (fixnum) (not safe))
  (let* ((len (u8vector-length v))
         (len-1 (1- len))
         (u (make-u8vector len)))
    (do ((i len-1 (1- i)))
        ((= i -1))
      (u8vector-set! u (- len-1 i) (u8vector-ref v i)))
    u))

(def/c (u8vector->bytestring v (delim #\space))
  (@contract (u8vector? v)
             (or (not delim) (char? delim)))
  (declare (fixnum) (not safe))
  (let* ((len (u8vector-length v))
         (s (make-string (+ (* 2 len) (if delim (1- len) 0)))))
    (let lp ((i 0) (j 0))
      (when (< i len)
        (let (next (u8vector-ref v i))
          (string-set! s j (char-upcase (hex (fxarithmetic-shift next -4))))
          (string-set! s (+ j 1) (char-upcase (hex (fxand next #x0f))))
          (when delim
            (string-set! s (+ j 2) delim))
          (lp (1+ i) (+ j 2 (if delim 1 0))))))
    s))

;; TODO: this could be a lot more efficient if we were operating directly on the string
;;       instead of splitting it.
;;       optimize me!
(def (bytestring->u8vector bs (delim #\space))
  (declare (fixnum) (not safe))
  (if delim
    (let* ((lst (string-split bs delim))
           (v (make-u8vector (length lst))))
      (let lp ((rest lst) (i 0))
        (match rest
          ([x . rest]
           (unless (= (string-length x) 2)
             (error "Invalid bytestring component" x))
           (let ((hi (unhex (string-ref x 0)))
                 (lo (unhex (string-ref x 1))))
             (u8vector-set! v i (fxior (fxarithmetic-shift hi 4) lo))
             (lp rest (1+ i))))
          (else v))))
    (hex-decode bs)))

(def/c (u8vector->uint v (endianness big))
  (@contract (u8vector? v))
  (do-endianness endianness
    (&u8vector->uint/be v)
    (&u8vector->uint/le v)))

(def (&u8vector->uint/be v)
  (declare (not safe))
  (let (len (u8vector-length v))
    (let lp ((i 0) (r 0))
      (if (fx< i len)
        (lp (fx1+ i)
            (bitwise-ior (arithmetic-shift r 8)
                         (u8vector-ref v i)))
        r))))

(def (&u8vector->uint/le v)
  (declare (not safe))
  (let (len (u8vector-length v))
    (let lp ((i (fx1- len)) (r 0))
      (if (fx>= i 0)
        (lp (fx1- i)
            (bitwise-ior (arithmetic-shift r 8)
                         (u8vector-ref v i)))
        r))))

(def/c (uint->u8vector uint (endianness big))
  (@contract (and (exact-integer? uint) (>= uint 0)))
  (do-endianness endianness
    (&uint->u8vector/be uint)
    (&uint->u8vector/le uint)))

(def (&uint->u8vector/be uint)
  (declare (not safe))
  (let* ((bits (integer-length uint))
         (bytes (fx+ (fxquotient bits 8) (if (fx> (fxremainder bits 8) 0) 1 0)))
         (res (make-u8vector bytes)))
    (let lp ((uint uint) (i (fx- bytes 1)))
      (if (> uint 0)
        (begin
          (u8vector-set! res i (bitwise-and uint #xff))
          (lp (arithmetic-shift uint -8)
              (fx1- i)))
        res))))

(def (&uint->u8vector/le uint)
  (declare (not safe))
  (let* ((bits (integer-length uint))
         (bytes (fx+ (fxquotient bits 8) (if (fx> (fxremainder bits 8) 0) 1 0)))
         (res (make-u8vector bytes)))
    (let lp ((uint uint) (i 0))
      (if (> uint 0)
        (begin
          (u8vector-set! res i (bitwise-and uint #xff))
          (lp (arithmetic-shift uint -8)
              (fx1+ i)))
        res))))

;;; FFI
(begin-ffi (native-endianness
            &u8vector-u16-ref/native
            &u8vector-u16-set!/native
            &u8vector-s16-ref/native
            &u8vector-s16-set!/native
            &u8vector-u32-ref/native
            &u8vector-u32-set!/native
            &u8vector-s32-ref/native
            &u8vector-s32-set!/native
            &u8vector-u64-ref/native
            &u8vector-u64-set!/native
            &u8vector-s64-ref/native
            &u8vector-s64-set!/native
            &u8vector-float-ref/native
            &u8vector-float-set!/native
            &u8vector-double-ref/native
            &u8vector-double-set!/native)

  (c-declare "#include <stdint.h>")

  (define native-endianness
    (if ((c-lambda () scheme-object
              #<<END-C
#ifdef ___LITTLE_ENDIAN
___return(___TRU);
#else
___return(___FAL);
#endif
END-C
))
      'little
      'big))

  (define-c-lambda &u8vector-u16-ref/native (scheme-object int) unsigned-int16
    "uint16_t res = *(uint16_t*)(U8_DATA(___arg1) + ___arg2); ___return(res);")
  (define-c-lambda &u8vector-u16-set!/native (scheme-object int unsigned-int16) void
    "*(uint16_t*)(U8_DATA(___arg1) + ___arg2) = ___arg3; ___return;")
  (define-c-lambda &u8vector-s16-ref/native (scheme-object int) int16
    "int16_t res = *(int16_t*)(U8_DATA(___arg1) + ___arg2); ___return(res);")
  (define-c-lambda &u8vector-s16-set!/native (scheme-object int int16) void
    "*(int16_t*)(U8_DATA(___arg1) + ___arg2) = ___arg3; ___return;")

  (define-c-lambda &u8vector-u32-ref/native (scheme-object int) unsigned-int32
    "uint32_t res = *(uint32_t*)(U8_DATA(___arg1) + ___arg2); ___return(res);")
  (define-c-lambda &u8vector-u32-set!/native (scheme-object int unsigned-int32) void
    "*(uint32_t*)(U8_DATA(___arg1) + ___arg2) = ___arg3; ___return;")
  (define-c-lambda &u8vector-s32-ref/native (scheme-object int) int32
    "int32_t res = *(int32_t*)(U8_DATA(___arg1) + ___arg2); ___return(res);")
  (define-c-lambda &u8vector-s32-set!/native (scheme-object int int32) void
    "*(int32_t*)(U8_DATA(___arg1) + ___arg2) = ___arg3; ___return;")

  (define-c-lambda &u8vector-u64-ref/native (scheme-object int) unsigned-int64
    "uint64_t res = *(uint64_t*)(U8_DATA(___arg1) + ___arg2); ___return(res);")
  (define-c-lambda &u8vector-u64-set!/native (scheme-object int unsigned-int64) void
    "*(uint64_t*)(U8_DATA(___arg1) + ___arg2) = ___arg3; ___return;")
  (define-c-lambda &u8vector-s64-ref/native (scheme-object int) int64
    "int64_t res = *(int64_t*)(U8_DATA(___arg1) + ___arg2); ___return(res);")
  (define-c-lambda &u8vector-s64-set!/native (scheme-object int int64) void
    "*(int64_t*)(U8_DATA(___arg1) + ___arg2) = ___arg3; ___return;")

  (define-c-lambda &u8vector-float-ref/native (scheme-object int) float
    "float res = *(float*)(U8_DATA(___arg1) + ___arg2); ___return(res);")
  (define-c-lambda &u8vector-float-set!/native (scheme-object int float) void
    "*(float*)(U8_DATA(___arg1) + ___arg2) = ___arg3; ___return;")

  (define-c-lambda &u8vector-double-ref/native (scheme-object int) double
    "double res = *(double*)(U8_DATA(___arg1) + ___arg2); ___return(res);")
  (define-c-lambda &u8vector-double-set!/native (scheme-object int double) void
    "*(double*)(U8_DATA(___arg1) + ___arg2) = ___arg3; ___return;")
  )
