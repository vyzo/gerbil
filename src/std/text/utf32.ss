;;; -*- Gerbil -*-
;;; © vyzo
;;; string<->utf32 conversion

(import :gerbil/gambit/fixnum
        :std/misc/bytes
        :std/error
        :std/contract)
(export string->utf32 utf32->string)

(declare (not safe))

(def/c (string->utf32 str (endianness big) (BOM? #f))
  (@contract (string? str))
  (let (u32-set!
        (case endianness
          ((big) u32-set!/be)
          ((little) u32-set!/le)
          ((native) (&u8vector-u32-set!/native))
          (else
           (error "Bad endianness" endianness))))
    (utf32-encode str u32-set! BOM?)))

(def (utf32-encode str u32-set! BOM?)
  (if BOM?
    (let (bytes (make-u8vector (fx* 4 (fx1+ (string-length str)))))
      (u32-set! bytes 0 #x0000feff)
      (utf32-encode! str bytes 4 u32-set!))
    (let (bytes (make-u8vector (fx* 4 (string-length str))))
      (utf32-encode! str bytes 0 u32-set!))))

(def (utf32-encode! str bytes j u32-set!)
  (def end (string-length str))
  (let lp ((i 0) (j j))
    (if (fx< i end)
      (let* ((char (string-ref str i))
             (int (char->integer char)))
        (u32-set! bytes j int)
        (lp (fx1+ i) (fx+ j 4)))
      bytes)))

(def/c (utf32->string bytes (endianness big) (endianness-mandatory? #f))
  (@contract (u8vector? bytes))
  (let (u32-ref
        (case endianness
          ((big) u32-ref/be)
          ((little) u32-ref/le)
          ((native) &u8vector-u32-ref/native)
          (else
           (error "Bad endianness" endianness))))
    (utf32-decode bytes u32-ref (not endianness-mandatory?))))

(def (utf32-decode bytes u32-ref BOM?)
  (def len (u8vector-length bytes))
  (unless (fx= (fxremainder len 4) 0)
    (raise-io-error 'utf32-decode "Cannot decode UTF-32; u8vector length is not a multiple of 4" bytes))
  (if BOM?
    ;; try to read the BOM to determine endianness
    (if (fx>= len 4)
      (let ((b0 (u8vector-ref bytes 0))
            (b1 (u8vector-ref bytes 1))
            (b2 (u8vector-ref bytes 2))
            (b3 (u8vector-ref bytes 3)))
        (cond
         ((and (fx= b0 #x00) (fx= b1 #x00) (fx= b2 #xfe) (fx= b3 #xff)) ; big endian
          (utf32-decode! bytes 4 u32-ref/be))
         ((and (fx= b0 #xff) (fx= b1 #xfe) (fx= b2 #x00) (fx= b3 #x00)) ; little endian
          (utf32-decode! bytes 4 u32-ref/le))
         (else                          ; user specified endianness
          (utf32-decode! bytes 0 u32-ref))))
      "")                               ; empty
    (utf32-decode! bytes 0 u32-ref)))

(def (utf32-decode! bytes i u32-ref)
  (def end (u8vector-length bytes))
  (def str (make-string (fxquotient (fx- end i) 4)))
  (let lp ((i i) (j 0))
    (if (fx< i end)
      (let (int (u32-ref bytes i))
        (cond
         ((or (and (fixnum? int) (or (fx<= 0 int #xd7ff) (fx<= #xe000 int #xffff)))
              (<= #x010000 int #x10ffff))
          (string-set! str j (integer->char int))
          (lp (fx+ i 4) (fx1+ j)))
         (else
          ;; invalid character
          (string-set! str j #\xfffd) ; replacement character
          (lp (fx+ i 4) (fx1+ j)))))
      str)))

;;; Utilities

(def u32-ref/be
  (if (eq? native-endianness big)
    &u8vector-u32-ref/native
    (lambda (v i)
      (&u8vector-uint-ref/be v i 4))))

(def u32-ref/le
  (if (eq? native-endianness little)
    &u8vector-u32-ref/native
    (lambda (v i)
      (&u8vector-uint-ref/le v i 4))))

(def u32-set!/be
  (if (eq? native-endianness big)
    &u8vector-u32-set!/native
    (lambda (v i n)
      (&u8vector-uint-set!/be v i n 4))))

(def u32-set!/le
  (if (eq? native-endianness little)
    &u8vector-u32-set!/native
    (lambda (v i n)
      (&u8vector-uint-set!/le v i n 4))))
