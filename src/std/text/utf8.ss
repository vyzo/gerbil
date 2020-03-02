;;; -*- Gerbil -*-
;;; (C) vyzo at hackzen.org
;;; string<->utf8 conversion without intermediate ports

(import :gerbil/gambit/bits
        :std/error
        :std/contract)
(export string->utf8 utf8->string
        utf8-encode utf8-decode
        string-utf8-length)

(declare (not safe))

(def/c (string->utf8 str (start 0) (end (string-length str)))
  (@contract (string? str)
             (and (fixnum? start) (fixnum? end)
                  (fx<= 0 start end (string-length str))))
  (utf8-encode str start end))

(def/c (string-utf8-length str (start 0) (end (string-length str)))
  (@contract (string? str)
             (and (fixnum? start) (fixnum? end)
                  (fx<= 0 start end (string-length str))))
  (utf8-encode-length str start end))

(def/c (utf8->string u8v (start 0) (end (u8vector-length u8v)))
  (@contract (u8vector? u8v)
             (and (fixnum? start) (fixnum? end)
                  (fx<= 0 start end (u8vector-length u8v))))
  (utf8-decode u8v start end))

(def (utf8-encode str start end)
  (let* ((slen (fx- end start))
         (u8vlen (##fx* slen 4))
         (u8v (make-u8vector u8vlen))
         (count (utf8-encode! str u8v start end)))
    (##u8vector-shrink! u8v count)
    u8v))

(def (utf8-encode-length str start end)
  (let lp ((i start) (r 0))
    (if (##fx< i end)
      (let* ((char (##string-ref str i))
             (clen (utf8-char-length char)))
        (lp (##fx+ i 1)
            (##fx+ r clen)))
      r)))

(def (utf8-char-length char)
  (let (c (##char->integer char))
    (cond
     ((##fx<= c #x7f)   1)
     ((##fx<= c #x7ff)  2)
     ((##fx<= c #xffff) 3)
     (else 4))))

(def (utf8-encode! str u8v start end)
  (let lp ((i start) (j 0))
    (if (##fx< i end)
      (let* ((char (##string-ref str i))
             (c (##char->integer char)))
        (cond
         ((##fx<= c #x7f)
          (##u8vector-set! u8v j c)
          (lp (##fx+ i 1) (##fx+ j 1)))
         ((##fx<= c #x7ff)
          (##u8vector-set! u8v j (##fxior #xc0 (##fxarithmetic-shift-right c 6)))
          (##u8vector-set! u8v (##fx+ j 1) (##fxior #x80 (##fxand c #x3f)))
          (lp (##fx+ i 1) (##fx+ j 2)))
         ((##fx<= c #xffff)
          (##u8vector-set! u8v j (##fxior #xe0 (##fxarithmetic-shift-right c 12)))
          (##u8vector-set! u8v (##fx+ j 1) (##fxior #x80 (##fxand (##fxarithmetic-shift-right c 6) #x3f)))
          (##u8vector-set! u8v (##fx+ j 2) (##fxior #x80 (##fxand c #x3f)))
          (lp (##fx+ i 1) (##fx+ j 3)))
         (else                          ; max char is #x10ffff
          (##u8vector-set! u8v j (##fxior #xf0 (##fxarithmetic-shift-right c 18)))
          (##u8vector-set! u8v (##fx+ j 1) (##fxior #x80 (##fxand (##fxarithmetic-shift-right c 12) #x3f)))
          (##u8vector-set! u8v (##fx+ j 2) (##fxior #x80 (##fxand (##fxarithmetic-shift-right c 6) #x3f)))
          (##u8vector-set! u8v (##fx+ j 3) (##fxior #x80 (##fxand c #x3f)))
          (lp (##fx+ i 1) (##fx+ j 4)))))
      j)))

(def (utf8-decode u8v start end)
  (let* ((u8vlen (fx- end start))
         (str (make-string u8vlen))
         (slen (utf8-decode! u8v str start end)))
    (##string-shrink! str slen)
    str))

(def (utf8-decode! u8v str start end)
  (let lp ((i start) (j 0))
    (if (##fx< i end)
      (let (byte (##u8vector-ref u8v i))
        (cond
         ((##fx<= byte #x7f)
          (let (char (##integer->char byte))
            (##string-set! str j char)
            (lp (##fx+ i 1) (##fx+ j 1))))
         ((##fx<= byte #xdf)
          (let* ((i+2 (##fx+ i 2))
                 (_ (unless (##fx<= i+2 end)
                      (raise-io-error 'utf8-decode! "incomplete character" byte)))
                 (byte2 (##u8vector-ref u8v (##fx+ i 1)))
                 (char
                  (##integer->char
                   (##fxior (##fxarithmetic-shift-left (##fxand byte #x1f) 6)
                            (##fxand byte2 #x3f)))))
            (##string-set! str j char)
            (lp i+2 (##fx+ j 1))))
         ((##fx<= byte #xef)
          (let* ((i+3 (##fx+ i 3))
                 (_ (unless (##fx<= i+3 end)
                      (raise-io-error 'utf8-decode! "incomplete character" byte)))
                 (byte2 (##u8vector-ref u8v (##fx+ i 1)))
                 (byte3 (##u8vector-ref u8v (##fx+ i 2)))
                 (char
                  (##integer->char
                   (##fxior (##fxarithmetic-shift-left (##fxand byte #x0f) 12)
                            (##fxarithmetic-shift-left (##fxand byte2 #x3f) 6)
                            (##fxand byte3 #x3f)))))
            (##string-set! str j char)
            (lp i+3 (##fx+ j 1))))
         ((##fx<= byte #xf4)
          (let* ((i+4 (##fx+ i 4))
                 (_ (unless (##fx<= i+4 end)
                      (raise-io-error 'utf8-decode! "incomplete character" byte)))
                 (byte2 (##u8vector-ref u8v (##fx+ i 1)))
                 (byte3 (##u8vector-ref u8v (##fx+ i 2)))
                 (byte4 (##u8vector-ref u8v (##fx+ i 3)))
                 (char
                  (##integer->char
                   (##fxior (##fxarithmetic-shift-left (##fxand byte #x07) 18)
                            (##fxarithmetic-shift-left (##fxand byte2 #x3f) 12)
                            (##fxarithmetic-shift-left (##fxand byte3 #x3f) 6)
                            (##fxand byte4 #x3f)))))
            (##string-set! str j char)
            (lp i+4 (##fx+ j 1))))
         (else
          (##string-set! str j #\xfffd) ; UTF-8 replacement character
          (lp (##fx+ i 1) (##fx+ j 1)))))
      j)))
