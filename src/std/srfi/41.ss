;;; -*- Gerbil -*-
;;; (c) vyzo at hackzen.org
;;; SRFI-41: streams library

(import :std/srfi/9
        :std/contract)
(export
  stream-type
  stream-lazy stream-eager stream-delay stream-force
  stream-null stream-pair? stream-null?
  stream-cons stream-car stream-cdr
  stream-lambda
  define-stream
  list->stream port->stream
  stream
  stream?
  stream->list
  stream-append stream-concat
  stream-constant
  stream-drop stream-drop-while
  stream-filter
  stream-fold
  stream-for-each
  stream-from
  stream-iterate
  stream-length
  stream-let
  stream-map
  stream-match
  stream-of
  stream-range
  stream-ref
  stream-reverse
  stream-scan
  stream-take stream-take-while
  stream-unfold stream-unfolds
  stream-zip)
(include "srfi-41.scm")
