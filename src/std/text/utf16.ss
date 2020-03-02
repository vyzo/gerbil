;;; -*- Gerbil -*-
;;; © vyzo
;;; string<->utf16 conversion

(import :gerbil/gambit/fixnum
        :gerbil/gambit/bits
        :std/misc/bytes
        :std/error
        :std/contract)
(export string->utf16 utf16->string)

(declare (not safe))

(def/c (string->utf16 str (endianness big) (BOM? #f))
  (@contract (string? str))
  (let (u16-set!
        (case endianness
          ((big) u16-set!/be)
          ((little) u16-set!/le)
          ((native) &u8vector-u16-set!/native)
          (else
           (error "Bad endianness" endianness))))
  (utf16-encode str u16-set! BOM?)))

(def (utf16-encode str u16-set! BOM?)
  (if BOM?
    (let (bytes (make-u8vector (fx+ (fx* 4 (string-length str)) 2)))
      (u16-set! bytes 0 #xfeff)
      (utf16-encode! str bytes 2 u16-set!))
    (let (bytes (make-u8vector (fx* 4 (string-length str))))
      (utf16-encode! str bytes 0 u16-set!))))

(def (utf16-encode! str bytes j u16-set!)
  (def end (string-length str))
  (let lp ((i 0) (j j))
    (cond
     ((fx< i end)
      (let* ((char (string-ref str i))
             (int (char->integer char)))
        (cond
         ((and (fixnum? int) (or (fx<= 0 int #xd7ff) (fx<= #xe000 int #xffff)))
          (u16-set! bytes j int)
          (lp (fx1+ i) (fx+ j 2)))
         ((<= #x010000 int #x10ffff)
          (let* ((U (- int #x10000))
                 (W1 (fx+ (arithmetic-shift U -10) #xd800))
                 (W2 (fx+ (bitwise-and U #x03ff) #xdc00)))
            (u16-set! bytes j W1)
            (u16-set! bytes (fx+ j 2) W2)
            (lp (fx1+ i) (fx+ j 4))))
         (else
          (raise-io-error 'utf16-encode! "Illegal codepoint" char int)))))
     ((fx< j (u8vector-length bytes))
      (u8vector-shrink! bytes j)
      bytes)
     (else bytes))))

(def/c (utf16->string bytes (endianness big) (endianness-mandatory? #f))
  (@contract (u8vector? bytes))
  (let (u16-ref
        (case endianness
          ((big) u16-ref/be)
          ((little) u16-ref/le)
          ((native) &u8vector-u16-ref/native)
          (else
           (error "Bad endianness" endianness))))
    (utf16-decode bytes u16-ref (not endianness-mandatory?))))

(def (utf16-decode bytes u16-ref BOM?)
  (def len (u8vector-length bytes))
  (unless (fxeven? len)
    (raise-io-error 'utf16-decode "Cannot decode UTF-16; odd length u8vector" bytes))
  (if BOM?
    ;; try to read the BOM to determine endianness
    (if (fx>= len 2)
      (let ((b0 (u8vector-ref bytes 0))
            (b1 (u8vector-ref bytes 1)))
        (cond
         ((and (fx= b0 #xfe) (fx= b1 #xff)) ; big endian
          (utf16-decode! bytes 2 u16-ref/be))
         ((and (fx= b0 #xff) (fx= b1 #xfe)) ; little endian
          (utf16-decode! bytes 2 u16-ref/le))
         (else                          ; user specified endianness
          (utf16-decode! bytes 0 u16-ref))))
      "")                               ; empty
    (utf16-decode! bytes 0 u16-ref)))

(def (utf16-decode! bytes i u16-ref)
  (def end (u8vector-length bytes))
  (def str (make-string (fx- end i)))
  (let lp ((i i) (j 0))
    (cond
     ((fx< i end)
      (let (W (u16-ref bytes i))
        (if (or (fx<= 0 W #xd7ff) (fx<= #xe000 W #xffff))
          (let (char (integer->char W))
            (string-set! str j char)
            (lp (fx+ i 2) (fx1+ j)))
          (let (Whi (fxarithmetic-shift W -10))
            (if (fx= Whi #b110110)
              ;; high surrogate
              (let (i+2 (fx+ i 2))
                (if (fx< i+2 end)
                  (let* ((W2 (u16-ref bytes i+2))
                         (W2hi (fxarithmetic-shift W2 -10)))
                    (if (fx= W2hi #b110111)
                      (let* ((u1 (fxand W #x03ff))
                             (u2 (fxand W2 #x03ff))
                             (u* (bitwise-ior (arithmetic-shift u1 10) u2))
                             (u (+ u* #x10000))
                             (char (integer->char u)))
                        (string-set! str j char)
                        (lp (fx+ i 4) (fx1+ j)))
                      ;; invalid character
                      (begin
                        (string-set! str j #xfffd) ; replacement character
                        (lp (fx+ i 4) (fx1+ j)))))
                  (raise-io-error 'utf16-decode! "Incomplete character" W)))
              ;; invalid character
              (begin
                (string-set! str j #\xfffd) ; replacement character
                (lp (fx+ i 2) (fx1+ j))))))))
     ((fx< j (string-length str))
      (string-shrink! str j)
      str)
     (else str))))

;;; Utilities

(def u16-ref/be
  (if (eq? native-endianness big)
    &u8vector-u16-ref/native
    (lambda (v i)
      (&u8vector-uint-ref/be v i 2))))

(def u16-ref/le
  (if (eq? native-endianness little)
    &u8vector-u16-ref/native
    (lambda (v i)
      (&u8vector-uint-ref/le v i 2))))

(def u16-set!/be
  (if (eq? native-endianness big)
    &u8vector-u16-set!/native
    (lambda (v i n)
      (&u8vector-uint-set!/be v i n 2))))

(def u16-set!/le
  (if (eq? native-endianness little)
    &u8vector-u16-set!/native
    (lambda (v i n)
      (&u8vector-uint-set!/le v i n 2))))
