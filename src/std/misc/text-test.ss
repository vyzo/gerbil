;;; -*- Gerbil -*-
;;; (C) vyzo at hackzen.org
;;;     belmarca
;;; :std/misc/text test

(import :std/misc/text
        :std/test
        :std/sugar
        (for-syntax :std/misc/bytes))
(export text-test)

;; results
(def run-time-result "Hello, world!")
(def expansion-time-result "FF 00 FF")
(def mixed-result (string-append run-time-result "\n"
                                 expansion-time-result))

(def text-test
  (test-suite "test :std/misc/text"
    ;; quasistring
    (test-case "Test quasistring."
      (let (res ((lambda (name) (quasistring "Hello, #{name}!")) "world"))
        (check-equal? run-time-result res)))
    (test-case "Test include-quasistring."
      (def rt-res ((lambda (name) (include-quasistring "_test/run-time.txt")) "world"))
      (check-equal? rt-res "Hello, world!\n")) ;; include-text preserves the \n
    ;; quasistring*
    (test-case "Test quasistring*."
      (let (res ((lambda (name) (quasistring* "Hello, #{name}!")) "world"))
        (check-equal? run-time-result res)))
    (test-case "Test include-quasistring*."
      (def rt-res ((lambda (name) (include-quasistring* "_test/run-time.txt")) "world"))
      (check-equal? rt-res "Hello, world!\n")
      (def et-res ((lambda (name) (include-quasistring* "_test/expansion-time.txt")) "world"))
      (check-equal? et-res "FF 00 FF\n"))))
