;; -*- Gerbil -*-
;;;; String utilities

(export
  string-split-prefix
  string-trim-prefix
  string-split-suffix
  string-trim-suffix
  string-split-eol
  string-trim-eol
  string-subst
  string-whitespace?
  random-string
  +cr+ +lf+ +crlf+)

(import
  (only-in :gerbil/gambit/ports write-substring write-string)
  (only-in :gerbil/gambit/random random-integer)
  :std/srfi/13
  :std/contract)

;; If the string starts with given prefix, return the end of the string after the prefix.
;; Otherwise, return the entire string. NB: Only remove the prefix once.
(def (string-trim-prefix prefix string)
  (if (string-prefix? prefix string)
    (string-drop string (string-length prefix))
    string))

;; Split a string based on the given prefix, if present.
;; Return two values:
;; - the trimmed string,
;; - the prefix (eq? to the argument) if found, or an empty string if not found
(def (string-split-prefix prefix string)
  (let ((trimmed (string-trim-prefix prefix string)))
    (if (eq? trimmed string) (values string "") (values trimmed prefix))))


;; If the string ends with given suffix, return the beginning of the string up to the suffix.
;; Otherwise, return the entire string. NB: Only remove the suffix once.
(def (string-trim-suffix suffix string)
  (if (string-suffix? suffix string)
    (string-drop-right string (string-length suffix))
    string))

;; Split a string based on the given suffix, if present.
;; Return two values:
;; - the trimmed string,
;; - the suffix (eq? to the argument) if found, or an empty string if not found
(def (string-split-suffix suffix string)
  (let ((trimmed (string-trim-suffix suffix string)))
    (if (eq? trimmed string) (values string "") (values trimmed suffix))))


;; Line endings
(define +cr+ "\r")
(define +lf+ "\n")
(define +crlf+ "\r\n")

;; TODO: do we want a parameter to list the allowed line endings in the current context?
;; a function to add the default line-ending, which would be the first in that list,
;; or maybe a separate parameter? Indeed, we can't just iterate through such a list
;; to find the longest suffix if +lf+ is in front of +crlf+ -- longer must be tested first.

;; Trim any single end-of-line marker CR, LF or CRLF at the end of the string.
;; NB: This function will only remove one end-of-line marker,
;; like the shell when processing $(subprocess output) or perl's chomp.
;; Use (string-trim-right string (char-set #\return #\newline)) to remove all of them.
(def (string-trim-eol string)
  (defrules try ()
    ((_ eol fallback) (let ((trimmed (string-trim-suffix eol string)))
                        (if (eq? trimmed string) fallback trimmed))))
  (try +crlf+ (try +lf+ (try +cr+ string)))) ;; NB: note how we try the longer +crlf+ *before* +lf+.


;; Split a string based on any end-of-line marker CR, LF or CRLF at the end of the string.
;; Return two values:
;; - the trimmed string
;; - the eol marker found, or the empty string if not found
(def (string-split-eol string)
  (defrules try ()
    ((_ eol fallback) (let ((trimmed (string-trim-suffix eol string)))
                        (if (eq? trimmed string) fallback (values trimmed eol)))))
  (try +crlf+ (try +lf+ (try +cr+ (values string "")))))


;; string-subst helper which handles the case that the argument 'old' is an empty string.
;;   new    non-empty
;;   count  non-zero, number of replacements (-1 means no limit)
(def (subst-helper-empty-old str new count)
  (declare (not safe) (fixnum))
  (def len-str (string-length str))
  (if (= count 1)
    (string-append new str)            ; add 'new' and leave procedure
    (call-with-output-string
     (lambda (port)
       (write-string new port) ; 'count' > 1, add 'new' before the first character
       (let ((stop (1- len-str))
             (count (if (or (negative? count) (> count len-str))
                      (1+ len-str) ; the maximal number of replacements is len + 1
                      count)))
         (let loop ((i 0)
                    (matches 1)) ; 1 because 'new' was already added once
           (cond
            ((= matches count)
             (write-string new port)
             (write-substring str i len-str port))
            ((= i stop)
             (unless (zero? i) (write-string new port))
             (write-char (string-ref str i) port)
             (write-string new port))
            (else
             (unless (zero? i) (write-string new port))
             (write-char (string-ref str i) port)
             (loop (1+ i) (1+ matches))))))))))


;; string-subst helper which handles the case that the argument 'old' is a non-empty string.
;;   str    non-empty
;;   old    non-empty
;;   new    can be empty
;;   count  non-zero, number of replacements (-1 means no limit)
(def (subst-helper-nonempty-old str old new count)
  (declare (not safe) (fixnum))
  (def len-str (string-length str))
  (def size-old (1- (string-length old)))
  (def size-str (1- (string-length str)))
  (call-with-output-string
   (lambda (port)
     (let loop ((i 0)                   ; position in str
                (matches 0)
                (last 0)            ; position after last match in str
                (j 0))              ; position in old
       (cond
        ((= matches count)              ; stop, limit reached
         (write-substring str i len-str port))
        ((= i size-str)                 ; stop, end of str
         (if (and (eq? (string-ref str i) (string-ref old j))
                  (= j size-old))
           (write-string new port)
           (write-substring str last len-str port)))
        (else
         (if (eq? (string-ref str i) (string-ref old j))
           (if (= j size-old)           ; match of old in str
             (begin
               (write-string new port)
               (loop (1+ i) (1+ matches) (1+ i) 0))
             (loop (1+ i) matches last (1+ j))) ; char equal, not yet a match
           (begin
             (write-substring str last (1+ i) port) ; no match, continue search
             (loop (1+ i) matches (1+ i) 0)))))))))


;; In str replace the string old with string new.
;; The procedure accepts only a fixnum or #f for count.
;;   count > 0   limit replacements
;;   count #f    no limit
;;   count <= 0  return input
;;
;; Example:
;;  (string-subst "abc" "b" "_") => "a_c"
;;  (string-subst "abc" "" "_")  => "_a_b_c_"
(def/c (string-subst str old new count: (count #f))
  (@contract (string? str)
             (string? old)
             (string? new)
             (or (not count) (fixnum? count)))
  (declare (fixnum))
  (def old-empty? (string-empty? old))
  (def new-empty? (string-empty? new))
  (def str-empty? (string-empty? str))
  (if (or (and old-empty? new-empty?)
          (and count (<= count 0)))
    str
    (let (count (if (number? count) count -1)) ; convert #f to -1
      (cond
       (old-empty? (subst-helper-empty-old str new count))
       (str-empty? str)
       (else       (subst-helper-nonempty-old str old new count))))))

;; Returns true when the string s consists only of whitespace characters.
;;
;;   " "   space
;;   "\n"  line feed
;;   "\t"  horizontal tab
;;   "\r"  carriage return
;;   "\f"  form feed
;;   "\v"  vertical tab
;;
;; Example:
;;  (string-whitespace? " \n\r \t") => #t
(def (string-whitespace? s)
  (string-every char-whitespace? s))


(def (random-word-char)
  (declare (not safe) (fixnum))
  (def n (random-integer 63))
  (integer->char
   (+ n (cond
	 ((< n 10) 48) ; 0-9
	 ((< n 36) 55) ; A-Z
	 ((< n 62) 61) ; a-z
	 (else 33))))) ; _


;; random-string returns a string consisting of regex word-boundary
;; characters [a-zA-Z0-9_]. Throws an error if len is not a fixnum.
;;
;; Example:
;;  (random-string) => "5CfMyYd2Ob"
(def/c (random-string (len 10))
  (@contract (fixnum? len))
  (declare (not safe) (fixnum))
  (if (> len 0)
    (let (str (make-string len))
      (do ((i 0 (1+ i)))
	  ((= i len))
	(string-set! str i (random-word-char)))
      str)
    ""))
