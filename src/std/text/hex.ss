;;; -*- Gerbil -*-
;;; (C) vyzo at hackzen.org
;;; hex encoding

(export hex-encode hexlify hex-decode unhexlify hex unhex unhex*)
(import :gerbil/gambit/fixnum
        :std/contract)

(def hexes "0123456789abcdef")

(def/c (hex-encode bytes (start 0) (end (u8vector-length bytes)))
  (@contract (u8vector? bytes)
             (and (fixnum? start) (fixnum? end) (fx<= 0 start end (u8vector-length bytes))))
  (declare (not safe))
  (let* ((len (##fx- end start))
         (str (make-string (##fx* 2 len))))
    (let lp ((n 0))
      (if (##fx< n len)
        (let* ((ix (##fx+ n start))
               (b (##u8vector-ref bytes ix))
               (off (##fxarithmetic-shift n 1)))
          (##string-set! str off (##string-ref hexes (##fxarithmetic-shift b -4)))
          (##string-set! str (##fx+ off 1) (##string-ref hexes (##fxand b #x0f)))
          (lp (##fx+ n 1)))
        str))))

(def (hex u4)
  (string-ref hexes u4))

(def unhexes
  (let (ht (make-hash-table-eq))
    (for-each (cut hash-put! ht <> <>)
              (string->list "0123456789")
              (iota 10))
    (for-each (cut hash-put! ht <> <>)
              (string->list "abcdef")
              (iota 6 10))
    (for-each (cut hash-put! ht <> <>)
              (string->list "ABCDEF")
              (iota 6 10))
    ht))

(def (unhex char)
  (hash-ref unhexes char))

(def (unhex* char)
  (hash-get unhexes char))

(def/c (hex-decode str)
  (@contract (string? str)
             (fxeven? (string-length str)))
  (declare (not safe))
  (let (len (string-length str))
    (let* ((blen (##fxquotient len 2))
           (bytes (make-u8vector blen)))
      (let lp ((n 0))
        (if (##fx< n blen)
          (let (off (##fxarithmetic-shift n 1))
            (##u8vector-set! bytes n
               (##fxior (##fxarithmetic-shift (unhex (##string-ref str off)) 4)
                        (unhex (##string-ref str (##fx+ off 1)))))
            (lp (##fx+ n 1)))
          bytes)))))

(defalias hexlify hex-encode)
(defalias unhexlify hex-decode)
