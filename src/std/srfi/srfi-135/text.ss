;;; -*- Gerbil -*-
;;; (c) vyzo at hackzen.org
;;; SRFI-135: Immutable Texts

(import :gerbil/gambit/exact
        (only-in :std/srfi/13 string-upcase string-downcase string-titlecase)
        :std/srfi/srfi-135/kernel8
        :std/srfi/srfi-135/etc
        :std/srfi/srfi-135/macros)
(export #t)
(include "text.scm")
