(export string-test)

(import
  :std/misc/string :std/srfi/13
  :std/test :gerbil/gambit/exceptions
  :std/contract
  :std/pregexp)

(def string-test
  (test-suite "test :std/misc/string"
    (test-case "string-split-suffix"
      (check-equal? (values->list (string-split-suffix ".c" "foo.c")) ["foo" ".c"])
      (check-equal? (values->list (string-split-suffix ".c" "foo")) ["foo" ""]))
    (test-case "string-trim-suffix"
      (check-equal? (string-trim-suffix ".c" "foo.c") "foo")
      (check-equal? (string-trim-suffix ".c" "foo") "foo"))
    (test-case "string-split-eol"
      (check-equal? (values->list (string-split-eol "foo\n")) ["foo" "\n"])
      (check-equal? (values->list (string-split-eol "foo\r\n")) ["foo" "\r\n"])
      (check-equal? (values->list (string-split-eol "foo\r")) ["foo" "\r"])
      (check-equal? (values->list (string-split-eol "foo\n\n\n")) ["foo\n\n" "\n"])
      (check-equal? (values->list (string-split-eol "foo")) ["foo" ""])
      (check-equal? (string-trim-eol "foo\n") "foo")
      (check-equal? (string-trim-eol "foo\r") "foo")
      (check-equal? (string-trim-eol "foo\r\n") "foo")
      (check-equal? (string-trim-eol "foo\n\n") "foo\n")
      (check-equal? (string-trim-eol "foo\r\r") "foo\r")
      (check-equal? (string-trim-eol "foo\r\n\r\n") "foo\r\n")
      (check-equal? (string-trim-eol "foo") "foo"))
    (test-case "string-subst"
     (check-equal? (string-subst ""             ""   ""  count: 1)  "")
     (check-equal? (string-subst "abc"          "b"  "_" count: 0)  "abc")
     (check-equal? (string-subst "abc"          ""   ""  count: #f) "abc")
     (check-equal? (string-subst ""             "b"  "c" count: #f) "")
     (check-equal? (string-subst "hello, world" "l"  "_" count: 2)  "he__o, world")
     (check-equal? (string-subst "abb"          "b*" "_" count: #f) "abb")
     (check-exception
      (string-subst "abc" "b" "_" count: #t)
      contract-violation?)
     ;; empty old
     (check-equal? (string-subst ""     "" "_"  count: 1)  "_")
     (check-equal? (string-subst "a"    "" "_"  count: 1)  "_a")
     (check-equal? (string-subst "abba" "" "_"  count: 2)  "_a_bba")
     (check-equal? (string-subst "abc"  "" "_"  count: #f) "_a_b_c_")
     (check-equal? (string-subst "abc"  "" "_"  count: 3)  "_a_b_c")
     (check-equal? (string-subst "abc"  "" "_"  count: 2)  "_a_bc")
     (check-equal? (string-subst "abc"  "" "__" count: 2)  "__a__bc")
     (check-equal? (string-subst "a"    "" "_"  count: 3)  "_a_")
     ;; non-empty old
     (check-equal? (string-subst "abc"   "b"  "_" count: #f) "a_c")
     (check-equal? (string-subst "abc"   "b"  "_" count: 2)  "a_c")
     (check-equal? (string-subst "abbcb" "b"  "_" count: 2)  "a__cb")
     (check-equal? (string-subst "abbcb" "b"  "_" count: 3)  "a__c_")
     (check-equal? (string-subst "abbcb" "bb" "_" count: #f) "a_cb"))
    (test-case "string-whitespace?"
      (check-equal? (string-whitespace? "") #t)
      (check-equal? (string-whitespace? " ") #t)
      (check-equal? (string-whitespace? " \n") #t)
      (check-equal? (string-whitespace? " \n\t\r\f\v") #t)
      (check-equal? (string-whitespace? " a") #f))
    (test-case "random-string"
      (check-eq? (and (pregexp-match "^\\w+$" (random-string 100)) #t) #t)
      (check-equal? (random-string 0) "")
      (check-equal? (random-string -1) "")
      (check-equal? (string-length (random-string 5)) 5))))
