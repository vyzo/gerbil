# Miscellaneous

<!--
Documentation template:

## submodule
::: tip To use the bindings from this module:
``` scheme
(import :std/...)
```
:::

### function
``` scheme
(function param ...) -> ret1 | ret2 | ...

  param := param description ...
```

Function description; *param* highlighted; inline `code`

::: tip Examples:
``` scheme
> (function  ...)
ret
```
:::
-->

## Buffered channels
::: tip To use the bindings from this module:
``` scheme
(import :std/misc/channel)
```
:::

### make-channel
``` scheme
(make-channel [n = #f]) -> channel

  n := optional fixnum, number of values channel buffer can hold
```

Creates a new buffered channel, a synchronization construct useful for sending
and receiving data between producers and consumers, implicitly locking when
reading from or writing to the channel. Chaining multiple channels, one after
another, allows building computation pipelines with ease. *n* specifies how many
elements the channel buffer is allowed to hold before blocking, with `#f` never
blocking at all.

::: tip Examples:
``` scheme
> (import :std/iter :gerbil/gambit/threads)
> (def (consume ch)
    (let (val (channel-get ch))
      (unless (eof-object? val)
        (with ([src . num] val)
          (displayln "received " num " from " src)
          (consume ch)))))
> (def (produce ch count)
    (for (i (in-iota count))
      (channel-put ch (cons (current-thread)
                            (+ 10 (random-integer 90))))))
> (let* ((ch (make-channel 2))
         (consumer (spawn consume ch))
         (producers (for/collect (i (in-iota 3))
                      (spawn produce ch 3))))
    (for-each thread-join! producers)
    (channel-close ch)
    (thread-join! consumer))
received 36 from #<thread #4>
received 73 from #<thread #4>
received 69 from #<thread #4>
received 73 from #<thread #5>
received 52 from #<thread #5>
received 59 from #<thread #5>
received 69 from #<thread #6>
received 53 from #<thread #6>
received 81 from #<thread #6>
```
:::

### channel?
``` scheme
(channel? ch) -> boolean

  ch := channel to check
```

Returns `#t` if *ch* is a channel, `#f` otherwise.

::: tip Examples:
``` scheme
> (channel? (make-channel))
#t

> (make-channel 3)
#<channel #26>
> (channel-close #26)
> (channel? #26)
#t
```
:::

### channel-put
``` scheme
(channel-put ch val [timeout = #f]) -> boolean | error

  ch      := channel to write to
  val     := value to write into ch
  timeout := optional, how long to wait when channel is full
```

Writes *val* to *ch* and returns a truth value indicating whether the send was
successful or not. `channel-put` blocks when the channel's buffer is full,
waiting indefinitely for an available slot or until the optional *timeout*,
declared in seconds or as a relative time object, is reached. Sending data to an
already closed channel will signal an error.

::: tip Examples:
``` scheme
> (def ch (make-channel 3))
> (channel-put ch 'a)
#t
> (channel-put ch 'b)
#t
> (channel-put ch 'c)
#t
> (channel-put ch 'd 2)    ; buffer full, gives up after 2 seconds
#f
> (import :gerbil/gambit/threads)
> (spawn-thread (lambda () (thread-sleep! 2) (channel-get ch)))
#<thread #29>
> (channel-put ch 'e)      ; blocks until other thread retrieves value
#t
> (channel-put ch 'e)      ; blocks indefinitely, no other threads retrieve values
*** ERROR IN ##thread-deadlock-action! -- Deadlock detected
```
:::

### channel-try-put
``` scheme
(channel-try-put ch val) -> boolean | error

  ch  := channel to write to
  val := value to write into ch
```

Similar to `channel-put`, but doesn't block when the channel's buffer is full,
simply indicating success or failure via a truth value. Sending data to an
already closed channel will signal an error.

::: tip Examples:
``` scheme
> (def ch (make-channel 3))
> (channel-try-put ch 'a)
#t
> (channel-try-put ch 'b)
#t
> (channel-try-put ch 'c)
#t
> (channel-try-put ch 'd)    ; buffer full, doesn't block, gives up right away
#f

> (close-channel ch)
> (channel-try-put ch 'e)    ; channel already closed, no longer valid to right to it
error
```
:::

### channel-sync
``` scheme
(channel-sync ch val ...) -> void | error

  ch      := channel to write to
  val ... := values to send to ch
```

Forcefully writes *val ...* to *ch*, ignoring the channel's buffer limit. Useful
for sending special values that indicate a bi-directional out-of-band
communication request between consumers and producers without blocking. Sending
data to an already closed channel will signal an error.

::: tip Examples:
``` scheme
> (import :std/iter :gerbil/gambit/threads)
> (def (consume ch)
    (let loop ((i 0))
      (match (channel-get ch)
        ((eq? #!eof)
         (displayln "we're done here"))
        ((cons (quote more?) (? thread? thread))
         (displayln "received: sync request")
         (thread-send thread (if (< i 10) 'yes 'no))
         (loop i))
        ((? number? num)
         (displayln "received: " num)
         (loop (1+ i))))))
> (def (produce ch)
    (let loop ()
      (if (channel-try-put ch (random-integer 100))
        (loop)
        (begin            ; if buffer full, ask consumer whether to produce more
          (channel-sync ch (cons 'more? (current-thread)))
          (match (thread-receive)
            ('yes (loop))
            ('no  (channel-close ch)))))))
> (let* ((ch (make-channel 4))
         (producer (spawn produce ch))
         (consumer (spawn consume ch)))
    (for-each thread-join! [producer consumer]))
received: 28
received: 67
received: 79
received: 67
received: sync request    ; out-of-band answer via thread-send: 'yes
received: 21
received: 43
received: 71
received: 54
received: sync request    ; answer: 'yes
received: 29
received: 19              ; consumer processed 10 items, target reached
received: 61
received: 88
received: sync request    ; answer: no; producer closes channel, consumer shuts down
we're done here
```
:::

### channel-get
``` scheme
(channel-get ch [timeout = #f] [default = #f]) -> any | default | #!eof

  ch      := channel to read from
  timeout := optional, how long to wait when channel is empty
  default := optional, value to return when timeout reached
```

Reads a value from *ch* and returns it, or *default* if a *timeout* was set and
reached, declared in seconds or as a relative time object. `channel-get` blocks
when the channel's buffer is empty, waiting indefinitely for more data or until
the optional *timeout* is reached. Reading data from an already closed channel
is allowed, but will always return `#!eof`.

::: tip Examples:
``` scheme
> (def ch (make-channel 3))
> (for-each (cut channel-try-put ch <>) (iota 10))
> (channel-get ch)
0
> (channel-get ch 2)           ; returns right away
1
> (channel-get ch 2 'EMPTY)
2
> (channel-get ch 2)           ; channel can only hold three values, waits two seconds
#f
> (channel-get ch 2 'EMPTY)
EMPTY
> (channel-close ch)
> (channel-get ch)
#!eof
> (channel-get ch 2 'EMPTY)    ; closed channel always returns #!eof
#!eof
```
:::

### channel-try-get
``` scheme
(channel-try-get ch [default = #f]) -> any | default | #!eof

  ch      := channel to read from
  default := optional, value to return when channel empty
```

Similar to `channel-get`, but doesn't block when the channel's buffer is empty,
simply returning *default* in that case. Reading data from an already closed
channel is allowed, but will always return `#!eof`.

::: tip Examples:
``` scheme
> (def ch (make-channel 3))
> (for-each (cut channel-try-put ch <>) (string->list "abcdef"))
> (channel-try-get ch)
#\a
> (channel-try-get ch)
#\b
> (channel-try-get ch 'EMPTY)
#\c
> (channel-try-get ch 'EMPTY)    ; returns right away, no blocking occurs
EMPTY
> (channel-close ch)
> (channel-try-get ch 'EMPTY)
#!eof
```
:::

### Channel Iterator
``` scheme
(defmethod (:iter (ch channel)) (iter-channel ch)) -> iterator

  ch := channel to iterate over
```

The module defines a generic dispatch overload for buffered channels, allowing
them to be iterated just like lists or hashes. Iterating *ch* will yield values,
and block if necessary, until the channel is closed and its elements fully
consumed.

::: tip Examples:
``` scheme
> (import :std/iter :gerbil/gambit/threads)
> (def (consume ch)
    (for/fold (sum 0) (x ch)
      (+ x sum)))
> (def (produce ch count)
    (for (i (in-iota count))
      (channel-put ch (random-integer 100))))
> (let* ((ch (make-channel))
         (consumer (spawn consume ch))
         (producers (for/collect (i (in-iota 10))
                      (spawn produce ch 100))))
    (for-each thread-join! producers)
    (channel-close ch)
    (thread-join! consumer))
49644
```
:::

### channel-close
``` scheme
(channel-close ch) -> void

  ch := channel to close
```

Closes a buffered channel, forbidding write access. Consumers are still allowed
to retrieve values from such a closed channel, but once empty, it will simply
return `#!eof`.

Note: Only senders should close channels. Furthermore, it's not an error to
close a channel multiple times.

::: tip Examples:
``` scheme
> (def ch (make-channel))
> (channel-put ch 1)
#t
> (channel-close ch)
> (channel-get ch)      ; reading from a closed channel is allowed
1
> (channel-get ch)
#!eof
> (channel-put ch 2)    ; writing to a closed channel signals an error
error
```
:::

### channel-closed?
``` scheme
(channel-closed? ch) -> boolean

  ch := channel to check
```

Returns `#t` if *ch* is closed, `#f` otherwise.

::: tip Examples:
``` scheme
> (def ch (make-channel))
> (channel-closed? ch)
#f
> (channel-close ch)
> (channel-closed? ch)
#t
```
:::

### Channel Destructor
``` scheme
(defmethod {destroy <port>} channel-close)
```

The module also defines a `destroy` method for channels, so that they can be
used in `with-destroy` forms and other primitives that use the destroy idiom,
ensuring that channels will be closed even if an error is signaled somewhere
within the body.

::: tip Examples:
``` scheme
> (def ch (make-channel))
> (channel-put ch 10)
#t
> (channel-closed? ch)
#f
> (with-destroy ch
    (channel-get ch))
10
> (channel-closed? ch)
#t
```
:::


## Bytes

This library provides primitives for operating on u8vectors as well as some utility functions.

::: tip To use the bindings from this module:
``` scheme
(import :std/misc/bytes)
```
:::

### endianness
```scheme
(endianness big|little|native) -> endianness symbol

(def big 'big)
(def little 'little)
(def native 'native)
(def native-endianness ...)
```

Specifies the endianness for integer and floating point operations on u8vectors.

The supported endianness can be `big`, `little`, or `native`; `native-endianness` is bound
at runtime to the native architecture endianness.

### u8vector-s8-ref
```scheme
(u8vector-s8-ref v i) -> int

  v := u8vector
  i := integer; offset index in v
```

Retrieves the signed byte from *v* in position *i*, decoding from a 2's complement representation.

### u8vector-s8-set!
```scheme
(u8vector-s8-set! v i n) -> unspecified

  v := u8vector
  i := integer; offset index in v
  n := signed byte
```

Sets the signed byte in *v* at position *i* from the value *n*, encoding to 2's complement representation.

### u8vector-uint-ref
```scheme
(u8vector-uint-ref v i endianness size) -> exact nonnegative integer

  v          := u8vector
  i          := integer; offset index in v
  endianness := endianness symbol; the endianness of the binary representation of the integer
  size       := integer; the size of the integer in bytes

```

Retrieves an unsigned integer from its binary representation from *v*, starting at index *i*.

### u8vector-uint-set!
```scheme
(u8vector-uint-set! v i n endianness size) -> unspecified

  v          := u8vector
  i          := integer; offset index in v
  n          := exact nonnegative integer; the value to set
  endianness := endianness symbol; the endianness of the binary representation of the integer
  size       := integer; the size of the integer in bytes

```

Encodes the unsigned integer *n* in its binary representation in *v*, starting at offset *i*.

### u8vector-sint-ref
```scheme
(u8vector-sint-ref v i endianness size) -> exact integer

  v          := u8vector
  i          := integer; offset index in v
  endianness := endianness symbol; the endianness of the binary representation of the integer
  size       := integer; the size of the integer in bytes

```

Retrieves a signed integer from its binary representation from *v*, starting at index *i*.

### u8vector-sint-set!
```scheme
(u8vector-sint-set! v i n endianness size) -> unspecified

  v          := u8vector
  i          := integer; offset index in v
  n          := exact integer; the value to set
  endianness := endianness symbol; the endianness of the binary representation of the integer
  size       := integer; the size of the integer in bytes

```

Encodes the signed integer *n* in its binary representation in *v*, starting at offset *i*.

### u8vector->uint-list
``` scheme
(u8vector->uint-list v endianness size) -> list of exact nonnegative integers

  v          := u8vector
  endianness := endianness symbol; the endianness of the binary representation of each integer
  size       := integer; the size of each integer in bytes
```

Decodes a u8vector *v* into a list of exact nonnegative integers.

### uint-list->u8vector
``` scheme
(uint-list->u8vector lst endianness size) -> u8vcetor

  lst        := list of exact nonnegative integers
  endianness := endianness symbol; the endianness of the binary representation of each integer
  size       := integer; the size of each integer in bytes
```

Encodes a list of unsigned integers to a u8vector.

### u8vector->sint-list
``` scheme
(u8vector->sint-list v endianness size) -> list of exact integers

  v          := u8vector
  endianness := endianness symbol; the endianness of the binary representation of each integer
  size       := integer; the size of each integer in bytes
```

Decodes a u8vector *v* into a list of exact integers.

### sint-list->u8vector
``` scheme
(uint-list->u8vector lst endianness size) -> u8vector

  lst        := list of exact integers
  endianness := endianness symbol; the endianness of the binary representation of each integer
  size       := integer; the size of each integer in bytes
```

Encodes a list of signed integers to a u8vector.

### Operations on Machine-size Integers
``` scheme
(u8vector-u16-ref v i endianness) -> u16
(u8vector-u16-native-ref v i) -> u16
(u8vector-u16-ref-set! v i n endianness) -> unspecified
(u8vector-u16-native-set! v i n) -> unspecified

(u8vector-s16-ref v i endianness) -> s16
(u8vector-s16-native-ref v i) -> s16
(u8vector-s16-ref-set! v i n endianness) -> unspecified
(u8vector-s16-native-set! v i n) -> unspecified

(u8vector-u32-ref v i endianness) -> u32
(u8vector-u32-native-ref v i) -> u32
(u8vector-u32-ref-set! v i n endianness) -> unspecified
(u8vector-u32-native-set! v i n) -> unspecified

(u8vector-s32-ref v i endianness) -> s32
(u8vector-s32-native-ref v i) -> s32
(u8vector-s32-ref-set! v i n endianness) -> unspecified
(u8vector-s32-native-set! v i n) -> unspecified

(u8vector-u64-ref v i endianness) -> u64
(u8vector-u64-native-ref v i) -> u64
(u8vector-u64-ref-set! v i n endianness) -> unspecified
(u8vector-u64-native-set! v i n) -> unspecified

(u8vector-s64-ref v i endianness) -> s64
(u8vector-s64-native-ref v i) -> s64
(u8vector-s64-ref-set! v i n endianness) -> unspecified
(u8vector-s64-native-set! v i n) -> unspecified

```

Operations for encoding and decoding machine-sized integers.
When the endianness matches the native endianness, then a faster native implementation is used.

### Operations on Floating Point Numbers
```scheme
(u8vector-float-ref v i endianness) -> flonum
(u8vector-float-native-ref v i) -> flonum
(u8vector-float-set! v i x endianness) -> unspecified
(u8vector-float-native-set! v i x) -> unspecified

(u8vector-double-ref v i endianness) -> flonum
(u8vector-double-native-ref v i) -> flonum
(u8vector-double-set! v i x endianness) -> unspecified
(u8vector-double-native-set! v i x) -> unspecified
```

Operations for encoding and decoding floating point numbers using the IEEE-754 representation.

### u8vector-swap!
``` scheme
(u8vector-swap! v i j) -> unspecified

  v := u8vector
  i := integer element position
  j := integer element position
```

Swaps elements *i* and *j* of `u8vector` *v*.

::: tip Examples:
``` scheme
> (def u (u8vector 1 2))
> (u8vector-swap! u 0 1)
> u
#u8(2 1)
```
:::

### u8vector-reverse!
``` scheme
(u8vector-reverse! v) -> void

  v := u8vector
```

Reverses the elements of `u8vector` *v* in-place. Mutates the vector.

::: tip Examples:
``` scheme
> (def u (u8vector 1 2 3 4 5))
> (u8vector-reverse! u)
> u
#u8(5 4 3 2 1)
```
:::

### u8vector-reverse
``` scheme
(u8vector-reverse v) -> u8vector

  v := u8vector
```

Reverses the elements of `u8vector` *v*. Produces a new `u8vector`.

::: tip Examples:
``` scheme
> (def u (u8vector 1 2 3 4 5))
> (u8vector-reverse u)
#u8(5 4 3 2 1)
```
:::

### u8vector->bytestring
``` scheme
(u8vector->bytestring v (delim #\space)) -> bytestring

  v     := u8vector
  delim := char
```

Constructs a string of bytes in hexadecimal from `u8vector` *v*.

Each byte is formatted as two uppercase hex characters
and separated using the specified delimiter character; the delimiter can
be `#f` to specify simple concatenation.

::: tip Examples:
``` scheme
> (u8vector->bytestring (u8vector 255 127 11 1 0))
"FF 7F 0B 01 00"
> (displayln (u8vector->bytestring (u8vector 255 127 11 1 0)))
FF 7F 0B 01 00
> (u8vector->bytestring (u8vector 1 2 3) #f)
"010203"
```
:::

### bytestring->u8vector
``` scheme
(bytestring->u8vector bs (delim #\space)) -> u8vector

  bs    := bytestring
  delim := char
```

Constructs a `u8vector` from bytestring *bs*.

This function expects a string of bytes delimited by *delim*, which can be `#f` to indicate
no delimiter. Each byte consists of two hexadecimal characters.

::: tip Examples:
``` scheme
> (bytestring->u8vector "FF AB 00")
#u8(255 171 0)
> (u8vector->bytestring (bytestring->u8vector "FF AB 00"))
"FF AB 00"
> (string->bytes "FF AB 00")
#u8(70 70 32 65 66 32 48 48)
```
:::

### u8vector->uint
``` scheme
(u8vector->uint v (endianness big)) -> uint

  v          := u8vector
  endianness := endianness symbol
```

Decodes a u8vector as an unsigned integer.

### uint->u8vector
``` scheme
(uint->u8vector n (endianness big)) -> u8vector

  n          := exact nonnegative integer
  endianness := endianness symbol
```

Encodes an unsigned integer to its binary representation.

::: tip Examples:
``` scheme
> (u8vector->uint #u8(0 1))
1
> (u8vector->uint (make-u8vector 2 #xFF))
65535
> (u8vector->uint (make-u8vector 8 #xFF))
18446744073709551615
> (equal? (- (expt 2 64) 1) (u8vector->uint (make-u8vector 8 #xFF)))
#t
```
:::


### Aliases
The following aliases are defined, using the canonical Scheme naming of u8vectors as bytevectors.

```scheme
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

(defalias bytevector-u16-ref u8vector-u16-ref)
(defalias bytevector-u16-native-ref u8vector-u16-native-ref)
(defalias bytevector-u16-set! u8vector-u16-set!)
(defalias bytevector-u16-native-set! u8vector-u16-native-set!)

(defalias bytevector-s16-ref u8vector-s16-ref)
(defalias bytevector-s16-native-ref u8vector-s16-native-ref)
(defalias bytevector-s16-set! u8vector-s16-set!)
(defalias bytevector-s16-native-set! u8vector-s16-native-set!)

(defalias bytevector-u32-ref u8vector-u32-ref)
(defalias bytevector-u32-native-ref u8vector-u32-native-ref)
(defalias bytevector-u32-set! u8vector-u32-set!)
(defalias bytevector-u32-native-set! u8vector-u32-native-set!)

(defalias bytevector-s32-ref u8vector-s32-ref)
(defalias bytevector-s32-native-ref u8vector-s32-native-ref)
(defalias bytevector-s32-set! u8vector-s32-set!)
(defalias bytevector-s32-native-set! u8vector-s32-native-set!)

(defalias bytevector-u64-ref u8vector-u64-ref)
(defalias bytevector-u64-native-ref u8vector-u64-native-ref)
(defalias bytevector-u64-set! u8vector-u64-set!)
(defalias bytevector-u64-native-set! u8vector-u64-native-set!)

(defalias bytevector-s64-ref u8vector-s64-ref)
(defalias bytevector-s64-native-ref u8vector-s64-native-ref)
(defalias bytevector-s64-set! u8vector-s64-set!)
(defalias bytevector-s64-native-set! u8vector-s64-native-set!)

(defalias bytevector-ieee-single-ref u8vector-float-ref)
(defalias bytevector-ieee-single-set! u8vector-float-set!)
(defalias bytevector-ieee-single-native-ref u8vector-float-native-ref)
(defalias bytevector-ieee-single-native-set! u8vector-float-native-set!)

(defalias bytevector-ieee-double-ref u8vector-double-ref)
(defalias bytevector-ieee-double-set! u8vector-double-set!)
(defalias bytevector-ieee-double-native-ref u8vector-double-native-ref)
(defalias bytevector-ieee-double-native-set! u8vector-double-native-set!)

(defalias bytevector-swap! u8vector-swap!)
(defalias bytevector-reverse! u8vector-reverse!)
(defalias bytevector-reverse u8vector-reverse)
(defalias bytevector->bytestring u8vector->bytestring)
(defalias bytestring->bytevector bytestring->u8vector)
(defalias bytevector->uint u8vector->uint)
(defalias uint->bytevector uint->u8vector)
```

### Low Level Unsafe Operations

The following low level unsafe operations are also exported.

```scheme
(&u8vector-s8-ref v i) -> s8
(&u8vector-s8-set! v i n) -> unspecified

(&u8vector-uint-ref/be v i size) -> uint
(&u8vector-uint-ref/le v i size) -> uint
(&u8vector-uint-set!/be v i n size) -> unspecified
(&u8vector-uint-set!/le v i n size) -> unspecified

(&u8vector-sint-ref/be v i size) -> sint
(&u8vector-sint-ref/le v i size) -> sint
(&u8vector-sint-set!/be v i n size) -> unspecified
(&u8vector-sint-set!/le v i n size) -> unspecified

(&u8vector-u16-ref/native v i) -> u16
(&u8vector-u16-set!/native v i n) -> unspecified
(&u8vector-s16-ref/native v i) -> s16
(&u8vector-s16-set!/native v i n) -> unspecified

(&u8vector-u32-ref/native v i) -> u32
(&u8vector-u32-set!/native v i n) -> unspecified
(&u8vector-s32-ref/native v i) -> s32
(&u8vector-s32-set!/native v i n) -> unspecified

(&u8vector-u64-ref/native v i) -> u64
(&u8vector-u64-set!/native v i n) -> unspecified
(&u8vector-s64-ref/native v i) -> s64
(&u8vector-s64-set!/native v i n) -> unspecified

(&u8vector-float-ref/native v i) -> flonum
(&u8vector-float-set!/native v i x) -> unspecified
(&u8vector-double-ref/native v i) -> flonum
(&u8vector-double-set!/native v i x) -> unspecified

(&u8vector-swap! v i j) -> unspecified
```

## Asynchronous Completions
::: tip To use the bindings from this module:
``` scheme
(import :std/misc/completion)
```
:::

### make-completion
``` scheme
(make-completion) -> completion
```

Creates a new asynchronous completion, a synchronization construct which blocks
until a thread signals that its task either succeeded or failed via
`completion-post!` or `completion-error!`, respectively, notifying all waiting
threads about the result.

::: tip Examples:
``` scheme
> (import :gerbil/gambit/threads :std/iter :std/sugar)
> (def (task i c)
    (displayln i ": waiting")
    (try (displayln i ": " (completion-wait! c))
      (catch (ex) (displayln i ": " ex))
      (finally (displayln i ": exiting"))))
> (let* ((c (make-completion))
         (threads (for/collect (i (in-iota 3))
                    (spawn task i c))))
    (spawn-thread
      (lambda ()
        (displayln "error in computation, notifying all")
        (completion-error! c 'did-not-finish)))
    (for-each thread-join! threads))
0: waiting
1: waiting
2: waiting
error in computation, notifying all
0: did-not-finish
0: exiting
1: did-not-finish
1: exiting
2: did-not-finish
2: exiting
```
:::

### completion?
``` scheme
(completion? c) -> boolean

  c := completion to check
```

Returns `#t` if *c* is a completion, `#f` otherwise.

::: tip Examples:
``` scheme
> (completion? (make-completion))
#t

> (import :gerbil/gambit/threads)
> (completion? (make-condition-variable))
#f
```
:::

### completion-ready?
``` scheme
(completion-ready? c) -> boolean

  c := completion to check
```

Returns `#t` if the completion is ready, `#f` otherwise. This operation is
non-blocking.

::: tip Examples:
``` scheme
> (def c (make-completion))
> (completion-ready? c)
#f
> (completion-post! c 'DONE)
> (completion-ready? c)
#t
```
:::

### completion-wait!
``` scheme
(completion-wait! c) -> any | error

  c := completion to wait on
```

Waits on *c* until it has been posted with `completion-post!` or an error has
been signaled with `completion-error!`. If the completion was posted, the posted
value is returned. If an error was signalled, then it is raised as an exception.

::: tip Examples:
``` scheme
> (def c (make-completion))
> (spawn completion-wait! c)
#<thread #3>
> (spawn completion-wait! c)
#<thread #4>
> (spawn completion-wait! c)
#<thread #5>
> (completion-post! c 'done)    ; all waiting threads will be notified
> (map thread-dead? [#3 #4 #5])
(#t #t #t)
> (completion-wait! c)          ; already completed, not waiting
done

> (def c (make-completion))
> (spawn completion-error! c 'failure)
#<thread #8>
> (completion-wait! c)
*** ERROR IN (console)@1986.1 -- This object was raised: failure
```
:::

### completion-post!
``` scheme
(completion-post! c val) ->  void | error

  c   := completion to post
  val := result value
```

Signals to *c* that the current thread's computation is complete. All other
waiting threads will be notified and receive *val* as the result.

Calling `completion-post!` on an already completed *c* will raise an error.

::: tip Examples:
``` scheme
> (import :gerbil/gambit/threads :std/iter)
> (def (task i c)
    (displayln i ": waiting")
    (displayln i ": " (completion-wait! c)))
> (let* ((c (make-completion))
         (threads (for/collect (i (in-iota 3))
                    (spawn task i c))))
    (thread-sleep! 1)
    (displayln "main: done")
    (completion-post! c 'ok)
    (for-each thread-join! threads))
0: waiting
1: waiting
2: waiting
main: done
0: ok
1: ok
2: ok

;; Completions are expected to be posted once. The following would
;; be a race condition, either succeeding fine or raising an error:
> (let (c (make-completion))
    (spawn completion-post! c 'done)    ; silently fails in case of error
    (completion-post! c 'done)
    (completion-wait! c))
;; either of these:
*** ERROR IN (console)@2019.5 -- Completion has already been posted #<completion #26>
done
```
:::

### completion-error!
``` scheme
(completion-error! c obj) -> void | error

  c   := completion to notify
  obj := exception object to raise
```

Signals an error to *c*, with *obj* being the exception argument that's raised,
notifying all waiting threads that a problem occurred.

Calling `completion-error!` on an already completed *c* will raise an error.

::: tip Examples:
``` scheme
> (import :gerbil/gambit/threads :std/sugar)
> (let (c (make-completion))
    (spawn completion-error! c 'failure)
    (try (completion-wait! c)    ; failure is raised in all waiting threads
      (catch (ex) (display-exception ex (current-error-port)))))
This object was raised: failure
```
:::

### with-completion-error
``` scheme
(with-completion-error c body ...) -> any | error

  c        := completion to notify when error occurs
  body ... := expressions to evaluate
```

Wraps *body ...* with an exception handler that notifies *c* via
`completion-error!` if any type of error is raised within the body expressions.
Furthermore, errors will propagate upwards and need to be handled, terminating
the thread otherwise.

::: tip Examples:
``` scheme
> (import :gerbil/gambit/threads :std/sugar)
> (def (task c)
    (with-completion-error c
      (displayln (/ 7 0))    ; call completion-error! and silently terminate thread
      (completion-post! c)))
> (let (c (make-completion))
    (spawn task c)
    (try
      (completion-wait! c)
      (displayln "All done!")
      (catch (ex) (display-exception ex (current-error-port)))))
Divide by zero
(/ 7 0)
```
:::

### completion
``` scheme
(defsyntax completion)
```

Completion type for user-defined generics and destructuring.

::: tip Examples:
``` scheme
> (import :gerbil/gambit/threads)
> (def c (make-completion))
> (completion-post! c 'done)
> (with ((completion mut cond-var ready? val ex) c)
    (with-lock mut
      (cut displayln "value: " (if ready? val "not ready"))))
value: done
```
:::


## Thread Barriers
::: tip To use the bindings from this module:
``` scheme
(import :std/misc/barrier)
```
:::

### make-barrier
``` scheme
(make-barrier n) -> barrier | error

  n := thread wait limit, fixnum
```

Creates a thread barrier, a synchronization construct that blocks up to *n*
threads before it allows them to proceed. *n* needs to be a non-negative fixnum,
otherwise an error is signaled.

::: tip Examples:
``` scheme
> (import :gerbil/gambit/threads :std/iter)
> (def (thread-task b)
    (thread-sleep! (+ 2 (random-integer 3)))
    (displayln (current-thread) " completed its task. Waiting for others.")
    (barrier-post! b)
    (barrier-wait! b)
    (displayln (current-thread) " runs again."))

> (let* ((b (make-barrier 3))
         (threads (for/collect (i (in-iota 5))
                    (spawn thread-task b))))
    (for-each thread-join! threads)
    (displayln "All threads are done."))
#<thread #1> completed its task. Waiting for others.
#<thread #2> completed its task. Waiting for others.
#<thread #3> completed its task. Waiting for others.
#<thread #1> runs again.    ; barrier limit reached, notifying waiting threads
#<thread #2> runs again.
#<thread #3> runs again.
#<thread #4> completed its task. Waiting for others.
#<thread #4> runs again.    ; limit already reached, no need to wait
#<thread #5> completed its task. Waiting for others.
#<thread #5> runs again.
All threads are done.
```
:::

### barrier?
``` scheme
(barrier? b) -> boolean

  b := barrier to check
```

Returns `#t` if *b* is a barrier, `#f` otherwise.

::: tip Examples:
``` scheme
> (barrier? (make-barrier 3))
#t

(import :gerbil/gambit/threads)
> (barrier? (make-mutex 'barrier))
#f
```
:::

### barrier-wait!
``` scheme
(barrier-wait! b) -> void | error

  b := barrier to wait on
```

Waits on *b* until it has been posted *n* times (as specified on barrier
creation) with `barrier-post!` or an error has been signaled with
`barrier-error!`. Errors will propagate upwards and need to be handled.

::: tip Examples:
``` scheme
> (import :gerbil/gambit/threads :std/iter :std/format)
> (def (log msg)
    (printf "~a@~a: ~a\n" (current-thread) (time->seconds (current-time)) msg))
> (def (task b)
    (log "working")
    (thread-sleep! (random-integer 5))
    (barrier-post! b)
    (log "waiting for other threads")
    (barrier-wait! b)
    (log "done"))
> (let (b (make-barrier 3))
    (for-each thread-join! (for/collect (i (in-iota 3)) (spawn task b)))
    (barrier-wait! b)     ; barrier thread limit already reached, not waiting
    (barrier-error! b 'failure)
    (barrier-wait! b))    ; unhandled exception, terminates primordial thread
#<thread #1>@1558088315.312991:  working
#<thread #2>@1558088315.3137062: working
#<thread #3>@1558088315.3143606: working
#<thread #3>@1558088317.3152056: waiting for other threads
#<thread #1>@1558088318.313868:  waiting for other threads
#<thread #3>@1558088319.3144877: done
#<thread #1>@1558088319.314984:  done
#<thread #2>@1558088319.3154783: waiting for other threads
#<thread #2>@1558088319.3161075: done
*** ERROR IN (console)@1593.5 -- This object was raised: failure
```
:::

### barrier-post!
``` scheme
(barrier-post! b) -> void

  b := barrier to signal to
```

Signals *b* that the current thread's computation is complete. All other waiting
threads will be notified once *b*'s post limit (as specified on barrier creation)
is reached.

::: tip Examples:
``` scheme
> (import :gerbil/gambit/threads)
> (let* ((b (make-barrier 2))
         (t1 (spawn barrier-post! b))
         (t2 (spawn barrier-post! b)))
    (barrier-wait! b)    ; signaled twice, good to go
    'OK)
OK
```
:::

### barrier-error!
``` scheme
(barrier-error! b obj) -> void

  b   := barrier to signal error on
  obj := exception object to raise
```

Signals an error to *b*, with *obj* being the exception argument that's raised,
notifying all waiting threads that a problem occurred.

::: tip Examples:
``` scheme
> (import :gerbil/gambit/threads :std/sugar)
> (let* ((b (make-barrier 3))
         (t (spawn barrier-error! b 'failure)))
    (try (barrier-wait! b)    ; failure is raised in all waiting threads
      (catch (ex) (display-exception ex (current-error-port)))))
This object was raised: failure
```
:::

### with-barrier-error
``` scheme
(with-barrier-error b body ...) -> any | error

  b        := barrier to notify when error occurs
  body ... := expressions to evaluate
```

Wraps *body ...* with an exception handler that notifies *b* via
`barrier-error!` if any type of error is raised within the body expressions.
Furthermore, errors will propagate upwards and need to be handled, terminating
the thread otherwise.

::: tip Examples:
``` scheme
> (import :gerbil/gambit/threads :std/sugar)
> (def (task b)
    (with-barrier-error b
      (displayln (/ 7 0))    ; call barrier-error! and silently terminate thread
      (barrier-post! b)))
> (let* ((b (make-barrier 2))
         (t (spawn task b)))
    (try
      (barrier-wait! b)
      (displayln "All done!")
      (catch (ex) (display-exception ex (current-error-port)))))
Divide by zero
(/ 7 0)
```
:::

### barrier
``` scheme
(defsyntax barrier)
```

Barrier type for user-defined generics and destructuring.

::: tip Examples:
``` scheme
> (import :gerbil/gambit/threads)
> (with ((barrier mut cond-var count limit ex) (make-barrier 3))
    (with-lock mut
      (cut displayln "limit: " count "/" limit)))
limit: 0/3
```
:::


## Deques
::: tip To use the bindings from this module:
``` scheme
(import :std/misc/deque)
```
:::

### make-deque
``` scheme
(make-deque) -> deque
```

Creates a new empty deque, a double-ended queue, which allows adding and
removing elements on both ends without walking the whole data structure first.

::: tip Examples:
``` scheme
> (import :std/test)
> (let (dq (make-deque))
    (check (deque-empty? dq) => #t)
    (push-front! dq 10)
    (push-front! dq 20)
    (push-back!  dq 30)
    (check (deque-length dq) => 3)
    (deque->list dq))
... check (deque-empty? dq) is equal? to #t
... check (deque-length dq) is equal? to 3
(20 10 30)
```
:::

### deque?
``` scheme
(deque? dq) -> boolean

  dq := deque to check
```

Returns `#t` if *dq* is a deque, `#f` otherwise.

::: tip Examples:
``` scheme
> (let (dq (make-deque))
    (push-front! dq (make-deque))
    (and (deque? dq)
         (deque? (peek-front dq))
         (deque? (make-deque))))
#t

> (deque? (list 1 2 3))
#f
```
:::

### deque-length
``` scheme
(deque-length dq) -> fixnum

  dq := deque to inspect
```

Returns the number of elements *dq* holds.

Similar to retrieving the length of a vector, this operations is `O(1)`, since
deques always keep track of their length.

::: tip Examples:
``` scheme
> (let (dq (make-deque))
    (for-each (cut push-back! dq <>) '(A B C D E F))
    (deque-length dq))
6

> (deque-length (make-deque))
0
```
:::

### deque-empty?
``` scheme
(deque-empty? dq) -> boolean

  dq := deque to check whether empty
```

Returns `#t` if *dq* has no elements queued, `#f` otherwise.

::: tip Examples:
``` scheme
> (deque-empty? (make-deque))
#t

> (let (dq (make-deque))
    (push-back! dq (make-deque))
    (and (deque-empty? (peek-front dq))
         (deque-empty? dq)))
#f
```
:::

### push-front!
``` scheme
(push-front! dq elem) -> unspecified

  dq   := deque to push onto
  elem := element to push to dq
```

Enqueues (pushes) *elem* to the front of the *dq*. Similar to `set!`, it's
unspecified what `push-front!` returns afterwards.

::: tip Examples:
``` scheme
> (let (dq (make-deque))
    (push-front! dq 30)
    (push-front! dq 20)
    (push-front! dq 10)
    (deque->list dq))
(10 20 30)
```
:::

### push-back!
``` scheme
(push-back! dq elem) -> unspecified

  dq   := deque to push onto
  elem := element to push to dq
```

`push-back!` is similar to `push-front!`, but pushes *elem* to the back of *dq*
instead of the front.

::: tip Examples:
``` scheme
> (let (dq (make-deque))
    (push-back! dq #\a)
    (push-back! dq #\b)
    (push-back! dq #\c)
    (list->string (deque->list dq)))
"abc"
```
:::

### pop-front!
``` scheme
(pop-front! dq [default = absent-obj]) -> any | default | error

  dq      := deque to pop from
  default := optional element returned when dq is empty
```

Pops the front of *dq* and returns that value. If *dq* is empty and a default
value is supplied, then *default* is returned. Otherwise an error is raised.

::: tip Examples:
``` scheme
> (let (dq (make-deque))
    (for-each (cut push-back! dq <>) [1 2 3])
    (displayln (pop-front! dq 0))
    (displayln (pop-front! dq 0))
    (displayln (pop-front! dq 0))
    ;; would signal error without default value:
    (displayln (pop-front! dq 0)))
1
2
3
0
```
:::

### pop-back!
``` scheme
(pop-back! dq [default = absent-obj]) -> any | default | error

  dq      := deque to pop from
  default := optional element returned when dq is empty
```

`pop-back!` is similar to `pop-front!`, but pops the back of *dq* instead and
returns that value. If *dq* is empty and a default value is supplied, then
*default* is returned. Otherwise an error is raised.

::: tip Examples:
``` scheme
> (import (group-in :std iter sugar))
> (let (dq (make-deque))
    (for ((x "ABCDEF") (y (in-naturals 1)))
      (push-front! dq (cons x y)))
    (until (deque-empty? dq)
      (displayln (pop-back! dq))))
(A . 1)
(B . 2)
(C . 3)
(D . 4)
(E . 5)
(F . 6)
```
:::

### peek-front
``` scheme
(peek-front dq [default = absent-obj]) -> any | default | error

  dq      := deque to peek front
  default := optional element returned when dq is empty
```

Returns the front value of *dq* without popping it from the deque like
`pop-front!` does. If *dq* is empty and a default value is supplied, then
*default* is returned. Otherwise an error is raised.

::: tip Examples:
``` scheme
> (let (dq (make-deque))
    (push-back! dq 10)
    (push-back! dq 20)
    (push-back! dq 30)
    (peek-front dq))
10

> (import :std/sugar :std/misc/func)
> (let (dq (make-deque))
    (for-each (cut push-front! dq <>)
              (repeat random-integer 10 10))
    (displayln (deque->list dq))
    (while (odd? (peek-front dq 0))
      (pop-front! dq))
    (deque->list dq))
(3 5 5 1 0 4 5 8 6 1)
(0 4 5 8 6 1)
```
:::

### peek-back
``` scheme
(peek-back dq [default = absent-obj]) -> any | default | error

  dq      := deque to peek back
  default := optional element returned when dq is empty
```

Returns the back value of *dq* without popping it from the deque like
`pop-back!` does. If *dq* is empty and a default value is supplied, then
*default* is returned. Otherwise an error is raised.

::: tip Examples:
``` scheme
> (let (dq (make-deque))
    (push-back! dq 'A)
    (push-back! dq 'B)
    (push-back! dq 'C)
    (displayln (peek-back dq))
    (pop-front! dq)
    (displayln (peek-back dq))
    (pop-back! dq)
    (displayln (peek-back dq)))
C
C
B

> (def dq (make-deque))
> (push-back! dq "xyz")
#<deque #15>    ; unspecified, don't depend on this
> (peek-back dq 'EMPTY)
"xyz"
> (pop-front! dq)
"xyz"
> (peek-back dq 'EMPTY)
EMPTY
> (peek-back dq)
error
```
:::

### deque-&gt;list
``` scheme
(deque->list dq) -> list

  dq := deque to transform into list
```

Returns a new list of the elements queued in *dq*, in order.

::: tip Examples:
``` scheme
> (let (dq (make-deque))
    (push-back! dq #\a)
    (push-back! dq 100)
    (push-back! dq "other")
    (deque->list dq))
(#\a 100 "other")

> (import :std/srfi/1)
> (let (dq (make-deque))
    (for-each (cut push-front! dq <>) (iota 100))
    (drop (deque->list dq) 90))
(9 8 7 6 5 4 3 2 1 0)
```
:::

### deque
``` scheme
(defsyntax deque)
```

Deque type for user-defined generics and destructuring.

::: tip Examples:
``` scheme
> (let (dq (make-deque))
    (push-back! dq "first")
    (push-back! dq "second")
    (push-back! dq "third")
    (match dq
      ((deque front back length)
       (displayln "front:  " front)
       (displayln "back:   " back)
       (displayln "length: " length))))
front:  #<node #17>
back:   #<node #18>
length: 3
```
:::


## List utilities
::: tip To use the bindings from this module:
``` scheme
(import :std/misc/list)
```
:::

### alist?
``` scheme
(alist? alist) -> boolean

  alist := association list to check
```

Checks whether *alist* is a proper association list and returns a truth value
(`#t` or `#f`). *alist* needs to be finite, circular lists are not supported.

A proper association list is a list of pairs and may be of the following forms:
- `((key1 . value1) ...)`
- `((key1 value1) ...)`

::: tip Examples:
``` scheme
> (alist? '((a . 1) (b . 2) (c . 3)))
#t

> (alist? [["one" #\1] ["two" #\2] ["three" #\3]])
#t

> (alist? '((a . 1) ("two" #\2) (1 2 3 4)))
#t    ; (1 2 3 4) is equivalent to (1 . (2 3 4))

> (alist? '(a 1 b 2 c 3))
#f    ; input is a plist, see plist? function

> (alist? '())
#t    ; edge-case, just like (list? '()) => #t
```
:::

### plist?
``` scheme
(plist? plist) -> boolean

  plist := property list to check
```

Checks whether *plist* is a proper property list and returns a truth value (`#t`
or `#f`). *plist* needs to be finite, circular lists are not supported.

A proper property list is a list of alternating keys and values of the following
form: `((key1 value1 key2 value2 ...))`

::: tip Examples:
``` scheme
> (plist? '(a 1 b 2 c 3 d 4))
#t

> (plist? ["uno" [1 2 3] "dos" [4 5 6] "tres" [7 8 9]])
#t

> (plist? '((a . 1) (b . 2)))
#t    ; key1 = (a . 1), value1 = (b . 2)

> (plist? '((a . 1) (b . 2) (c . 3)))
#f    ; key2 = (c . 3), but missing value2

> (plist? [])
#t    ; edge-case, just like (list? []) => #t

```
:::

### plist-&gt;alist
``` scheme
(plist->alist plist) -> alist | error

  plist := property list to transform
```

Transforms a property list `(k1 v1 k2 v2 ...)` into an association list `((k1 . v1)
(k2 . v2)...)`. *plist* needs to be finite, circular lists are not supported.
Furthermore, an error is signaled when *plist* is a improper property list.

::: tip Examples:
``` scheme
> (plist->alist [10 "cat" 11 "dog" 12 "bird"])
((10 . "cat") (11 . "dog") (12 . "bird"))

> (plist->alist ["semicolon" #\; "comma" #\, "dot"])
error    ; key "dot" has no associated property value

> (plist->alist [])
()

```
:::

### alist-&gt;plist
``` scheme
(alist->plist alist) -> plist | error

  alist := association list to transform
```

Transforms an association list `((k1 . v1) (k2 . v2) ...)` into a property list
`(k1 v1 k2 v2 ...)`. *alist* needs to be finite, circular lists are not supported.
Furthermore, an error is signaled when *alist* is an improper association list.

::: tip Examples:
``` scheme
> (alist->plist [[1 . 10] [2 . 20] [3 . 30]])
(1 10 2 20 3 30)

> (alist->plist [["fire" #\f] ["water" #\w] ["earth" #\e]])
("fire" (#\f) "water" (#\w) "earth" (#\e))

> (alist->plist '((1 2 3) (4 5 6) (7 8 9)))
(1 (2 3) 4 (5 6) 7 (8 9))

> (alist->plist '((a) (b) (c)))
(a () b () c ())

> (alist->plist [])
()

```
:::

### length=?, length&lt;? ... length&gt;=?
``` scheme
(length=?  lst1 lst2) -> boolean
(length<?  lst1 lst2) -> boolean
(length<=? lst1 lst2) -> boolean
(length>?  lst1 lst2) -> boolean
(length>=? lst1 lst2) -> boolean

  lst1, lst2 := lists to compare
```

Compares the list lengths of both *lst1* and *lst2*, and returns a truth value
(`#t` or `#f`).

| function           | less efficient variant       |
|:-------------------|:-----------------------------|
| `(length=?  x y)`  | `(=  (length x) (length y))` |
| `(length<?  x y)`  | `(<  (length x) (length y))` |
| `(length<=? x y)`  | `(<= (length x) (length y))` |
| `(length>?  x y)`  | `(>  (length x) (length y))` |
| `(length>=? x y)`  | `(>= (length x) (length y))` |

These functions are potentially more efficient because they only need to compare
the lists up until the point where they start to differ from one another. They
will short-circuit once they encounter a difference instead of calculating both
lengths up-front.

Also, either of these two lists is allowed to be circular, but not both.

::: tip Examples:
``` scheme
> (import :std/srfi/1)
> (def small (iota 10))   ; => (0 1 ... 9)
> (def large (iota 100))  ; => (0 1 ... 99)

> (length=? small large)
#f    ; comparison stops as soon as small runs out of elements

> (length<? large (circular-list 1 2 3))
#t    ; circular list never runs out of elements

> (length>=? (circular-list 0 1) [])
#t
```
:::

### length=n?, length&lt;n? ... length&gt;=n?
``` scheme
(length=n?  lst n) -> boolean | error
(length<n?  lst n) -> boolean | error
(length<=n? lst n) -> boolean | error
(length>n?  lst n) -> boolean | error
(length>=n? lst n) -> boolean | error

  lst := list to compare
  n   := number
```

Checks how the length of *lst* compares to *n* and returns a truth value result
(`#t` or `#f`). Signals an error when n isn't a valid number.

| function            | less efficient variant |
|:--------------------|:-----------------------|
| `(length=n?  x n)`  | `(=  (length x) n)`    |
| `(length<n?  x n)`  | `(<  (length x) n)`    |
| `(length<=n? x n)`  | `(<= (length x) n)`    |
| `(length>n?  x n)`  | `(>  (length x) n)`    |
| `(length>=n? x n)`  | `(>= (length x) n)`    |

These functions are potentially more efficient because they only need to check
the list for up to *n* elements instead of calculating *lst*'s length up-front.

Also, *lst* is allowed to be circular.

::: tip Examples:
``` scheme
> (length=n? [#\a #\b #\c] 3)
#t

> (import :std/srfi/1)
> (length>=n? (circular-list 0 1) 5)
#t

> (length<n? (circular-list 1 2 3) 10000)
#f    ; circular list never runs out of elements
```
:::

### call-with-list-builder
``` scheme
(call-with-list-builder proc) -> list

  proc := procedure that takes two proc identifiers as input
```

Takes a procedure or lambda *proc* which itself takes two procedures that can have
any name but are called *put!* and *peek* here:

- *put!* will append its input element onto an internal list (and thus modifies
  it) on each invocation.
- *peek* retrieves the elements collected so far, or `[]` if *put!* is never called.

Finally, `call-with-list-builder` returns the constructed list.

::: tip Examples:
``` scheme
> (import :std/iter)
> (call-with-list-builder
    (lambda (put! peek)
      (for (x (in-range 5 10))
        (displayln (peek))
        (put! (random-integer (1+ x))))))
()           ; no prior put!
(5)
(5 6)
(5 6 2)
(5 6 2 8)    ; fifth explicit peek call
(5 6 2 8 6)  ; peek is called implicitly at the end
```
:::

### with-list-builder
``` scheme
(with-list-builder (put! [peek]) body ...) -> list

  put! := function identifier that modifies internal list
  peek := optional function identifier that retrieves internal list
```

Syntax sugar for the `call-with-list-builder` procedure, so *put!* and *peek* can
be used without wrapping them in a lambda first. `with-list-builder` returns the
internal list at the end.

::: tip Examples:
``` scheme
> (import :std/iter)
> (with-list-builder (put!)
    (for (n (in-iota 100 1))
      (let ((mod3 (zero? (modulo n 3)))
            (mod5 (zero? (modulo n 5))))
        (put! (cond ((and mod3 mod5) "fizzbuzz")
                    (mod3 "fizz")
                    (mod5 "buzz")
                    (else n))))))
(1 2 "fizz" 4 "buzz" "fizz" ... 97 98 "fizz" "buzz")
```
:::

### snoc
``` scheme
(snoc elem lst) -> list | error

  elem := element to append to lst
  lst  := proper list
```

`snoc` is similar to `cons`, but appends *elem* at the end of *lst* instead of
putting it at the front.

Different from `cons`: `snoc` will signal an error when *lst* is not a proper
list. `cons`, in contrast, constructs a pair out of these two input values.

::: tip Examples:
``` scheme
> (cons 4 [1 2 3])
(4 1 2 3)

> (snoc 4 [1 2 3])
(1 2 3 4)

> (cons 1 2)
(1 . 2)

> (snoc 1 2)
error    ; expects a list as second argument

> (snoc '(a b c) '())
((a b c))
```
:::

### append1
``` scheme
(append1 lst elem) -> list | error

  lst  := proper list
  elem := element to append to lst
```

`append1` is similar to `append`, but is constructing a proper list whereas the
latter returns an improper list when appending a non-list *elem* to *lst*.
`append` also joins two or more input lists while `append1` simply adds the
second list as-is.

Signals an error when *lst* is not a list.

::: tip Examples:
``` scheme
> (append [1 2 3] 4)
(1 2 3 . 4)

> (append1 [1 2 3] 4)
(1 2 3 4)

> (append [1 2 3] [4 5 6])
(1 2 3 4 5 6)

> (append1 [1 2 3] [4 5 6])
(1 2 3 (4 5 6))

> (append1 "raise" "error")
error    ; expects a list as first argument
```
:::

### for-each!
``` scheme
(for-each! lst proc) -> void

  lst  := proper or even improper list
  proc := procedure called for side-effects
```

`for-each!` is similar to `for-each`, but the arguments *lst* and *proc* are
swapped which allows better nesting. Another slight difference: `for-each!` even
accepts improper lists.

::: tip Examples:
``` scheme
> (def exprs [[2 + 0] [2 - 0] [0 * 2] [2 / 0] [0 / 2]])

> (for-each (match <>
              ([x (eq? /) (? zero? y)]
               (displayln "div by zero!"))
              ([x op y]
               (displayln (op x y))))
            exprs)

> (for-each! exprs
    (match <>
      ([x (eq? /) (? zero? y)]
       (displayln "div by zero!"))
      ([x op y]
       (displayln (op x y)))))

;; both print:
2
2
0
div by zero!
0

> (for-each displayln '(1 2 . 3))
error    ; list expected

> (for-each! '(1 2 . 3) displayln)
1
2        ; dotted list ending not included
```
:::

### push!
``` scheme
(push! elem lst) -> unspecified | error

  elem := element to cons onto lst
  lst  := list
```

Macro that conses *elem* onto *lst* and `set!`s *lst* accordingly. *lst* needs
to be bound beforehand or it signals an error. It's unspecified what `push!`
returns otherwise.

::: tip Examples:
``` scheme
> (def lst [])
> (push! 10 lst)
> (push! 20 lst)
> (push! 30 lst)
> lst
(30 20 10)

> (def pair [#\b . #\a])
> (push! #\c pair)
> pair
(#\c #\b . #\a)

> (push! 1 [2 3])
error    ; uses set! internally, requires valid binding
```
:::

### flatten
``` scheme
(flatten lst) -> list

  lst := proper nested list-of-lists
```

Removes all layers of nesting from *lst*, which is expected to be a proper
list-of-lists (or tree structure). It will ignore any empty lists it encounters
while traversing, not adding them to the returned flattened list.

::: tip Examples:
```scheme
> (flatten [1 [2 3] [[4 5]]])
(1 2 3 4 5)

> (flatten [1 [] [2 [3 [] 4] 5]])
(1 2 3 4 5)  ; ignores empty sublists

> (flatten '((a . 1) (b . 2) (c . 3)))
(a b c)      ; expects proper non-dotted list-of-lists
```
:::

### flatten1
``` scheme
(flatten1 lst) -> list | error

  lst := proper nested list-of-lists
```

`flatten1` is a special variant of `flatten` which will not flatten the whole
nested list-of-lists (or tree structure), but instead removes only a single layer of
nesting from *lst*.

Note: *lst* is expected to be a list of proper lists, association lists will
signal an error.

::: tip Examples:
``` scheme
> (flatten1 [1 [2 3] [[4 5]]])
(1 2 3 (4 5))

> (flatten1 [1 [] [2 [3 [] 4] 5]])
(1 2 (3 () 4) 5)

> (import :std/srfi/1)
> (map (cut iota <>) [1 2 3 4]
((0) (0 1) (0 1 2) (0 1 2 3))
> (flatten (map (cut iota <>) [1 2 3 4]))
(0 0 1 0 1 2 0 1 2 3)

> (flatten1 '((a . 1) (b . 2) (c . 3)))
error    ; expects proper non-dotted list-of-lists
```
:::

### rassoc
``` scheme
(rassoc elem alist [pred = eqv?]) -> pair | #f

  elem  := element to search for in alist
  alist := association list
  pred  := comparison predicate, optional
```

`rassoc` is similar to `assoc`, but instead of comparing *elem* with the first
element of each pair in *alist* the optional predicate *pred* (which defaults to
`eqv?`) will compare with the pair's second element.

Returns the first pair in *alist* whose `cdr` satisfies the predicate *pred*, or `#f`
otherwise.

::: tip Examples:
``` scheme
> (rassoc 2 '((a . 1) (b . 2) (c . 2) (d . 1)))
(b . 2)

> (rassoc "a" '((1 . "a") (2 . "b")))
#f       ; eqv? is used by default

> (rassoc "a" '((1 . "a") (2 . "b")) string=?)
(1 . "a")

> (rassoc '(5 6) '((a 1 2) (b 3 4) (c 5 6)) equal?)
(c 5 6)  ; equivalent to '(c . (5 6))
```
:::

### when-list-or-empty
``` scheme
(when-list-or-empty lst body ...) -> body ... | []

  lst := value or list on which expansion depends
```

Macro which expands to *body* expressions only if *lst* is a non-empty list,
otherwise an empty list is returned.

::: tip Examples:
``` scheme
> (let (nums [1 2 3])
    (when-list-or-empty nums
      (cdr nums)))
(2 3)

> (when-list-or-empty []
    (cons "never" "expanded"))
()
```
:::

### slice
``` scheme
(slice lst start [limit = #f]) -> list

  lst   := proper list
  start := start index
  limit := number of items to take from lst
```

Returns a list from `lst`, starting from the left at `start`,
containing `limit` elements.

::: tip Examples:
``` scheme
> (slice [1 2 3 4] 2)
(3 4)

> (slice [1 2 3 4] 2 1)
(3)
```
:::

### slice-right
``` scheme
(slice-right lst start [limit = #f]) -> list

  lst   := proper list
  start := start index from the right of lst
  limit := number of items to take from lst
```

Returns a list from `lst`, starting from the right at `start`,
containing `limit` elements.

::: tip Examples:
``` scheme
> (slice-right [1 2 3 4] 2)
(1 2)

> (slice-right [1 2 3 4] 2 1)
(2)
```
:::

### slice!
``` scheme
(slice! lst start [limit = #f]) -> list

  lst   := proper list
  start := start index
  limit := number of items to take from lst
```

Returns a sublist by potentially updating the input list `lst`.
Starting from the left at `start`, containing `limit` elements.

::: tip Examples:
``` scheme
> (def lst [1 2 3 4 5])
> (slice! lst 2 2)
(3 4)
```
:::

### slice-right!
``` scheme
(slice-right! lst start [limit = #f]) -> list

  lst   := proper list
  start := start index from the right of lst
  limit := number of items to take from lst
```

Returns a sublist by potentially updating the input list `lst`.
Starting from the right at `start`, containing `limit` elements.

::: tip Examples:
``` scheme
> (def lst [1 2 3 4 5])
> (slice-right! lst 2 2)
(2 3)
```
:::

### butlast
``` scheme
(butlast lst) -> list

  lst   := proper list
```

`butlast` returns a copy of the proper list `lst`, except the last element.
When `lst` is empty, `lst` is returned as it is.

::: tip Examples:
``` scheme
> (butlast [1 2 3])
(1 2)

> (butlast [])
()
```
:::

### split
``` scheme
(split lst proc [limit = #f]) -> list

  lst   := proper list
  stop  := value or unary procedure
  limit := optional, split the list only limit times
```
split the list `lst` into a list-of-lists using the value or
unary procedure `stop`. If limit is set, split the list only limit times.

::: tip Examples:
``` scheme
(split '(1 2 "hi" 3 4) string?)
> ((1 2) (3 4))

(split [1 2 0 3 4 0 5 6] 0 1)
> ((1 2) (3 4 0 5 6))

(split [] number?)
> ()
```
:::

### group
``` scheme
(group lst [test = equal?]) -> list

  lst  := proper list
  test := optional, binary predicate
```
group consecutive elements of the list `lst` into a list-of-lists.

::: tip Examples:
``` scheme
(group [1 2 2 3 1 1])
> ((1) (2 2) (3) (1 1))

(import :std/sort)
(group (sort [1 2 2 3 1 1] <) eqv?)
> ((1 1 1) (2 2) (3))
```
:::

## LRU caches
::: tip To use the bindings from this module:
``` scheme
(import :std/misc/lru)
```
:::

### make-lru-cache
``` scheme
(make-lru-cache cap) -> lru-cache | error

  cap := max capacity of cache, fixnum
```

Creates a new empty Least Recently Used (LRU) cache, a cache replacement data
structure, which tracks element usage and drops seldom used ones when full to
make room for new elements. *cap* is the capacity, i.e., the number of elements
the cache can hold before purging older entries. *cap* needs to be at least 1,
otherwise an error is signaled.

::: tip Examples:
``` scheme
> (def lru (make-lru-cache 3))
> (lru-cache-put! lru 'a "heavy-load-01")
> (lru-cache-put! lru 'b "heavy-load-02")
> (lru-cache-put! lru 'c "heavy-load-03")
> (lru-cache-put! lru 'd "heavy-load-04")
> (lru-cache-put! lru 'e "heavy-load-05")
> (lru-cache-size lru)
3                  ; cache full, older entries are eviced first:
> (lru-cache->list lru)
((e . "heavy-load-05") (d . "heavy-load-04") (c . "heavy-load-03"))
> (lru-cache-get lru 'c)
"heavy-load-03"    ; cache hit, bring to front:
> (lru-cache->list lru)
((c . "heavy-load-03") (e . "heavy-load-05") (d . "heavy-load-04"))

> (import :std/iter)
> (for ((values key load) lru)
    (displayln "key: " key ", load: " load))
key: c, load: heavy-load-03
key: e, load: heavy-load-05
key: d, load: heavy-load-04
```
:::

### lru-cache?
``` scheme
(lru-cache? lru) -> boolean

  lru := lru-cache to check
```

Returns `#t` if *lru* is an LRU cache, `#f` otherwise.

::: tip Examples:
``` scheme
> (lru-cache? (make-lru-cache 25))
#t
```
:::

### lru-cache-size
``` scheme
(lru-cache-size lru) -> fixnum

  lru := lru-cache to check
```

Returns the current size (i.e., the number of elements the LRU cache holds, not
the capacity) of *lru*.

::: tip Examples:
``` scheme
> (let (lru (make-lru-cache 3))
    (lru-cache-put! lru 1 #x01)
    (lru-cache-put! lru 2 #x02)
    (lru-cache-size lru))
2

> (lru-cache-size (make-lru-cache 1000))
0
```
:::

### lru-cache-capacity
``` scheme
(lru-cache-capacity lru) -> fixnum

  lru := lru-cache to check
```

Returns the maximum number of elements *lru* can hold.

::: tip Examples:
``` scheme
> (let (lru (make-lru-cache 3))
    (lru-cache-put! lru 1 #x01)
    (lru-cache-put! lru 2 #x02)
    (lru-cache-capacity lru))
3

> (lru-cache-capacity (make-lru-cache 1000))
1000
```
:::

### lru-cache-put!
``` scheme
(lru-cache-put! lru key val) -> void

  lru      := lru-cache
  key, val := key-value association to insert into lru
```

Puts an association of *key* to *val* into *lru*, in the queue head position to
be precise. If the cache is full, then the tail of the LRU queue (i.e., the
value least recently used) is dropped from the cache.

::: tip Examples:
``` scheme
> (defstruct resource (raw-data))
> (make-lru-cache 3)
#<lru-cache #35>
> (lru-cache-put! #35 1 (make-resource 'HUGE))
> (lru-cache-put! #35 2 (make-resource 'SMALL))
> (lru-cache-put! #35 3 (make-resource 'LARGE))
> (lru-cache->list #35)
((3 . #<resource #36>) (2 . #<resource #37>) (1 . #<resource #38>))
> (lru-cache-put! #35 4 'non-resource)    ; cache is full, evict old element
> (lru-cache->list #35)
((4 . non-resource) (3 . #<resource #36>) (2 . #<resource #37>))
> (resource-raw-data #38)
HUGE
```
:::

### lru-cache-remove!
``` scheme
(lru-cache-remove! lru key) -> void

  lru := lru-cache to remove from
  key := key to look up
```

Removes the association of *key* from *lru*, making room for a new element in
the lru cache.

::: tip Examples:
``` scheme
> (make-lru-cache 3)
#<lru-cache #39>
> (lru-cache-put! #39 1 "this")
> (lru-cache-put! #39 1 "that")    ; same key, simply updated
> (lru-cache->list #39)
((1 . "that"))
> (lru-cache-remove! #39 1)
> (lru-cache->list #39)
()
```
:::

### lru-cache-ref
``` scheme
(lru-cache-ref lru key [default = absent-obj]) -> any | default | error

  lru     := lru-cache to access
  key     := key to look up
  default := optional element returned when key can't be found
```

Returns the association of *key* in *lru*, and promotes the node to the head of
the LRU queue. If there is no association, then *default* is returned. If the
default is omitted, then an error is raised.

::: tip Examples:
``` scheme
> (let (lru (make-lru-cache 3))
    (lru-cache-put! lru 'a "file-a")
    (lru-cache-put! lru 'b "file-b")
    (lru-cache-put! lru 'c "file-c")
    (displayln (lru-cache->list lru))
    (displayln (lru-cache-ref lru 'b 'NONE))
    (displayln (lru-cache->list lru))
    (lru-cache-ref lru 'd 'NONE))
((c . file-c) (b . file-b) (a . file-a))
file-b
((b . file-b) (c . file-c) (a . file-a))
NONE
```
:::

### lru-cache-get
``` scheme
(lru-cache-ref lru key) -> any | #f

  lru := lru-cache to access
  key := key to look up
```

Same as `(lru-cache-ref lru key #f)`.

::: tip Examples:
``` scheme
> (lru-cache-get (make-lru-cache 3) 'not-in-here)
#f
```
:::

### lru-cache-flush!
``` scheme
(lru-cache-flush! lru) -> lru-cache

  lru := lru-cache to clear
```

Removes all elements from *lru* and returns the empty LRU cache. The capacity
remains unchanged.

::: tip Examples:
``` scheme
> (let (lru (make-lru-cache 100))
    (lru-cache-put! lru "first"  '1st)
    (lru-cache-put! lru "second" '2nd)
    (lru-cache-put! lru "third"  '3rd)
    (displayln (lru-cache-size lru) " " (lru-cache-capacity lru))
    (displayln (lru-cache-flush! lru))
    (displayln (lru-cache-size lru) " " (lru-cache-capacity lru)))
3 100
#<lru-cache #12>
0 100
```
:::

### lru-cache-for-each
``` scheme
(lru-cache-for-each proc lru) -> void

  proc := procedure to be called for each key-value pair in lru
  lru  := lru-cache
```

Applies `(proc key val)` for every key-value association in *lru*, in Most
Recently Used (MRU) order. Isn't returning anything, executed for its side
effects.

::: tip Examples:
``` scheme
> (make-lru-cache 3)
#<lru-cache #43>
> (for-each (lambda (x) (lru-cache-put! #43 x (* x x))) [1 2 3 4 5])
> (lru-cache-for-each (lambda (k v) (displayln k " " v)) #43)
5 25
4 16
3 9
```
:::

### lru-cache-walk
``` scheme
(lru-cache-walk proc lru) -> void

  proc := procedure to be called for each key-value pair in lru
  lru  := lru cache
```

Same as `(lru-cache-for-each proc lru)`.

### lru-cache-fold
``` scheme
(lru-cache-fold proc init lru) -> any

  proc := procedure to be called for each key-value pair in lru
  init := initial value
  lru  := lru-cache
```

Folds *lru* in Most Recently Used (MRU) order.

*proc*'s signature is expected to look like this: `(proc key val
prev-intermediate) -> next-intermediate)`. `lru-cache-fold` returns the last
*next-intermediate* value produced by *proc*. Furthermore, *prev-intermediate*
will be set to *init* at the beginning.

::: tip Examples:
``` scheme
> (let (lru (make-lru-cache 3))
    (lru-cache-put! lru 'a "creatures")
    (lru-cache-put! lru 'b "fluffy")
    (lru-cache-put! lru 'c "are")
    (lru-cache-fold (lambda (k v i) (string-append i " " v))
                    "gerbils" lru))
"gerbils are fluffy creatures"
```
:::

### lru-cache-foldr
``` scheme
(lru-cache-foldr proc init lru) -> any

  proc := procedure to be called for each key-value pair in lru
  init := initial value
  lru  := lru-cache
```

Where `lru-cache-fold` folds in Most Recently Used (MRU) order,
`lru-cache-foldr` folds *lru* in Least Recently Used (LRU) order.

::: tip Examples:
``` scheme
> (let (lru (make-lru-cache 5))
    (lru-cache-put! lru 'a (iota 5))
    (lru-cache-put! lru 'b (iota 4))
    (lru-cache-put! lru 'c (iota 3))
    (lru-cache-fold (lambda (k v i) (cons v i)) [] lru))
((0 1 2 3 4) (0 1 2 3) (0 1 2))
```
:::

### lru-cache-&gt;list
``` scheme
(lru-cache->list lru) -> alist

  lru := lru-cache
```

Returns an alist of key-value associations in *lru*, in Most Recently Used (MRU)
order.

::: tip Examples:
``` scheme
> (import :std/srfi/14)
> (make-lru-cache 10)
#<lru-cache #47>
> (for-each (cut lru-cache-put! #47 <> <>) (iota 10) (char-set->list char-set:letter))
> (lru-cache->list #47)
((9 . #\J)
 (8 . #\I)
 (7 . #\H)
 (6 . #\G)
 (5 . #\F)
 (4 . #\E)
 (3 . #\D)
 (2 . #\C)
 (1 . #\B)
 (0 . #\A))
```
:::

### in-lru-cache
``` scheme
(in-lru-cache lru) -> iterator

  lru := lru-cache to iterate over
```

Creates an iterator over *lru*, yielding key-value values in Most Recently Used
(MRU) order.

::: tip Examples:
``` scheme
> (import :std/iter)
> (let (lru (make-lru-cache 3))
    (lru-cache-put! lru 1 #\a)
    (lru-cache-put! lru 2 #\b)
    (lru-cache-put! lru 3 #\c)
    (for ((values k v) (in-lru-cache lru))    ; or short: (for ((values k v) lru) ...)
      (displayln k " -> " v)))
3 -> c
2 -> b
1 -> a
```
:::

### in-lru-cache-keys
``` scheme
(in-lru-cache-keys lru) -> iterator

  lru := lru-cache to iterate over
```

Creates an iterator over *lru*, yielding keys in Most Recently Used (MRU) order.

::: tip Examples:
``` scheme
> (import :std/iter)
> (let (lru (make-lru-cache 3))
    (lru-cache-put! lru 1 #\a)
    (lru-cache-put! lru 2 #\b)
    (lru-cache-put! lru 3 #\c)
    (for (x (in-lru-cache-keys lru))
      (displayln x)))
3
2
1
```
:::

### in-lru-cache-values
``` scheme
(in-lru-cache-values lru) -> iterator

  lru := lru-cache to iterate over
```

Creates an iterator over *lru*, yielding values in Most Recently Used (MRU) order.

::: tip Examples:
``` scheme
> (import :std/iter)
> (let (lru (make-lru-cache 3))
    (lru-cache-put! lru 1 #\a)
    (lru-cache-put! lru 2 #\b)
    (lru-cache-put! lru 3 #\c)
    (for (x (in-lru-cache-values lru))
      (displayln x)))
c
b
a
```
:::

### lru-cache
``` scheme
(defsyntax lru-cache)
```

LRU cache type for user-defined generics and destructuring.

::: tip Examples:
``` scheme
;; possible lru-cache iterator implementation:
(defmethod (:iter (lru lru-cache))
  (in-lru-cache lru))

(def (in-lru-cache lru)
  (def (iterate)
    (lru-cache-for-each yield lru))
  (in-coroutine iterate))
```
:::


## Port utilities
::: tip To use the bindings from this module:
``` scheme
(import :std/misc/ports)
```
:::

### copy-port
``` scheme
(copy-port in out) -> void | error

  in  := input port to read from
  out := output port to write to
```

Copy all data from port *in* to port *out*. Signals an error when *in* and *out*
aren't satisfying `input-port?` and `output-port?`, respectively.

::: tip Examples:
``` scheme
> (def nums (string-join (map number->string [1 2 3 4 5]) "\n" 'suffix))
> (call-with-output-file "~/testing/nums.txt"
    (lambda (out)
      (call-with-input-string nums
        (lambda (in) (copy-port in out)))))

$ cat ~/testing/nums.txt    ; unix-like command-line
1
2
3
4
5

> (copy-port (current-input-port) (current-output-port))
hello,
hello,       ; duplicates what you type at the REPL
everyone!
everyone!    ; quit with Ctrl-D
```
:::

### read-all-as-string
``` scheme
(read-all-as-string in) -> string | error

  in := input port to read from
```

Reads all the contents of port *in*, returning a single string including all
newline characters. Signals an error when *in* can't be read.

::: tip Examples:
``` scheme
> (import :std/srfi/13)
> (with-input-from-file "~/dev/gerbil/CHANGELOG.md"
    (lambda ()
      (string-take (read-all-as-string (current-input-port)) 80)))
"### 2-9-2019: Gerbil-v0.15.1\n\nPatch release to support Gambit v4.9.3\n\nDetails:\n-"
```
:::

### read-all-as-lines
``` scheme
(read-all-as-lines in [separator: #\newline] [include-separator?: #f]) -> list | error

  in                 := input port to read from
  separator          := character to consider line ending
  include-separator? := truth value, whether to include separator char in results
```

Reads all the contents of port *in* as a list of strings. The optional separator
related keyword parameters specify what is considered a line ending and whether
to include these separator characters in the line strings. Signals an error when
*in* can't be read.

::: tip Examples:
``` scheme
> (import :std/srfi/1)
> (take (call-with-input-file "~/dev/gerbil/README.md" read-all-as-lines) 4)
("# Gerbil Scheme"
 ""
 "Gerbil is an opinionated dialect of Scheme designed for Systems Programming,"
 "with a state of the art macro and module system on top of the Gambit runtime.")

> (with-input-from-string "aa:bb:cc:dd::ff"
    (lambda () (read-all-as-lines (current-input-port) separator: #\:)))
("aa" "bb" "cc" "dd" "" "ff")
```
:::

### read-file-string
``` scheme
(read-file-string path) -> string | error

  path := path to file to read contents from
```

Reads contents of the file at *path*, returning a single string including all
newline characters. Signals an error when *path* can't be read.

Note: There is another optional *settings* keyword parameter not shown above,
but it's not terribly interesting for this file reading procedure. Check section
`17.7.1 Filesystem devices` of the Gambit Manual if you want to know more.

::: tip Examples:
``` scheme
$ cat ~/testing/nums.txt    ; unix-like command-line
1
2
3
4
5

(map string->number
     (string-split (read-file-string "~/testing/nums.txt") #\newline))
(1 2 3 4 5)
```
:::

### read-file-lines
``` scheme
(read-file-lines path) -> list | error

  path := path to file to read contents from
```

Reads all lines of the file at *path* as a list of strings. Signals an error
when *path* can't be read.

Note: There is another optional *settings* keyword parameter not shown above,
but it's not terribly interesting for this file reading procedure. Check section
`17.7.1 Filesystem devices` of the Gambit Manual if you want to know more.

::: tip Examples:
``` scheme
$ cat ~/testing/nums.txt    ; unix-like command-line
1
2
3
4
5

> (read-file-lines "~/testing/nums.txt")
("1" "2" "3" "4" "5")

;; Advent of code 2018, problem 01a: Sum a file of around 1000 exact integer values.
$ head -n5 ~/dev/aoc18/01/input.txt
+12
-13
+17
+17
-10

> (apply + (map string->number (read-file-lines "~/dev/aoc18/01/input.txt")))
508
```
:::

### read-all-as-u8vector
``` scheme
(read-all-as-u8vector in (bufsize 8192)) -> u8vector | error

  in      := input port to read from
  bufsize := buffer size, defaults to 8192 bytes
```

Reads all the contents of port *in*, returning a single u8vector. Signals
an error when *in* can't be read.

::: tip Examples:
``` scheme
> (def u8 (call-with-input-file "/path/to/file" read-all-as-u8vector))
> (u8vector-length u8)
98526
```
:::

### read-file-u8vector
``` scheme
(read-file-u8vector path settings: [] bufsize: 8192) -> u8vector | error

  path     := path to file to read contents from
  settings := port settings, defaults to the empty list
  bufsize  := buffer size, defaults to 8192 bytes
```

Reads contents of the file at *path*, returning a single u8vector. Signals
an error when *path* can't be read.

Check section `17.7.1 Filesystem devices` of the Gambit Manual if you want
to know more about the *settings* parameter.

::: tip Examples:
``` scheme
> (def u8 (read-file-u8vector "/path/to/file" bufsize: 1024))
> (u8vector-length u8)
98526
```
:::

### write-file-string
``` scheme
(write-file-string file string settings: [] newline-ending: #t) -> void | error

  file           := the file to be written to
  string         := the string to write
  settings       := Gambit path-settings (default [])
  newline-ending := append newline if last character is not a newline (default #t)
```

Write string to file using the `display` procedure. Check section
[17.7.1 Filesystem devices](http://www.iro.umontreal.ca/~gambit/doc/gambit.html#Filesystem-devices)
of the Gambit Manual if you want to know more about the `settings` parameter.

::: tip Examples:
``` scheme
;; write "Hello, world!\n" to /tmp/foo.txt (may overwrite an existing file)
(write-file-string "/tmp/foo.txt" "Hello, world!")  ; \n is appended automatically

;; by using a path-setting we can append a string to an existing file
(write-file-string "/tmp/foo.txt" "hi" settings: [append: #t])

;; the file content is now: "Hello, world!\nhi\n"

;; let's append another string without auto-enforcement of a newline ending
(write-file-string "/tmp/foo.txt" "ho" settings: [append: #t] newline-ending: #f)

;; the final file content is: "Hello, world!\nhi\nho"  ; no trail newline character
```
:::

### write-file-lines
``` scheme
(write-file-lines file list settings: [] newline-ending: #t) -> void | error

  file           := the file to be written to
  list           := list of strings to write
  settings       := Gambit path-settings (default [])
  newline-ending := append newline if last character is not a newline (default #t)
```

Write every entry of the list as newline separated line to file using
the `display`procedure. Check section
[17.7.1 Filesystem devices](http://www.iro.umontreal.ca/~gambit/doc/gambit.html#Filesystem-devices)
of the Gambit Manual if you want to know more about the `settings` parameter.

::: tip Examples:
``` scheme
(write-file-lines "/tmp/foo.txt" ["foo" "bar"])

$ cat /tmp/foo.txt    ; unix-like command-line
foo
bar
```
:::

### Port Destructor
``` scheme
(defmethod {destroy <port>} close-port)
```

The module also defines a `destroy` method for ports, so that they can be used
in `with-destroy` forms and other primitives that use the destroy idiom,
ensuring that ports will be closed even if an error is signaled somewhere within
the body.

::: tip Examples:
``` scheme
> (define (for-each-dir-entry dir proc)
    (let ((dir-port (open-directory dir)))
      (let loop ()
        (let ((file (read dir-port)))
          (if (eof-object? file)
              (close-port dir-port)
              (begin
                (proc file)
                (loop)))))))

;; could also be written like this utilizing with-destroy:
> (import :std/sugar)
> (define (for-each-dir-entry dir proc)
    (let ((dir-port (open-directory dir)))
      (with-destroy dir-port
        ;; dir-port will be closed upon exiting this scope
        (let loop ((file (read dir-port)))
          (unless (eof-object? file)
            (proc file)
            (loop (read dir-port)))))))

> (for-each-dir-entry "/home/username" displayln)
dev
downloads
videos
documents
desktop
pictures
music
testing
```
:::


## Priority Queues
::: tip To use the bindings from this module:
``` scheme
(import :std/misc/pqueue)
```
:::

### make-pqueue
``` scheme
(make-pqueue prio [cmp = <] [capacity = 15]) -> pqueue

  prio     := function returning priority of elements
  cmp      := optional heap comparison function, min-heap by default
  capacity := optional initial size
```

Creates a new empty priority queue, a data structure similar to a simple queue,
but extended to take the associated priority value of an element into account
when pushing, popping and peeking elements.

- *prio* is a function returning the real priority of an element. It is utilized
  to determine the insert position whenever some element is about to be pushed
  onto the priority queue.
- *cmp*, a comparison function, is used to order the elements based on their
  priority, defaulting to `<`.
- *capacity* is the number of elements the pqueue can hold before it needs to
  resize itself.

::: tip Examples:
For example, let's assume we always want to retrieve the longest string
currently within our queue. This could be achieved with `string-length` as our
priority function and ordering these lengths via `>`:
``` scheme
> (def pq (make-pqueue string-length >))
> (pqueue-push! pq "shortest")
> (pqueue-push! pq "very, very, long")
> (pqueue-push! pq "medium length")
> (pqueue-peek pq)
"very, very, long"
> (pqueue-pop! pq)
"very, very, long"
> (pqueue-peek pq)
"medium length"
```
:::

### pqueue?
``` scheme
(pqueue? pq) -> boolean

  pq := priority queue to check
```

Returns `#t` if *pq* is a priority queue, `#f` otherwise.

::: tip Examples:
``` scheme
> (let (pq (make-pqueue identity))
    (when (pqueue? pq)
      (pqueue-push! pq 1000)
      (pqueue-push! pq 100)
      (pqueue-push! pq 10)
      (pqueue-peek pq)))
10

> (import :std/misc/queue)
> (pqueue? (make-queue))
#f
```
:::

### pqueue-size
``` scheme
(pqueue-size pq) -> fixnum

  pq := priority queue to inspect
```

Returns the number of elements queued in *pq*.

This operation is `O(1)`, since priority queues always keep track of their size.

::: tip Examples:
``` scheme
> (let (pq (make-pqueue char->integer))
    (string-for-each (cut pqueue-push! pq <>) "ABCDEF")
    (pqueue-size pq))
6
```
:::

### pqueue-empty?
``` scheme
(pqueue-empty? pq) -> boolean

  pq := priority queue to check
```

Returns `#t` if *pq* has no elements queued, `#f` otherwise.

::: tip Examples:
``` scheme
> (pqueue-empty? (make-pqueue identity < 1000))
#t

> (make-pqueue identity)
#<pqueue #21>
> (pqueue-push! #21 1)
> (pqueue-push! #21 3)
> (pqueue-push! #21 5)
> (pqueue-empty? #21)
#f
```
:::

### pqueue-push!
``` scheme
(pqueue-push! pq elem) -> unspecified

  pq   := priority queue to push onto
  elem := element to push to pq
```

Enqueues *elem* in *pq*. The insert position depends on the priority and
comparison functions specified in `make-pqueue`. Similar to `set!`, it's
unspecified what `pqueue-push!` returns afterwards.

::: tip Examples:
``` scheme
> (defstruct city (name population))
> (def cities [(make-city "Salto" 104028)
               (make-city "Санкт-Петербург" 4879566)
               (make-city "Qaqortoq" 3089)
               (make-city "አዲስ ፡ አበባ" 3352000)
               (make-city "Jayapura" 315872)
               (make-city "香港" 7448900)])
> (let (pq (make-pqueue city-population))
    (for-each (cut pqueue-push! pq <>) cities)
    (city-name (pqueue-peek pq)))
"Qaqortoq"
```
:::

### pqueue-pop!
``` scheme
(pqueue-pop! pq [default = absent-obj]) -> any | default | error

  pq      := priority queue to pop from
  default := optional element returned when pq is empty
```

Pops the next value in *pq* and returns it. Which element gets popped depends on
the priority and comparison function specified in `make-pqueue`. If *pq* is
empty and a default value is supplied, then *default* is returned. Otherwise an
error is raised.

::: tip Examples:
``` scheme
> (import :std/sugar)
> (let (pq (make-pqueue values))
    (for-each (cut pqueue-push! pq <>) [10 1 20 2 30 3])
    (until (pqueue-empty? pq)
      (displayln (pqueue-pop! pq)))
    ;; would signal error without default value:
    (pqueue-pop! pq 100))
1
2
3
10
20
30
100
```
:::

### pqueue-peek
``` scheme
(pqueue-peek pq) -> any | error

  pq := priority queue to peek
```

Returns the next value in *pq* without popping it from the priority queue like
`pqueue-pop!` does. An error is raised when *pq* is empty.

::: tip Examples:
``` scheme
> (import :std/srfi/1)
> (def pq (make-pqueue length))
> (pqueue-push! pq (iota (random-integer 10)))
> (pqueue-peek pq)
(0 1 2 3 4 5 6 7)
> (pqueue-push! pq [13 21 34 55])
> (pqueue-peek pq)
(13 21 34 55)
```
:::

### pqueue
```
(defsyntax pqueue)
```

Priority queue type for user-defined generics and destructuring.

::: tip Examples:
``` scheme
> (let (pq (make-pqueue string-length >))
    (pqueue-push! pq "Mimas")
    (pqueue-push! pq "Enceladus")
    (pqueue-push! pq "Tethys")
    (with ((pqueue internal-heap) pq)
      (with ((vector size . vals) internal-heap)
        (displayln "size: " size "\nvals: " vals))))
size: 3
vals: ((9 . Enceladus) (5 . Mimas) (6 . Tethys) 0 0 0 0 0 0 0 0 0 0 0 0)
```
:::


## Process Utilities
::: tip To use the bindings from this module:
``` scheme
(import :std/misc/process)
```
:::

### run-process
``` scheme
(run-process cmd
             [coprocess: read-all-as-string]
             [check-status: #t]
             [environment: #f]
             [directory: #f]
             [stdin-redirection: #t]
             [stdout-redirection: #t]
             [stderr-redirection: #f]
             [pseudo-terminal: #f]
             [show-console: #f]) -> any | error

  cmd                := list of strings, [path . arguments]
  coprocess          := procedure interacting with process
  check-status       := procedure or truth value
  environment        := list of strings, ["VAR=VALUE" ...]
  directory          := dir, working directory
  stdin-redirection  := boolean, standard input redirection
  stdout-redirection := boolean, standard output redirection
  stderr-redirection := boolean, standard error redirection
  pseudo-terminal    := boolean, terminal or pipes (UNIX)
  show-console       := boolean, show or hide console (Windows)
```

Synchronously runs *cmd* in a subprocess, where *cmd* is expected to be a list
consisting of a path to an executable on the filesystem and its arguments.

The following keyword settings are available:

- *coprocess*: A procedure that specifies how to interact with the process,
  which it receives as an argument, and what should be returned from
  `run-process`. Defaults to reading the whole output as a string via
  `std/misc/ports#read-all-as-string`.
- *check-status*: Declares how to handle the exit status of the process upon
  termination. If a procedure is provided, then it will be called with the
  process' exit status and a list of process creation arguments. If
  *check-status* is `#t`, the default, then the exit status is checked and an
  error is raised in case it differs from `0`. Lastly, the exit status is simply
  ignored, when *check-status* is `#f`.
- *environment*: Indicates the set of environment variable bindings that the
  process receives. Each element of the list is a string of the form
  `VAR=VALUE`, where *VAR* is the name of the variable and *VALUE* is its
  binding. When *environment* is `#f`, which is the default, the process inherits
  the environment variable bindings of the Scheme program.
- *directory*: Sets the working directory of the process. When it's `#f`, the
  default, then the process uses the value of `(current-directory)`.
- *stdin-redirection*: Indicates how the standard input of the process is
  redirected. The default `#t` will redirect the standard input from the
  process-port (i.e. what is written to the process-port will be available on
  the standard input). `#f` will leave the standard input as-is, which typically
  results in input coming from the console.
- *stdout-redirection*: Indicates how the standard output of the process is
  redirected. The default `#t` will redirect the standard output to the
  process-port (i.e. all output to standard output can be read from the
  process-port). `#f` will leave the standard output as-is, which typically
  results in the output going to the console.
- *stderr-redirection*: Indicates how the standard error of the process is
  redirected. `#t` will redirect the standard error to the process-port (i.e.
  all output to standard error can be read from the process-port). The default
  `#f` will leave the standard error as-is, which typically results in error
  messages being output to the console.
- *pseudo-terminal*: Applies to *UNIX*. It indicates what type of device will be
  bound to the process’ standard input and standard output. `#t` will use a
  pseudo-terminal device (this is a device that behaves like a tty device even
  though there is no real terminal or user directly involved). The default `#f`
  will use a pair of pipes. The difference is important for programs which
  behave differently when they are used interactively, for example shells.
- *show-console*: Applies to *Microsoft Windows*. It controls whether the
  process’ console window will be hidden or visible. The default value of this
  setting is `#f` (i.e. hide the console window).

More information can be found in section `17.7.2 Process devices` of the Gambit
manual.

::: tip Examples:
``` scheme
> (run-process ["date" "--utc"] coprocess: read-line)
"Tue 21 May 2019 12:22:20 PM UTC"

> (run-process ["/usr/bin/ls"])
"desktop\ndev\ndocuments\ndownloads\nmusic\nnotes\npictures\nvideos\n"

> (import :std/misc/ports)
> (run-process ["ls" "-l"] coprocess: read-all-as-lines)
("drwxr-xr-x.  2 user user  4096 Mar 26 13:26 desktop"
 "drwxr-xr-x.  8 user user  4096 May 13 14:28 dev"
 "drwxr-xr-x. 12 user user 12288 May 19 17:26 documents"
 "drwxr-xr-x.  2 user user  4096 May 20 10:13 downloads"
 "drwxrwxr-x.  8 user user  4096 May  1 15:13 music"
 "drwxr-xr-x.  2 user user  4096 May 21 10:53 notes"
 "drwxr-xr-x.  9 user user  4096 Apr 30 19:08 pictures"
 "drwxrwxr-x.  3 user user 12288 May 21 09:41 videos")


> (def (word-count path)
    (run-process ["wc" path]
                 coprocess: (lambda (process)
                              (with ([l w c] (filter number? (read-all process)))
                                (displayln "lines: " l "\nwords: " w "\nchars: " c)))))
> (word-count "/home/user/dev/scheme/nums.txt")
lines: 5
words: 5
chars: 10
```
:::

### run-process/batch
``` scheme
(run-process/batch cmd) -> void

  cmd := list of strings, [path . arguments]
```

Runs a batch process with *stdin* closed, and both *stdout* and *stderr* on the
current console. Same as `(run-process cmd coprocess: close-output-port
stdout-redirection: #f)`.

::: tip Examples:
``` scheme
> (def files ["file1.txt" "file2.txt" "file3.txt"])
> (for-each (lambda (file) (run-process/batch ["touch" file])) files)
> (run-process/batch (append ["zip" "big.zip"] files))
adding: file1.txt (stored 0%)
adding: file2.txt (stored 0%)
adding: file3.txt (stored 0%)
```
:::


## Simple Queues
::: tip To use the bindings from this module:
``` scheme
(import :std/misc/queue)
```
:::

### make-queue
``` scheme
(make-queue) -> queue
```

Creates a new empty queue, a First-In-First-Out (FIFO) data structure similar to
a list. Compared to an ordinary lists, queues allow appending elements without
having to walk all to the end first.

::: tip Examples:
``` scheme
> (import :std/test)
> (let (q (make-queue))
    (check (queue-empty? q) => #t)
    (enqueue! q 1)
    (enqueue! q 2)
    (enqueue! q 3)
    (check (queue-length q) => 3)
    (queue->list q))
... check (queue-empty? q) is equal? to #t
... check (queue-length q) is equal? to 3
(1 2 3)
```
:::

### queue?
``` scheme
(queue? q) -> boolean

  q := queue to check
```

Returns `#t` if *q* is a queue, `#f` otherwise.

::: tip Examples:
``` scheme
> (let (q (make-queue))
    (enqueue! q (make-queue))
    (and (queue? q)
         (queue? (queue-peek q))
         (queue? (make-queue))))
#t

> (queue? (list 1 2 3))
#f
```
:::

### queue-length
``` scheme
(queue-length q) -> fixnum

  q := queue to check
```

Returns the number of elements enqueued in *q*.

Similar to retrieving the length of a vector, this operation is `O(1)`, since
queues always keep track of their length.

::: tip Examples:
``` scheme
> (let (q (make-queue))
    (enqueue! q #\a)
    (enqueue! q #\b)
    (enqueue! q #\c)
    (queue-length q))
3

> (queue-length (make-queue))
0
```
:::

### queue-empty?
``` scheme
(queue-empty? q) -> boolean

  q := queue to check
```

Returns `#t` if *q* has no elements enqueued, `#f` otherwise.

::: tip Examples:
``` scheme
> (queue-empty? (make-queue))
#t

> (let (q (make-queue))
    (enqueue! q (make-queue))
    (and (queue-empty? (queue-peek q))
         (queue-empty? q)))
#f
```
:::

### non-empty-queue?
``` scheme
(non-empty-queue? q) -> boolean

  q := queue to check
```

Returns `#t` if *q* is not empty, i.e., it has at least one element enqueued.

Equivalent to `(not (queue-empty? q))`.

::: tip Examples:
``` scheme
> (non-empty-queue? (make-queue))
#f

> (let (q (make-queue))
    (enqueue! q [])
    (non-empty-queue? q))
#t
```
:::

### enqueue!
``` scheme
(enqueue! q elem) -> unspecified

  q    := queue to push onto
  elem := element to append to q
```

Enqueues (pushes) *elem* to the end of *q*. Similar to `set!`, it's unspecified
what `enqueue!` returns afterwards.

This operation is faster than simply appending to the end of a regular list,
because queues needn't be walked first.

::: tip Examples:
``` scheme
> (let (q (make-queue))
    (enqueue! q 10)
    (enqueue! q 20)
    (enqueue! q 30)
    (queue->list q))
(10 20 30)

> (import :std/srfi/1 :std/test)
> (let ((q (make-queue))
        (lst (iota 10)))
    (for-each (cut enqueue! q <>) lst)
    (check-equal? (queue-length q) (length lst))
    (check-equal? (queue->list q) lst))
... check (queue-length q) is equal? to 10
... check (queue->list q) is equal? to (0 1 2 3 4 5 6 7 8 9)
```
:::

### enqueue-front!
``` scheme
(enqueue-front! q elem) -> unspecified

  q    := queue to push onto
  elem := element to enqueue to q
```

`enqueue-front!` is similar to `enqueue!`, but pushes *elem* to the front of *q*
instead of the end. It's unspecified what will be returned.

::: tip Examples:
``` scheme
> (let (q (make-queue))
    (enqueue-front! q 10)
    (enqueue-front! q 20)
    (enqueue-front! q 30)
    (queue->list q))
(30 20 10)
```
:::

### dequeue!
``` scheme
(dequeue! q [default = absent-obj]) -> any | default | error

  q       := queue to pop from
  default := optional element returned when q is empty
```

Pops the front of *q* and returns that value. If *q* is empty and a default
value is supplied, then *default* is returned. Otherwise an error is raised.

::: tip Examples:
``` scheme
> (let (q (make-queue))
    (for-each (cut enqueue! q <>) [1 2 3])
    (displayln (dequeue! q))
    (displayln (dequeue! q))
    (displayln (queue->list q))
    (displayln (dequeue! q 100))
    ;; would signal error without default value:
    (displayln (dequeue! q 100)))
1
2
(3)
3
100
```
:::

### queue-peek
``` scheme
(queue-peek q [default = absent-obj]) -> any | default | error

  q       := queue to peek front
  default := optional element returned when q is empty
```

Returns the front value of *q* without popping it from the queue like `dequeue!`
does. If *q* is empty and a default value is supplied, then *default* is
returned. Otherwise an error is raised.

::: tip Examples:
``` scheme
> (def q (make-queue))
> (enqueue! q #\a)
#<queue #8>
> (enqueue! q #\b)
#<queue #8>
> (queue-peek q)
#\a
> (dequeue! q)
#\a
> (queue-peek q)
#\b
> (dequeue! q)
#\b
> (queue-peek q 10)
10
> (queue-peek q)
error
```
:::

### queue-&gt;list
``` scheme
(queue->list q) -> list

  q := queue to transform into list
```

Returns a new list of the elements queued in *q*, in order.

::: tip Examples:
``` scheme
> (import :std/srfi/1)
> (let (q (make-queue))
    (for-each (cut enqueue! q <>) (iota 100))
    (take (queue->list q) 5))
(0 1 2 3 4)
```
:::

### queue
```
(defsyntax queue)
```

Queue type, for user-defined generics and destructuring.

::: tip Examples:
``` scheme
> (let (q (make-queue))
    (enqueue! q 1)
    (enqueue! q 'b)
    (enqueue! q #\c)
    (with ((queue elems back length) q)
      (displayln "elements: " elems ", back: " back "\nand holds " length " items")))
elements: (1 b c), back: (c)
and holds 3 items
```
:::


## Red-Black Trees
::: tip To use the bindings from this module:
``` scheme
(import :std/misc/rbtree)
```
:::

### make-rbtree
``` scheme
(make-rbtree cmp [root = +empty+]) -> rbtree

  cmp  := comparison procedure
  root := optional tree root element
```

Creates a new red-black tree, a self-balancing binary search tree variant,
similar to an AVL tree. Also usable as an sorted hash-table alternative for
small datasets.

The comparison procedure *cmp* is expected to accept two keys, *a* and *b*, and
perform a ternary comparison:
- If `(< a b)`, then it must return a negative number.
- If `(= a b)`, then it must return 0.
- If `(> a b)`, then it must return a positive number.

Examples of comparison procedures: `-`, `string-cmp` or `symbol-cmp`. The latter
two are defined in this module.

::: tip Examples:
``` scheme
> (def rbt1 (make-rbtree -))
> (def rbt2 (list->rbtree string-cmp [["one" . 1] ["two" . 2] ["three" . 3]]))

> (rbtree-put! rbt1 1 "one")
> (rbtree-put! rbt1 2 "two")
> (rbtree-put! rbt1 3 "four")
> (rbtree-put! rbt1 4 "four")
> (rbtree-update! rbt1 3 (lambda (x) (when (string=? x "four") "three")))
> (rbtree-remove! rbt1 4)
> (rbtree->list rbt1)
((1 . "one") (2 . "two") (3 . "three"))
> (rbtree->list rbt2)
(("one" . 1) ("three" . 3) ("two" . 2))

> (import :std/iter)
> (for* ((key (in-rbtree-keys rbt2)) (val (in-rbtree-values rbt1)))
    (unless (string=? key val)
      (displayln key " " val)))
one two
one three
three one
three two
two one
two three
```
:::

### rbtree?
``` scheme
(rbtree? rbt) -> boolean

  rbt := rbtree to check
```

Returns `#t` if *rbt* is an rbtree, `#f` otherwise.

::: tip Examples:
``` scheme
> (rbtree? (make-rbtree string-cmp))
#t
```
:::

### rbtree-empty?
``` scheme
(rbtree-empty? rbt) -> boolean

  rbt := rbtree to check
```

Returns `#t` if *rbt* is empty, `#f` otherwise.

::: tip Examples:
``` scheme
> (rbtree-empty? (make-rbtree -))
#t

> (make-rbtree -)
#<rbtree #62>
> (rbtree-put! #62 0 'NULL)
> (rbtree-empty? #62)
#f
```
:::

### rbtree-put!
``` scheme
(rbtree-put! rbt key val) -> unspecified

  rbt := rbtree to update
  key, val := key-value association to add to rbt
```

Destructively updates *rbt* by inserting the key-value association *key* to
*val*. Similar to `set!`, it's unspecified what `rbtree-put!` returns.

::: tip Examples:
``` scheme
> (let (rbt (make-rbtree -))
    (rbtree-put! rbt 3 'a)
    (displayln (rbtree->list rbt))
    (rbtree-put! rbt 2 'b)
    (displayln (rbtree->list rbt))
    (rbtree-put! rbt 4 'c)
    (displayln (rbtree->list rbt))
    (rbtree-put! rbt 1 'd)
    (displayln (rbtree->list rbt)))
((3 . a))
((2 . b) (3 . a))
((2 . b) (3 . a) (4 . c))
((1 . d) (2 . b) (3 . a) (4 . c))
```
:::

### rbtree-put
``` scheme
(rbtree-put rbt key val) -> rbtree

  rbt := rbtree to update
  key, val := key-value association to add to rbt
```

`rbtree-put` is similar to `rbtree-put!`, but functionally updates *rbt* instead,
returning a new rbtree without modifying *rbt*.

::: tip Examples:
``` scheme
> (let (rbt (make-rbtree -))
    (displayln (rbtree->list (rbtree-put rbt 1 'a)))
    (displayln "empty? " (rbtree-empty? rbt)))
((1 . a))
empty? #t
```
:::

### rbtree-update!
``` scheme
(rbtree-update! rbt key proc [default = void]) -> unspecified

  rbt     := rbtree to update
  key     := key to look up
  proc    := update procedure, receives previous value
  default := optional default value when key not present
```

Destructively updates *rbt* by modifying the value associated with *key*. Looks
up *key* in *rbt* and passes the associated value (or *default*, if *key* isn't
present) to *proc*, an updating procedure. Similar to `set!`, it's unspecified
what `rbtree-update!` returns.

::: tip Examples:
``` scheme
> (def rbt (make-rbtree string-cmp))
> (rbtree-update! rbt "one" 1+ 0)    ; would signal error without default value
> (rbtree->list rbt)
(("one" . 1))
> (rbtree-put! rbt "two" 2)
> (rbtree-update! rbt "two" 1+)
> (rbtree-update! rbt "one" (cut * 2 <>))
> (rbtree->list rbt)
(("one" . 2) ("two" . 3))
```
:::

### rbtree-update
``` scheme
(rbtree-update rbt key proc [default = void]) -> rbtree

  rbt     := rbtree to update
  key     := key to look up
  proc    := update procedure, receives previous value
  default := optional default value when key not present
```

`rbtree-update` is similar to `rbtree-update!`, but functionally updates *rbt*
instead, returning a new rbtree without modifying *rbt*.

::: tip Examples:
``` scheme
> (def rbt (make-rbtree symbol-cmp))
> (rbtree-put! rbt 'a 16)
> (rbtree->list (rbtree-update rbt 'a sqrt))
((a . 4))
> (rbtree->list rbt)
((a . 16))
```
:::

### rbtree-remove!
``` scheme
(rbtree-remove! rbt key) -> unspecified

  rbt := rbtree to update
  key := key to look up
```

Destructively updates *rbt* by removing the value associated with *key*. *rbt*
stays unmodified if *key* isn't present. Similar to `set!`, it's unspecified
what `rbtree-update!` returns.

::: tip Examples:
``` scheme
> (def rbt (make-rbtree symbol-cmp))
> (rbtree-put! rbt 'a 3)
> (rbtree-put! rbt 'b 2)
> (rbtree-put! rbt 'c 1)
> (rbtree-remove! rbt 'b)
> (rbtree-remove! rbt 'd)    ; nothing happens
> (rbtree->list rbt)
((a . 3) (c . 1))
```
:::

### rbtree-remove
``` scheme
(rbtree-remove rbt key) -> rbtree

  rbt := rbtree to update
  key := key to look up
```

`rbtree-remove` is similar to `rbtree-update!`, but functionally updates *rbt*
instead, returning a new rbtree without modifying *rbt*. If *key* isn't present,
then `rbtree-remove` simply returns *rbt* instead of allocating a new identical
tree.

::: tip Examples:
``` scheme
> (let (rbt (make-rbtree -))
    (rbtree-put! rbt 1 "gambit")
    (rbtree-put! (rbtree-remove rbt 2) 1 "gerbil")    ; rbtree-remove returns rbt
    (displayln (rbtree->list rbt))
    (rbtree->list (rbtree-remove rbt 1)))
((1 . "gerbil"))
()
```
:::

### rbtree-ref
``` scheme
(rbtree-ref rbt key [default = absent-obj]) -> any | default | error

  rbt     := rbtree to search in
  key     := key to look up in rbt
  default := optional default value when key not present
```

Returns the value associated with *key* in *rbt*, or *default* if no association
is present; if the *default* value is omitted then an error is raised.

::: tip Examples:
``` scheme
> (def rbt (make-rbtree -))
> (rbtree-put! rbt 1 'a)
> (rbtree-put! rbt 2 'b)
> (rbtree-put! rbt 3 'c)
> (rbtree->list rbt)
((1 . a) (2 . b) (3 . c))
> (rbtree-ref rbt 2 'NONE)
b
> (rbtree-ref rbt 4 'NONE)    ; would signal error without default value
NONE
```
:::

### rbtree-get
``` scheme
(rbtree-get rbt key) -> any | #f

  rbt := rbtree to search in
  key := key to loop up in rbt
```

Same as `(rbtree-ref rbt key #f)`.

::: tip Examples:
``` scheme
> (make-rbtree symbol-cmp)
#<rbtree #54>
> (rbtree-put! #54 'C   "single C")
> (rbtree-put! #54 'BB  "double B")
> (rbtree-put! #54 'AAA "triple A")
> (rbtree-get  #54 'BB)
"double B"
> (rbtree-get  #54 'D)
#f
```
:::

### rbtree-copy
``` scheme
(rbtree-copy rbt) -> rbtree

  rbt := rbtree to copy
```

Returns a copy of *rbt*.

::: tip Examples:
``` scheme
> (rbtree->list (rbtree-copy (make-rbtree string-cmp)))
()

> (def rbt (make-rbtree string-cmp))
> (rbtree-put! rbt "op" sqrt)
> (rbtree-put! (rbtree-copy rbt) "op" +)    ; not overwriting rbt
> (rbtree->list rbt)
("op" . #<procedure #63 sqrt>)
```
:::

### rbtree-for-each
``` scheme
(rbtree-for-each proc rbt) -> void

  proc := procedure to be called for each key-value association in rbt
  rbt  := rbtree to iterate over
```

Evaluates `(proc key val)` for every key-value association in *rbt*, in
ascending order. Isn't returning anything, executed for its side effects.

::: tip Examples:
``` scheme
> (import :std/iter)
> (make-rbtree -)
#<rbtree #66>
> (for ((key [1 2 3 4 5]) (val ["I" "II" "III" "IV" "V"]))
    (rbtree-put! #66 key val))
> (rbtree-for-each (cut displayln <> " -> " <>) #66)
1 -> I
2 -> II
3 -> III
4 -> IV
5 -> V
```
:::

### rbtree-for-eachr
``` scheme
(rbtree-for-eachr proc rbt) -> void

  proc := procedure to be called for each key-value association in rbt
  rbt  := rbtree to iterate over
```

`rbtree-for-eachr` is similar to `rbtree-for-each`, but evaluates `(proc key
val)` in descending (reversed) order.

::: tip Examples:
``` scheme
> (import :std/iter)
> (make-rbtree -)
#<rbtree #66>
> (for ((key [1 2 3 4 5]) (val ["I" "II" "III" "IV" "V"]))
    (rbtree-put! #66 key val))
> (rbtree-for-eachr (cut displayln <> " -> " <>) #66)
5 -> V
4 -> IV
3 -> III
2 -> II
1 -> I
```
:::

### rbtree-fold
``` scheme
(rbtree-fold proc init rbt) -> any

  proc := procedure to be called for each key-value association in rbt
  init := initial value
  rbt  := rbtree to iterate over
```

Folds *rbt* in ascending order.

*proc*'s signature is expected to look like this: `(proc key val
prev-intermediate) -> next-intermediate)`. `rbtree-fold` returns the last
*next-intermediate* value produced by *proc*. Furthermore, *prev-intermediate*
will be set to *init* at the beginning.

::: tip Examples:
``` scheme
> (let (rbt (make-rbtree -))
    (for-each (cut rbtree-put! rbt <> <>) [1 2 3] ["short" "longest" "medium"])
    (rbtree-fold (lambda (k v i)
                   (cond ((> (string-length v) (string-length i)) v)
                         (else i)))
                 "tiny" rbt))
"longest"
```
:::

### rbtree-foldr
``` scheme
(rbtree-foldr proc init rbt) -> any

  proc := procedure to be called for each key-value association in rbt
  init := initial value
  rbt  := rbtree to iterate over
```

Where `rbtree-fold` folds in ascending order, `rbtree-foldr` folds *rbt* in
descending (reverse) order.

::: tip Examples:
``` scheme
> (def rbt (make-rbtree -))
> (rbtree-put! rbt 3 (iota 3))
> (rbtree-put! rbt 4 (iota 4))
> (rbtree-put! rbt 5 (iota 5))
> (rbtree-fold (lambda (k v i) (cons v i)) [] rbt)
((0 1 2 3 4) (0 1 2 3) (0 1 2))
> (rbtree-foldr (lambda (k v i) (cons v i)) [] rbt)
((0 1 2) (0 1 2 3) (0 1 2 3 4))
```
:::

### rbtree-&gt;list
``` scheme
(rbtree->list rbt) -> alist

  rbt := rbtree
```

Returns an alist of key-value associations in *rbt*, in ascending order.

::: tip Examples:
``` scheme
> (list->rbtree - [[3 . "drei"] [1 . "eins"] [2 . "zwei"] [4 . "vier"]])
#<rbtree #71>
> (rbtree->list #71)
((1 . "eins") (2 . "zwei") (3 . "drei") (4 . "vier"))
```
:::

### rbtree-&gt;listr
``` scheme
(rbtree->listr rbt) -> alist

  rbt := rbtree
```

Returns an alist of key-value associations in *rbt*, in descending (reverse)
order.

::: tip Examples:
``` scheme
> (list->rbtree - [[3 . "drei"] [1 . "eins"] [2 . "zwei"] [4 . "vier"]])
#<rbtree #71>
> (rbtree->listr #71)
((4 . "vier") (3 . "drei") (2 . "zwei") (1 . "eins"))
```
:::

### list-&gt;rbtree
``` scheme
(list->rbtree cmp lst) -> rbtree

  cmp := comparison procedure
  lst := alist of key-value associations
```

Creates a new rbtree from *lst*, an associative list. `make-rbtree` describes
how *cmp* is expected to look like.

::: tip Examples:
``` scheme
> (rbtree->list (list->rbtree symbol-cmp '((n . 3) (c . 2) (f . 1))))
((c . 2) (f . 1) (n . 3))

> (rbtree-empty? (rbtree-remove (list->rbtree - [[0 . #\x]]) 0))
#t
```
:::

### in-rbtree
``` scheme
(in-rbtree rbt) -> iterator

  rbt := rbtree to iterate over
```

Creates an iterator over *rbt*, yielding key-value values in ascending order.

::: tip Examples:
``` scheme
> (import :std/iter)
> (def rbt (list->rbtree - '((1 . a) (2 . b) (3 . c))))

> (for/collect ((values k v) (in-rbtree rbt))
    (cons k v))
((1 . a) (2 . b) (3 . c))    ; equivalent to (rbtree->list rbt)

> (for ((values k v) rbt)    ; generic :iter overload for rbtree
    (displayln k " -> " v))
1 -> a
2 -> b
3 -> c
```
:::

### in-rbtree-keys
``` scheme
(in-rbtree-keys rbt) -> iterator

  rbt := rbtree to iterate over
```

Creates an iterator over *rbt*, yielding keys in ascending order.

::: tip Examples:
``` scheme
> (import :std/iter)
> (def rbt1 (list->rbtree - [[1 . #\a] [2 . #\b] [3 . #\c] [4 . #\d] [5 . #\e]]))
> (def rbt2 (list->rbtree - [[5 . #\a] [4 . #\b] [3 . #\c] [2 . #\d] [1 . #\e]]))
> (for* ((x (in-rbtree-keys rbt1)) (y (in-rbtree-keys rbt2)))
    (when (> x y)    ; for* is testing all combinations
      (displayln (cons x y))))
(2 . 1)
(3 . 1)
(3 . 2)
(4 . 1)
(4 . 2)
(4 . 3)
(5 . 1)
(5 . 2)
(5 . 3)
(5 . 4)
```
:::

### in-rbtree-values
``` scheme
(in-rbtree-values rbt) -> iterator

  rbt := rbtree to iterate over
```

Creates an iterator over *rbt*, yielding values in ascending order.

::: tip Examples:
``` scheme
> (import :std/iter)
> (def rbt (list->rbtree symbol-cmp '((a . (1)) (b . (2 3)) (c . (4 5 6)))))

> (for/fold (i []) (lst (in-rbtree-values rbt))
    (append lst i))
(4 5 6 2 3 1)

> (import :std/misc/list)
> (for (lst (in-rbtree-values rbt))
    (when (length>=n? lst 3)
      (displayln lst)))
(4 5 6)
```
:::

### rbtree
``` scheme
(defsyntax rbtree)
```

Red-black tree (rbtree) type, for user-defined generics and destructuring.

::: tip Examples:
``` scheme
;; Possible rbtree iterator implementation:
> (defmethod (:iter (rbt rbtree))
    (in-rbtree rbt))

> (def (in-rbtree rbt)
    (def (iterate)
      (rbtree-for-each yield rbt))
    (in-coroutine iterate))
```
:::

### string-cmp
``` scheme
(string-cmp a b) -> fixnum

  a, b := strings to compare
```

Comparison function for lexicographic string ordering.

::: tip Examples:
``` scheme
> (string-cmp "gambit" "gerbil")
-4

> (string-cmp "aaa" "aaa")
0

> (string-cmp "aac" "aaa")
2

> (string-cmp "aa" "aaaa")
-2

> (string-cmp "aaa" "")
3

> (string-cmp "a" "cb")
-2
```
:::

### symbol-cmp
``` scheme
(symbol-cmp a b) -> fixnum

  a, b := symbols to compare
```

Comparison function for lexicographic symbol ordering.

::: tip Examples:
``` scheme
> (symbol-cmp 'gerbil 'gambit)
4

> (symbol-cmp 'D 'B)
2

> (symbol-cmp 'func (string->symbol "func"))
0
```
:::

### symbol-hash-cmp
``` scheme
(symbol-hash-cmp a b) -> fixnum

  a, b := symbols to compare
```

Comparison function for symbol ordering based on their hashes; ties are broken
by lexicographic ordering.

::: tip Examples:
``` scheme
> (symbol-hash-cmp 'gerbil 'gambit)
-173422207

> (displayln (symbol-hash 'a) " vs. " (symbol-hash 'b))
67905836 vs. 118238693
> (symbol-hash-cmp 'a 'b)
-50332857
```
:::


## Sourceable Representation
::: tip To use the bindings from this module:
``` scheme
(import :std/misc/repr)
```
:::

### print-representation
``` scheme
(print-representation obj
                      [port = (current-output-port)]
                      [options = (current-representation-options)]) -> void

  obj     := object to print
  port    := optional output port
  options := hash-table, representation options
```

Prints an evaluable source-code representation of *obj* to *port*, which
defaults to `(current-output-port)`. That very representation can later be read
back into an equivalent object.

The behaviour of `print-representation` can be specialized for new classes of
objects by defining new overloads on the `:pr` method, see `representable`.

Note: *options* aren't doing anything as of now, but are reserved for future
use.

::: tip Examples:
``` scheme
> (import :std/sugar)
> (def lst (list 1 2 3))
> (def vec (vector 1 2 3))
> (def ht  (hash (a 1) (b 2) (c 3)))
> (def fn  string-append)

> (displayln lst)
(1 2 3)
> (print-representation lst)
[1 2 3]           ; without newline, use prn for that

> (displayln vec)
#(1 2 3)
> (print-representation vec)
(vector 1 2 3)

> (displayln ht)
#<table #631>
> (print-representation ht)
(hash (a 1) (b 2) (c 3))

> (displayln fn)
#<procedure #632 string-append>
> (print-representation fn)
string-append

> (call-with-output-string (cut print-representation vec <>))
"(vector 1 2 3)"
> (repr vec)      ; better use repr, which prints to string by default:
"(vector 1 2 3)"

> (with-output-to-file "hash.rep" (cut print-representation ht))
$ cat hash.rep    ; unix-like command-line
(hash (a 1) (b 2) (c 3))%

> (with-input-from-file "hash.rep"
    (lambda () (print-representation (eval (read)))))
(hash (a 1) (b 2) (c 3))
```
:::

### pr
``` scheme
(defalias pr print-representation)
```

Short for `print-representation`.

::: tip Examples:
``` scheme
> (pr #(11 22 33))
(vector 11 22 33)                 ; without a newline
> (pr '((1 . x) (2 . y) (3 . z)))
[[1 'x ...] [2 'y ...] [3 'z ...]]
> (defstruct gerbil (name age greeting))
> (pr (make-gerbil "Cinnamon" 6 "Morning, everyone!"))
(begin0 #634 "#<gerbil #634>")    ; unrepresentable by default
```
:::

### prn
``` scheme
(prn obj [port = (current-output-port)]
         [options = (current-representation-options)]) -> void

  obj     := object to print
  port    := optional output port
  options := hash-table, representation options
```

`prn` does the same as `pr` or `print-representation`, but also follows with a
newline.

Note: *options* aren't doing anything as of now, but are reserved for future
use.

::: tip Examples:
``` scheme
> (import :std/sugar)
> (prn (hash-eqv (1 "I") (5 "V") (10 "X") (50 "L")))
(hash-eqv (1 "I") (10 "X") (5 "V") (50 "L"))    ; proper newline at the end
> (prn [1 2 [3 4 [5 6 7] 8] 9])
[1 2 [3 4 [5 6 7] 8] 9]
```
:::

### repr
``` scheme
(repr obj [options = (current-representation-options)]) -> string

  obj     := object to print
  options := hash-table, representation options
```

`repr` is similar to `print-representation`, but does not take a port as an
argument and instead returns the representation as a string.

Note: *options* aren't doing anything as of now, but are reserved for future
use.

::: tip Examples:
``` scheme
> (defstruct node (data next prev))
> (repr (make-node #f #f #f))
"(begin0 #635 \"#<node #635>\")"
> (repr (node-data (make-node #(1 2 3) #f #f)))
"(vector 1 2 3)"
```
:::

### representable
```
(defclass representable ())
(defmethod {:pr representable} print-unrepresentable-object)
```

`representable` is an abstract mixin class that defines a method for `:pr`. By
default, if a class does not provide its own implementation, then
`print-unrepresentable-object` will be called.

::: tip Examples:
``` scheme
> (defstruct point (x y))
> (def p (make-point 10 20))
> (displayln p)
#<point #4>
> (prn p)
(begin0 #4 "#<point #4>")    ; print-unrepresentable-object

> (defmethod {:pr point}
    (lambda (self port options)
      (for-each (cut display <> port)
                ["(point " (point-x self) " " (point-y self) ")"])))
> (prn p)
(point 10 20)

> (let ((p1 (make-point 10 20))
        (p2 (eval (with-input-from-string (repr p) read))))
    (and (= (point-x p1) (point-x p2))
         (= (point-y p1) (point-y p2))))
#t
```
:::

### print-unrepresentable-object
``` scheme
(print-unrepresentable-object obj
                              [port = (current-output-port)]
                              [options = (current-representation-options)]) -> void
  obj := object to print
  port := optional output port
  options := hash-table, representation options
```

`print-unrepresentable-object` is a helper function to use as a fallback for
objects that can't otherwise be displayed. Prints a general-purpose escape of
*obj*, using the `#id` syntax and appends a string hint as obtained from the
`write` function.

Note: *options* aren't doing anything as of now, but are reserved for future
use.

::: tip Examples:
``` scheme
> (import :std/misc/queue)
> (def q (make-queue))
> (enqueue! q 100)
> (prn q)
(begin0 #9 "#<queue #9>")    ; calls print-unrepresentable-object
> (print-unrepresentable-object q)
(begin0 #9 "#<queue #9>")
```
:::

<!-- Uncommenting for now till impl lands
### default-representation-options
```
(def default-representation-options)
```

`default-representation-options` is the default table of options.
No options are currently defined, and the default table is currently empty.
In the future, options may be defined for pretty-printing, etc.
-->

<!-- Uncommenting for now till impl lands
### current-representation-options
``` scheme
(current-representation-options [TODO]) -> TODO

  make-parameter := TODO
```

`current-representation-options` is a parameter returning the current options,
and initially returns the `default-representation-options`.

::: tip Examples:
``` scheme
TODO
```
:::
-->

### display-separated
``` scheme
(display-separated lst
                   [port = (current-output-port)]
                   [prefix: ""]
                   [separator: " "]
                   [suffix: ""]
                   [display-element: display]) -> void

  lst             := list of objects to print
  port            := optional output port
  prefix          := string prefix
  separator       := string separator
  suffix          := string suffix
  display-element := function that does the actual printing
```

`display-separated` is a helper function that takes *lst*, a list of objects to
print, an optional output *port*, and as keywords a *prefix* string (empty by
default), a *suffix* string (empty by default), a *separator* string (defaulting
to a single space `" "`), and a *display-element* function (`display` by
default). Displays each element of *lst* with the given *prefix*, *suffix*,
*separator* and *display-element* function.

::: tip Examples:
``` scheme
> (import :std/sugar)
> (def ht (hash (a 1) (b 2) (c 3)))
> (display-separated (hash-values ht) (current-output-port)
                     prefix: "(list\n  "
                     suffix: ")"
                     separator: "\n  ")
(list
  3
  2
  1)

;; this module already supports printing list:
> (prn (hash-values ht))
[3 2 1]
```
:::


## Type Descriptor Utilities.
::: tip To use the bindings from this module:
``` scheme
(import :std/misc/rtd)
```
:::

### object-type
``` scheme
(object-type obj) -> type | error

  obj := object instance
```

Safe variant of `runtime#object-type`. Returns the class of an object; *obj*
must be an object instance or an error is signaled.

::: tip Examples:
``` scheme
> (defstruct point (x y))
> (object-type (make-point 640 480))
#<type #4 point>
> (eq? point::t #4)
#t
> (object-type 12)
error    ; not segfaulting like runtime#object-type
```
:::

### type?
``` scheme
(type? typ) -> boolean

  typ := type object to check
```

Returns `#t` if *obj* is a type object, `#f` otherwise.

::: tip Examples:
``` scheme
> (defstruct point (x y))
> (type? point::t)
#t
> (type? (object-type (make-point -100 100)))
#t
> (type? (make-point 0 0))
#f
```
:::

### type-id
``` scheme
(type-id typ) -> type id | error

  typ := type object to inspect
```

Returns the id of the type object *typ*. Will signal an error if *typ* isn't a
type object.

::: tip Examples:
``` scheme
> (defstruct a ())
> (defclass  b ())
> (type-id a::t)
#:a::t45
> (type-id b::t)
#:b::t49
> (type-id (object-type (make-b)))
#:b::t49
```
:::

### type-name
``` scheme
(type-name typ) -> type name | error

  typ := type object to inspect
```

Returns the name of the type object *typ*. Will signal an error if *typ* isn't a
type object.

::: tip Examples:
``` scheme
> (defstruct vec3i (x y z))
> (type-name (object-type (make-vec3i 30 0 15)))
vec3i
```
:::

### type-super
``` scheme
(type-super typ) -> super class | error

  typ := type object to inspect
```

Returns the super class of the type object *typ*. Will signal an error if *typ*
isn't a type object.

::: tip Examples:
``` scheme
> (defstruct A (x y))
> (defstruct (B A) (z))
> (struct-subtype? A::t B::t)
#t
> (type-super B::t)
#<type #5 A>
> (type-super A::t)
#f
```
:::

### type-descriptor-mixin
``` scheme
(type-descriptor-mixin typ) -> list | error

  typ := type descriptor to inspect
```

Safe variant of `runtime#type-descriptor-mixin`. Returns the mixins of the type
as a list. *typ* must be a type descriptor or an error is signaled.

::: tip Examples:
``` scheme
> (defclass A (x))
> (defclass (B A) (y))
> (defclass (C A) (z))
> (defclass (D B C) ())
> (type-descriptor-mixin D::t)
(#<type #8 B> #<type #9 C> #<type #10 A>)
> (type-descriptor-mixin B::t)
(#<type #10 A>)
> (type-descriptor-mixin A::t)
()
```
:::

### type-descriptor-fields
``` scheme
(type-descriptor-fields typ) -> fixnum | error

  typ := type descriptor to inspect
```

Safe variant of `runtime#type-descriptor-fields`. Returns the number of fields
of the type as a fixnum. *typ* must be a type descriptor or an error is
signaled.

::: tip Examples:
``` scheme
> (defstruct color (r g b a))
> (type-descriptor-fields color::t)
4
```
:::

### type-descriptor-plist
``` scheme
(type-descriptor-plist typ) -> alist | error

  typ := type descriptor to inspect
```

Safe variant of `runtime#type-descriptor-plist`. Returns the type properties of
the type as an alist. *typ* must be a type descriptor or an error is signaled.

::: tip Examples:
``` scheme
> (defstruct vec4d (x y z w) final: #t)
> (type-descriptor-plist vec4d::t)
((fields: x y z w) (final: . #t))
```
:::

### type-descriptor-ctor
``` scheme
(type-descriptor-ctor typ) -> symbol | error

  typ := type descriptor to inspect
```

Safe variant of `runtime#type-descriptor-ctor`. Returns the constructor ID of
the type as a symbol. *typ* must be a type descriptor or an error is signaled.

::: tip Examples:
``` scheme
> (defclass A (x) constructor: :init!)
> (defmethod {:init! A}
    (lambda (self x)
      (set! (A-x self) (* x 2))))
> (type-descriptor-ctor A::t)
:init!
```
:::

### type-descriptor-slots
``` scheme
(type-descriptor-slots typ) -> hash-table | error

  typ := type descriptor to inspect
```

Safe variant of `runtime#type-descriptor-slots`. Returns the slots of the type
as a hash-table. *typ* must be a type descriptor or an error is signaled.

::: tip Examples:
``` scheme
> (defclass color (r g b a))
> (type-descriptor-slots color::t)
#<table #6>
> (hash->list #6)
((r . 0) (g . 1) (b . 2) (a: . 3) (g: . 1) (b: . 2) (r: . 0) (a . 3))
```
:::

### type-descriptor-methods
``` scheme
(type-descriptor-methods typ) -> hash-table | error

  typ := type descriptor to inspect
```

Safe variant of `runtime#type-descriptor-methods`. Returns the methods
associated with the type as a hash-table. *typ* must be a type descriptor or an
error is signaled.

::: tip Examples:
``` scheme
> (defclass A (x) constructor: :init!)
> (defmethod {:init! A}
    (lambda (self x)
      (set! (A-x self) (* x 2))))
> (type-descriptor-methods A::t)
#<table #11>
> (hash->list #11)
((:init! . #<procedure #12 A:::init!>))
```
:::


## Shared-structure Equality.
::: tip To use the bindings from this module:
``` scheme
(import :std/misc/shared)
```
:::

### equal-shared?
``` scheme
(equal-shared? a b) -> boolean

  a, b := structures to check
```

Checks whether *a* and *b*, two potentially recursive, cyclic or otherwise
infinite shared structures, e.g. trees or graphs, are equal.

::: warning Deprecation note:
Gambit 4.9.3 (released 2019-02-05) added similar support for handling shared
structures with `equal?`, superseding `equal-shared?`.
:::

## Shuffling
::: tip To use the bindings from this module:
``` scheme
(import :std/misc/shuffle)
```
:::

### shuffle
``` scheme
(shuffle lst) -> list

  lst := proper list to shuffle
```

Creates a pseudo-random permutation of the values in *lst* and returns a new
list. *lst* will not be modified during this.

Implementation detail: *lst* is converted to a random-access vector first, which
is then shuffled via `vector-shuffle!`, and finally converted back to a proper
list.

::: tip Examples:
``` scheme
> (def lst [1 2 3 4 5])

> (shuffle lst)
(2 1 3 5 4)

> (shuffle lst)
(3 4 2 1 5)

> lst
(1 2 3 4 5)    ; lst is unaffected by the shuffling
```
:::

### vector-shuffle
``` scheme
(vector-shuffle vec) -> vector

  vec := vector to shuffle
```

Creates a pseudo-random permutation of the values in *vec* and returns a new
vector. *vec* will not be modified during this.

Implementation detail: *vec* is copied first, and it is this very copy that is
then shuffled via `vector-shuffle!`.

::: tip Examples:
``` scheme
> (def vec #(1 2 3 4 5))

> (vector-shuffle vec)
#(2 1 5 4 3)

> (vector-shuffle vec)
#(4 2 5 1 3)

> vec
#(1 2 3 4 5)    ; vec is unaffected by the shuffling
```
:::

### vector-shuffle!
``` scheme
(vector-shuffle! vec) -> vector

  vec := vector to shuffle
```

Creates a pseudo-random permutation of the values in *vec*, but does so
in-place, which means that *vec* will be modified directly instead of allocating
a new vector.

Implementation detail: The shuffling is performed according to Sattolo's
algorithm, a Fisher-Yates shuffle variant.

::: tip Examples:
``` scheme
> (def vec #(1 2 3 4 5))

> (vector-shuffle! vec)
#(3 4 1 5 2)

> (vector-shuffle! vec)
#(3 1 5 4 2)

> vec
#(3 1 5 4 2)
```
:::


## String utilities
::: tip To use the bindings from this module:
``` scheme
(import :std/misc/string)
```
:::

### string-trim-prefix
``` scheme
(string-trim-prefix pfix str) -> string

  pfix := string prefix to trim
  str  := string to search in for pfix
```

If *str* starts with the given string prefix *pfix*, then `string-trim-prefix`
returns the rest of *str* without *pfix*. If *pfix* isn't a valid prefix of
*str*, return the entire string *str* instead.

::: tip Examples:
``` scheme
> (string-trim-prefix "date:" "date:2019-05-01")
"2019-05-01"

> (string-trim-prefix "$" "100")
"100"

> (map (cut string-trim-prefix ":std/misc/" <>)
       [":std/misc/string" ":std/misc/ports" ":std/misc/list"])
("string" "ports" "list")
```
:::

### string-trim-suffix
``` scheme
(string-trim-suffix sfix str) -> string

  sfix := string suffix to trim
  str  := string to search in for sfix
```

Analog to `string-trim-prefix`, but returns the beginning of *str* without the
string ending *sfix*.

::: tip Examples:
``` scheme
> (string-trim-suffix ".ss" "strings.ss")
"strings"

> (map (cut string-trim-suffix ".txt" <>)
       ["README.txt" "LICENSE.txt" "CREDITS.txt"])
("README" "LICENSE" "CREDITS")
```
:::

### string-trim-eol
``` scheme
(string-trim-eol str) -> string

  str := string to trim
```

Trims any single end-of-line marker `CR`, `LF` or `CRLF` at the end of *str*.

Note: `string-trim-eol` removes only one end-of-line marker. Use
`(string-trim-right str (char-set #\return #\newline))` to remove all of them.

::: tip Examples:
``` scheme
> (string-trim-eol "foo\r")
"foo"      ; equivalent to (string-trim-suffix +cr+ "foo\r")

> (string-trim-eol "foo\n\n")
"foo\n"    ; only a single end-of-line marker is removed
```
:::

### string-split-prefix
``` scheme
(string-split-prefix pfix str) -> (values string string)

  pfix := string prefix to split after
  str  := string to search in for pfix
```

Split *str* based on given string prefix *pfix*, returning both the string part
after the prefix as well as the prefix itself, or both the whole string and `""`
in case *pfix* isn't found in *str*.

`string-split-prefix` is similar to `string-trim-prefix`, but also returns the
prefix as a second value.

::: tip Examples:
``` scheme
> (string-split-prefix "123" "123abcdef")
"abcdef"    ; suffix/rest
"123"       ; prefix

> (string-split-prefix "123" "no-numbers-here")
"no-numbers-here"
""

> (import :std/srfi/13)
> (for-each (lambda (brw)
              (let-values (((name year) (string-split-prefix (string-take brw 4) brw)))
                (displayln "initial release of " name " was " year)))
            ["2002firefox" "2003safari" "2008chrome" "2015edge"])
initial release of firefox was 2002
initial release of safari was 2003
initial release of chrome was 2008
initial release of edge was 2015
```
:::

### string-split-suffix
``` scheme
(string-split-suffix sfix str) -> (values string string)

  sfix := string suffix to split before
  str  := string to search in for sfix
```

Analog to `string-split-prefix`, but splits *str* based on a given string suffix
*sfix* instead.

`string-split-suffix` is similar to `string-trim-suffix`, but also returns the
suffix as a second value.

::: tip Examples:
``` scheme
> (string-split-suffix ".scm" "secret.scm")
"secret"    ; prefix/rest
".scm"      ; suffix

> (string-split-suffix ".scm" "secret.lisp")
"secret.lisp"
""
```
:::

### string-split-eol
``` scheme
(string-split-eol str) -> string

  str := string to split
```

Analog to `string-trim-eol`, but splits one single end-of-line marker off of
*str*, which is then also returned as a second value.

::: tip Examples:
``` scheme
> (equal? +lf+ (values-ref (string-split-eol "foo\n") 1))
#t
```
:::

### string-subst
``` scheme
(string-subst str old new [count: #f]) -> string | error

  str   := string to perform changes on, won't be modified
  old   := string, what to remove
  new   := string, what to insert instead
  count := number of substitutions, optional keyword param
```

Substitutes/replaces string *old* with string *new* inside of *str*. *str*
itself will not be modified. The procedure expects *count* to be a valid number
(a fixnum to be precise) or `#f`, indicating the number of substitutions to
perform, otherwise an error is signaled.

- `count #f`: no limit, the default
- `count > 0`: limit replacements
- `count <= 0`: return input

::: tip Examples:
``` scheme
> (string-subst "aabbaaaaabb" "aa" "cc")
"ccbbccccabb"    ; single a remains, only replacing pairs

> (string-subst "subst;some;of;these;semicolons" ";" "#" count: 2)
"subst#some#of;these;semicolons"
```
:::

### string-whitespace?
``` scheme
(string-whitespace? str) -> boolean

  str := string to check for whitespace characters
```

Returns true when the string *s* consists only of whitespace characters.

| character string | name            |
|:-----------------|:----------------|
| ` `              | space           |
| `\n`             | line feed       |
| `\t`             | horizontal tab  |
| `\r`             | carriage return |
| `\f`             | form feed       |
| `\v`             | vertical tab    |

::: tip Examples:
``` scheme
> (string-whitespace? "")
#t

> (string-whitespace? "\n \t")
#t
```
:::

### random-string
``` scheme
(random-string [len = 10]) -> string | error

  len := optional, length of the output string
```

`random-string` returns a string consisting of regex word-boundary
characters (`[a-zA-Z0-9_]`). Throws an error if `len` is not a fixnum.

::: tip Examples:
``` scheme
> (random-string)
"5CfMyYd2Ob"

> (random-string 0)
""
```
:::

### line ending variables
``` scheme
(define +cr+   "\r")
(define +lf+   "\n")
(define +crlf+ "\r\n")
```

Global line ending convenience definitions.


## Synchronized Data Structures.
::: tip To use the bindings from this module:
``` scheme
(import :std/misc/sync)
```
:::

### make-sync-hash
``` scheme
(make-sync-hash ht) -> sync-hash

  ht := regular non-synced hash-table
```

Wraps *ht*, a regular hash-table, and returns a synced variant that supports
thread-safe table operations by implicitly locking.

Note: It's discouraged to modify the unwrapped, non-thread-safe *ht* after this
point.

::: tip Examples:
``` scheme
> (import :gerbil/gambit/threads :std/iter :std/srfi/1)
> (def (increment! sht)
    (for (x (in-range 1000))
      (sync-hash-do sht (cut hash-update! <> x 1+ 0))))

> (def sht (make-sync-hash (make-hash-table-eqv)))
> (def threads (for/collect (n (in-range 16))
                 (spawn-thread (cut increment! sht))))
> (for-each thread-join! threads)
> (sync-hash-do sht
    (lambda (ht)
      (every (cut = 16 <>)
             (hash-values ht))))
#t
```
:::

### sync-hash?
``` scheme
(sync-hash? sht) -> boolean

  sht := sync-hash to check
```

Returns `#t` if *sht* is a sync-hash, `#f` otherwise.

Synced variant of `hash?` and `hash-table?`.

::: tip Examples:
``` scheme
> (import :std/sugar)
> (sync-hash? (make-sync-hash (hash)))
#t

> (sync-hash? (make-hash-table))
#f
```
:::

### sync-hash-ref
``` scheme
(sync-hash-ref sht key default) -> any | default

  sht     := sync-hash to check
  key     := key to loop up in sht
  default := non-optional default value when key not present
```

Returns the value bound to *key* in *sht*, defaulting to *default* if no such
value was bound.

Synced variant of `hash-ref`.

::: tip Examples:
``` scheme
> (import :std/sugar)
> (def sht (make-sync-hash (hash (एक 1) (दस 10) (सौ 100))))
> (sync-hash-ref sht 'दस 0)
10
> (sync-hash-ref sht 'सहस्र 0)
0
> (sync-hash-ref sht 10 'NONE)
NONE
```
:::

### sync-hash-get
``` scheme
(sync-hash-get sht key) -> any | #f

  sht := sync-hash to check
  key := key to loop up in sht
```

Same as `(sync-hash-ref sht key #f)`.

Synced variant of `hash-get`.

::: tip Examples:
``` scheme
> (import :std/sugar)
> (def sht (make-sync-hash (hash (一 1) (十 10) (百 100))))
> (sync-hash-get sht '十)
10
> (sync-hash-get sht '千)
#f
> (sync-hash-get sht 10)
#f
```
:::

### sync-hash-put!
``` scheme
(sync-hash-put! sht key val) -> unspecified

  sht      := sync-hash to modify
  key, val := key-value pair to add to sht
```

Binds *key* to *val* in *sht*.

Synced variant of `hash-put!`.

::: tip Examples:
``` scheme
> (import :std/sugar)
> (make-sync-hash (hash))
#<sync-hash #77>
> (sync-hash-put! #77 #\a [1 2 3])
> (sync-hash-put! #77 'a  [4 5 6])
> (sync-hash-put! #77 "a" [7 8 9])
> (sync-hash-do #77 (cut hash-values <>))
((1 2 3) (4 5 6) (7 8 9))
```
:::

### sync-hash-remove!
``` scheme
(sync-hash-remove! sht key) -> void

  sht := sync-hash to modify
  key := key to look up in sht
```

Removes *sht*'s binding for *key*.

Synced variant of `hash-remove!`.

::: tip Examples:
``` scheme
> (import :std/sugar)
> (let (sht (make-sync-hash (hash (a 10) (b 20) (c 30) (d 40))))
    (sync-hash-remove! sht 'b)
    (sync-hash-remove! sht 'e)    ; nothing happens
    (sync-hash-do sht
      (lambda (ht) (hash-for-each (cut displayln <> " -> " <>) ht))))
a -> 10
d -> 40
c -> 30
```
:::

### sync-hash-key?
``` scheme
(sync-hash-key? sht key) -> boolean

  sht := sync-hash to check
  key := key to look up in sht
```

Returns `#t` if *sht* has a binding for key, `#f` otherwise.

Synced variant of `hash-key?`.

::: tip Examples:
``` scheme
> (def sht (make-sync-hash (list->hash-table [[1 . #\a] [2 . #\b] [3 . #\c]])))
> (sync-hash-key? sht 1)
#t
> (sync-hash-key? sht 3)
#t
> (sync-hash-key? sht 4)
#f
```
:::

### sync-hash-do
``` scheme
(sync-hash-do sht proc) -> any

  sht  := sync-hash to iterate or modify
  proc := procedure handling internal hash-table
```

Allows thread-safe access to the unwrapped regular hash-table of *sht* by
passing it to *proc* within an implicitly locked scope. Returns whatever *proc*
is returning.

::: tip Examples:
``` scheme
> (import :std/sugar)
> (def sht (make-sync-hash (hash (A0 160) (B1 177) (C2 194) (D3 211) (E4 228))))
> (sync-hash-do sht
    (lambda (ht)
      (hash-fold (lambda (k v i) (+ v i)) 0 ht)))
970
> (sync-hash-do sht (cut hash-put! <> 'C2 0))
> (sync-hash-get sht 'C2)
0
> (sync-hash-do sht hash->list)
((A0 . 160) (B1 . 177) (D3 . 211) (E4 . 228) (C2 . 0))
> (sync-hash-do sht (lambda (ht) (apply max (hash-values ht))))
228
```
:::


## Text Utilities
::: tip To use the bindings from this module:
``` scheme
(import :std/misc/text)
```
:::

### include-text
``` scheme
(include-text path) -> string

  path := path to file to include, string
```

Macro that expands to file contents of *path* at compile-time.

::: tip Examples:
``` scheme
> (def vert-shader-src (include-text "/home/user/dev/opengl/minimal.vert"))

;; instead of here strings:
> (def vert-shader-src #<<EOF
#version 420 core

void main(void)
{
    gl_Position = gl_Vertex;
}
EOF
)

> vert-shader-src    ; same string in both cases
"#version 420 core\n\nvoid main(void)\n{\n    gl_Position = gl_Vertex;\n}"
```
:::

### quasistring
``` scheme
(quasistring str) -> string

  str := template string containing run-time template variables only
```

Macro that parses the template string *str* for run-time template variables.
These are denoted by `#{}`. They can contain either symbols, which are captured
in the lexical scope, or s-expressions. Returns a `string-append` containing
the parsed string with template variables inserted in the proper order for
run-time evaluation.

Each run-time variable is passed to `format` for conversion to a `string`.

::: tip Examples:
``` scheme
> (let (name "world") (quasistring "Hello, #{name}!"))
"Hello, world!"
> (def (qs name: name) (quasistring "Hello, #{name}!"))
> (displayln (qs name: "world"))
Hello, world!
> (pp qs)
(lambda #0=#:args4967 (apply keyword-dispatch #(name:) #:kw-lambda4564 #0#))
> (pp (lambda (name) (quasistring "Hello, #{name}!")))
(lambda (#0=#:name71)
  (string-append "Hello, " (std/format#format "~a" #0#) "!"))
> (pp (quasistring "Current UNIX time: #{(time->seconds (current-time))}"))
"Current UNIX time: 1572452220.8500578"
> (def (now) (quasistring "Current UNIX time: #{(time->seconds (current-time))}"))
> (pp now)
(lambda ()
  (string-append
   "Current UNIX time: "
   (std/format#format "~a" (time->seconds (current-time)))
   ""))
> (now)
"Current UNIX time: 1572452333.9675934"
```
:::

### quasistring*
``` scheme
(quasistring str) -> string

  str := template string containing run-time and/or expansion-time template variables
```

Macro with the same behaviour as `quasistring` but also accepts expansion-time
template variables, denoted with `##{}`. Expansion-time template variables
are captured in at the top-level context (i.e. not in a `let` form).

Imports used inside expansion-time template variables need to be
imported `for-syntax`.

::: tip Examples:
``` scheme
> (def (qs name) (quasistring* "Hello, #{name}!"))
> (qs "world")
"Hello, world!"
> (def compiled-qs (let (name "world") (quasistring* "Hello, ##{name}!")))
*** ERROR IN ##main -- Unbound variable: #:name77
> (def name "world")
> (def compiled-qs (quasistring* "Hello, ##{name}!"))
> compiled-qs
"Hello, world!"
> (pp compiled-qs)
"Hello, world!"
> (string? compiled-qs)
#t
> (def (qs name) (quasistring* "Hello, #{name}!\nCurrent UNIX time: ##{(time->seconds (current-time))}"))
> (displayln (qs "world"))
Hello, world!
Current UNIX time: 1572452685.6643195
> (pp qs)     
(lambda (#0=#:name80)
  (string-append
   "Hello, "
   (std/format#format "~a" #0#)
   "!\nCurrent UNIX time: 1572452685.6643195"))
```
:::

### include-quasistring
``` scheme
(include-quasistring path) -> string

  path := path to the template file to include
```

Macro that parses the `quasistring` in template file at *path* using `include-text`.

::: tip Examples:
``` scheme
> (let (name "world") (include-quasistring "std/misc/_test/run-time.txt"))
"Hello, world!\n"
```
:::

### include-quasistring*
``` scheme
(include-quasistring* path) -> string

  path := path to the template file to include
```

Macro that parses the `quasistring*` in template file at *path* using `include-text`.

::: tip Examples:
``` scheme
> (import (for-syntax :std/misc/bytes))
> (let (name "world") (include-quasistring* "std/misc/_test/mixed.txt"))
"Hello, world!\nFF 00 FF\n"
```
:::

## Thread utilities
::: tip To use the bindings from this module:
``` scheme
(import :std/misc/threads)
```
:::

### primordial-thread-group
``` scheme
(primordial-thread-group) -> thread-group
```

Similar to `current-thread-group`, but always returns the primordial (main)
thread's group instead.

::: tip Examples:
``` scheme
;; same in main thread
> (current-thread-group)
#<thread-group #87 primordial>
> (primordial-thread-group)
#<thread-group #87 primordial>

;; differs in other groups
> (import :gerbil/gambit/threads)
> (def (task)
    (displayln (current-thread-group))
    (displayln (primordial-thread-group)))
> (thread-join! (spawn/group 'new-group task))
#<thread-group #181 new-group>
#<thread-group #87 primordial>
```
:::

### thread-group-&gt;thread-list*
``` scheme
(thread-group->thread-list* tg) -> list

  tg := thread-group to transform
```

Similar to `thread-group->thread-list`, but also collects the threads in all
subgroups of *tg*. Returns a flat list of threads.

::: tip Examples:
``` scheme
> (import :gerbil/gambit/threads)
> (let* ((g1 (make-thread-group 'G1))
         (g2 (make-thread-group 'G2 g1))
         (g3 (make-thread-group 'G3 g2))
         (t1 (make-thread (cut 1) 'T1 g1))
         (t2 (make-thread (cut 2) 'T2 g1))
         (t3 (make-thread (cut 3) 'T3 g2))
         (t4 (make-thread (cut 4) 'T4 g3)))
    (displayln (thread-group->thread-list  g1))
    (displayln (thread-group->thread-list  g2))
    (displayln (thread-group->thread-list  g3))
    (displayln (thread-group->thread-list* g1)))
(#<thread #214 T1> #<thread #215 T2>)
(#<thread #216 T3>)
(#<thread #217 T4>)
(#<thread #217 T4> #<thread #216 T3> #<thread #214 T1> #<thread #215 T2>)
```
:::

### all-threads
``` scheme
(all-threads) -> (list thread ...)
```

Same as `(thread-group->thread-list* (primordial-thread-group))`. Walks all
thread-groups recursively and collects threads in a flat list.

::: tip Examples:
``` scheme
> (all-threads)
(#<thread #205 th1>
 #<thread #202 th5>
 #<thread #203 th4>
 #<thread #204 th3>
 #<thread #201 th2>    ; th2, ..., th5 in subgroups
 #<thread #1 primordial>)

;; non-recursive, only threads in specified top group:
> (import :gerbil/gambit/threads)
> (thread-group->thread-list (current-thread-group))
(#<thread #1 primordial> #<thread #205 th1>)
```
:::

### thread-dead?
``` scheme
(thread-dead? th) -> boolean

  th := thread to check
```

Returns `#t` if *th* is terminated, i.e., no longer able to run, `#f` otherwise.

::: tip Examples:
``` scheme
> (let (th (spawn thread-sleep! 2))
    (displayln (thread-dead? th))
    (thread-join! th)
    (displayln (thread-dead? th)))
#f
#t

> (thread-dead? (current-thread))
#f
```
:::

### thread-group-kill!
``` scheme
(thread-group-kill! tg) -> void | error

  tg := thread-group to kill
```

Kills all threads and subgroups in *tg*. In addition, it detaches the thread
group from its parent, making it unreachable from the primordial thread-group
structure and eligible for garbage collection. Signals an error when *tg*
contains the current thread.

Note: A thread group that has been killed should not be used again to spawn
threads in it.

::: tip Examples:
``` scheme
> (def (fib n)
    (cond ((< n 2) n)
          (else (+ (fib (- n 1))
                   (fib (- n 2))))))
> (let (g (make-thread-group 'new-group))
    (spawn-thread (cut fib 10) 'fib10 g)
    (spawn-thread (cut fib 30) 'fib30 g)
    (spawn-thread (cut fib 50) 'fib50 g)
    (spawn-thread (cut fib 70) 'fib70 g)
    (thread-sleep! 1)
    (displayln (all-threads))
    (thread-group-kill! g)
    (displayln (all-threads)))
;; thread fib10 already terminated:
(#<thread #231 fib70> #<thread #232 fib50> #<thread #233 fib30> #<thread #1 primordial>)
(#<thread #1 primordial>)

> (thread-group-kill! (current-thread-group))
error
```
:::

### thread-raise!
``` scheme
(thread-raise! th obj) -> void | error

  th  := thread to signal error in
  obj := exception object to raise
```

Interrupts *th*, which can be the primordial thread, and raises *obj*,
terminating that very thread if not handled properly.

::: tip Examples:
``` scheme
> (import :gerbil/gambit/threads)
> (spawn thread-sleep! 10)
#<thread #238>
> (thread-dead? #238)
#f
> (thread-raise! #238 'failure)    ; #<thread #238> silently terminates
> (thread-dead? #238)
#t

> (thread-raise! (current-thread) 'failure)
*** ERROR IN (console)@1819.1 -- This object was raised: failure
```
:::

### thread-abort!
``` scheme
(thread-abort! th) -> void | error

  th := thread to abort
```

Same as `(thread-raise! th +thread-abort+)`. *+thread-abort+* is an
internal exception object that has predefined support for type checking via
`thread-abort?` and a `display-exception` method overload.

::: tip Examples:
``` scheme
> (import :gerbil/gambit/threads :std/sugar)
> (def (task)
    (try
      (let loop ()
        (displayln "working")
        (thread-sleep! 0.2)
        (loop))
      (catch (thread-abort? ex)
        (display-exception ex (current-error-port)))))
> (let (t (spawn task))
    (thread-sleep! 1)
    (thread-abort! t)
    (thread-join! t))
working
working
working
working
working
thread aborted
```
:::

### thread-abort?
``` scheme
(thread-abort? ex) -> boolean

  ex := exception to check
```

Returns `#t` if *ex* is a thread-abort exception type, `#f` otherwise,
essentially checking whether the current thread was interrupted via
`thread-abort!`.

::: tip Examples:
``` scheme
> (import :gerbil/gambit/threads :std/sugar)
> (try
    (thread-abort! (current-thread))
    (catch (thread-abort? ex)
      (display-exception ex (current-error-port))))
thread aborted    ; predefined exception message for thread-abort objects
```
:::

### thread-async!
``` scheme
(thread-async! th proc) -> any | void

  th   := thread to interrupt
  proc := thunk, procedure to execute
```

Interrupts *th*, which can be the primordial thread, and executes *proc*.
Returns the result of *proc*, if *th* is the current thread, `void` otherwise.

::: tip Examples:
``` scheme
> (import :gerbil/gambit/threads)
> (def (task)
    (let loop ((i 0))
      (thread-sleep! 0.25)
      (when (<= i 5)
        (displayln "regular work: " i)
        (loop (1+ i)))))
> (let (th (spawn task))
    (thread-sleep! 1)
    (thread-async! th (cut displayln "async work: " (current-thread)))
    (thread-join! th))
regular work: 0
regular work: 1
regular work: 2
async work: #<thread #60>    ; non-primordial thread
regular work: 3
regular work: 4
regular work: 5
```
:::

### on-all-processors
``` scheme
(on-all-processors proc) -> (list thread ...)

  proc := thunk, procedure to execute on all CPU cores
```

Executes *proc* multiple times, once on each available processing unit (CPU
core), and returns a list containing the created threads.

Note: Runtime support for multiple OS threads needs to be enabled in Gambit (see
the installation instructions), otherwise only a single core is used.

::: tip Examples:
``` scheme
;; check processor support:
> (##current-vm-processor-count)
2

> (import :gerbil/gambit/threads)
> (let (threads (on-all-processors (lambda () 'OK)))
    (map thread-join! threads))
(OK OK)
```
:::


## Timeouts
::: tip To use the bindings from this module:
``` scheme
(import :std/misc/timeout)
```
:::

### make-timeout
``` scheme
(make-timeout t [def = absent-obj]) -> time object | def | error

  t   := real number in seconds | time object | #f (false value)
  def := default value returned in case t is #f
```

Creates a time object representing a time point relative to the current time.
These time objects are used as timeout input parameters for synchronization
primitives in modules such as `:gerbil/gambit/threads` or `:std/misc/channel`:

- `(thread-sleep! timeout)`
- `(thread-join! thread [timeout [timeout-val]])`
- `(mutex-lock! mutex [timeout [thread]])`
- `(mutex-unlock! mutex [condition-variable [timeout]])`
- `(channel-put channel value [time-object])`
- `(channel-get channel [time-object [default]])`

`make-timeout` expects *t* to be exact or inexact real number in seconds; a time
point object satisfying `time?`, in which case it returns *t* itself; or `#f`,
which is often the case for gerbil's internal usage of `make-timeout`, returning
the optional default parameter *def* instead.

Signals an error when *t* is something other than a real number, a time object or `#f`.

::: tip Examples:
``` scheme
> (import :gerbil/gambit/threads)
> (thread-sleep! (make-timeout 10))
  ; no output, but will take ten seconds to complete
```
:::

## UUIDs
::: tip To use the bindings from this module:
``` scheme
(import :std/misc/uuid)
```
:::

Bindings to generate, recognize, and convert from and to *universally unique
identifiers* (UUID) for identification purposes.

Example UUID: `dae92f43-4a98-fde7-f559-c2b4c2665138`.

### UUID
``` scheme
(UUID uuid) -> uuid | error
(UUID str)  -> uuid | error
(UUID vec)  -> uuid | error
(UUID sym)  -> uuid | error

  uuid := uuid object, will be returned
  str  := string representation to convert from
  vec  := u8vector representation to convert from
  sym  := symbolic representation to convert from
```

Creates a new uuid object from various input objects. It accepts the following inputs:

- an already constructed object, which will then be simply returned,
- a string,
- an u8vector of 16 elements,
- and finally, a symbol that's first converted to a string and processed further.

`UUID` signals an error when any of these inputs are invalid UUID representations.

::: tip Examples:
``` scheme
> (def ustr (uuid->string (random-uuid)))
> (uuid=? (UUID ustr)
          (UUID (string->symbol ustr)))
#t
```
:::

### uuid-length
``` scheme
(def uuid-length 16)
```

Variable that holds the number of octets that are making up the UUID.

### make-uuid
``` scheme
(make-uuid vec str) -> uuid

  vec := uuid object u8vector representation
  str := uuid object string representation
```

Creates a new uuid object from *vec*, a u8vector representation, and *str*, a
string-representation. If *str* is specified as `#f`, then the string
representation will be generated on demand by procedures like `uuid->string`.

::: tip Examples:
``` scheme
;; possible random-uuid implementation:
> (import (only-in :std/crypto/etc random-bytes!))
> (def (random-uuid)
    (let (bytes (make-u8vector uuid-length))
      (random-bytes! bytes)
      (make-uuid bytes #f)))

> (uuid->string (random-uuid))
"e26a747f-2a17-aad1-2cdf-504a25e98d02"
```
:::

### uuid?
``` scheme
(uuid? uuid) -> boolean

  uuid := uuid object to check
```

Checks whether *uuid* is an actual uuid object.

::: tip Examples:
``` scheme
> (uuid? "337649b0-ec36-6c80-5d06-53f5586e6322")
#f

> (uuid? (string->uuid "337649b0-ec36-6c80-5d06-53f5586e6322"))
#t
```
:::

### uuid=?
``` scheme
(uuid=? u1 u2) -> boolean

  u1, u2 := uuid object to compare
```

Compares the uuid objects *u1* and *u2* and checks whether these two are equal.
Two uuid objects are equal when their byte representations are `equal?`.

::: tip Examples:
``` scheme
> (uuid=? (string->uuid "98ac7df1-204a-7932-dfdf-f466f9c9acff")
          (string->uuid "a8a695fd-7d0e-bd55-46a8-5a5951500b4b"))
#f

> (def u1 (u8vector->uuid #u8(227 124 73 208 223 79 147 3 57 65 100 56 99 245 171 80)))
> (def u2 (string->uuid "e37c49d0-df4f-9303-3941-643863f5ab50"))
> (uuid=? u1 u2)
#t
```
:::

### uuid-hash
``` scheme
(uuid-hash uuid) -> fixnum

  uuid := uuid object to hash
```

Returns the hash number of *uuid*, which is a small exact integer (fixnum). Two
uuid objects have the same hash value when their byte representations are
`equal?`.

::: tip Examples:
``` scheme
> (uuid-hash (random-uuid))
318443048

> (def u1 (u8vector->uuid #u8(227 124 73 208 223 79 147 3 57 65 100 56 99 245 171 80)))
> (def u2 (string->uuid "e37c49d0-df4f-9303-3941-643863f5ab50"))
> (= (uuid-hash u1) (uuid-hash u2))
#t
```
:::

### uuid-&gt;u8vector
``` scheme
(uuid->u8vector uuid) -> u8vector

  uuid := uuid object to convert
```

Converts *uuid* to its byte vector representation of length `uuid-length`.

::: tip Examples:
``` scheme
> (uuid->u8vector (random-uuid))
#u8(70 222 137 224 229 154 122 182 255 30 187 147 111 209 17 29)
```
:::

### u8vector-&gt;uuid
``` scheme
(u8vector->uuid vec) -> uuid | error

  vec := u8vector to convert
```

Converts *vec*, a u8vector representing a UUID, to an actual uuid object.
Signals an error when *vec*'s length doesn't match `uuid-length`, which is
predefined to be 16.

::: tip Examples:
``` scheme
> (def vec #u8(159 202 105 225 118 206 224 215 234 228 189 63 150 185 213 53))
> (u8vector-length vec)
16

> (uuid->string (u8vector->uuid vec))
"9fca69e1-76ce-e0d7-eae4-bd3f96b9d535"
```
:::

### uuid-&gt;string
``` scheme
(uuid->string uuid) -> string

  uuid := uuid object to convert
```

Converts *uuid* to its easier to read string representation.

::: tip Examples:
``` scheme
> (uuid->string (random-uuid))
"c6bc8cd8-88c9-64fb-bddb-2bed2c663ed7"

> (uuid->string (string->uuid "ce2c3a97-504c-0926-dddd-0d2571b9a683"))
"ce2c3a97-504c-0926-dddd-0d2571b9a683"
```
:::

### string-&gt;uuid
``` scheme
(string->uuid str) -> uuid | error

  str := string representing a UUID to convert
```

Converts *str*, a hex string representing a UUID, to an actual uuid object.
Signals an error when *str* is malformed.

::: tip Examples:
``` scheme
> (string->uuid "39fc54b8-6c00-9ec7-638f-4bb2b83abb0a")
#<uuid #386>

> (uuid->string (string->uuid "ce2c3a97-504c-0926-dddd-0d2571b9a683"))
"ce2c3a97-504c-0926-dddd-0d2571b9a683"
```
:::

### random-uuid
``` scheme
(random-uuid) -> uuid
```

Generates a new pseudo-random UUID.

::: tip Examples:
``` scheme
> (uuid->string (random-uuid))
"eb362448-93bb-f69f-9a90-e5eec79bc0a2"

> (uuid->string (random-uuid))
"78a9cf92-d3c0-eb38-cd16-6a18251ef3f6"
```
:::


## Functional utilities
::: tip To use the bindings from this module:
``` scheme
(import :std/misc/func)
```
:::

Collection of mixed purpose higher-order functions.

### always
``` scheme
(always val)            -> lambda
(always proc [arg ...]) -> lambda

  val     := value that should always be returned
  proc    := procedure that should always be called
  arg ... := optional arguments that will be passed to proc
```

Creates a lambda which returns the same *val* or calls always the
same *proc* with the same optional *args*.

::: tip Examples:
``` scheme
> (def fn (always 5))
> (list (fn) (fn) (fn)))
(5 5 5)

> (def fn (always (lambda () "hi")))
> (fn)
"hi"

> (def fn (always random-integer 10)
> (list (fn) (fn) (fn))
(4 3 8)
```
:::

### repeat
``` scheme
(repeat val n)            -> list
(repeat proc n [arg ...]) -> list

  val     := value that should be repeated
  proc    := proc that should be called n times
  n       := exact number, repetitions
  arg ... := optional arguments that will be passed to proc
```

Repeat *val* or call *proc* with the optional *args* *n* times and return the
result as list. *n* is expected to be an exact number.

::: tip Examples:
``` scheme
> (repeat 2 5)
(2 2 2 2 2)

> (repeat (lambda () 10) 3)
(10 10 10)

> (repeat random-integer 3 10)
(8 3 5)
```
:::

### compose1
```scheme
(compose1 f1 f ...) -> procedure

  f1, f ... := procedures
```

Composes a sequence of unary functions; per the mathematical function composition
the value flows right-to-left.

### rcompose1
```scheme
(rcompose1 f1 f ...) -> procedure

  f1, f ... := procedures
```

Like `compose1`, but the value flows left-to-right.

### compose
```scheme
(compose f1 f ...) -> procedure

  f1, f ... := procedures
```

Like `compose1`, but the composed function accepts multiple arguments.

Note: If you are composing unary functions, use `compose1`, as it avoids allocation
from capturing arguments for apply.

### rcompose
```scheme
(rcompose f1 f ...) -> procedure

  f1, f ... := procedures
```

Like `compose`, but the values flow left-to-right.

### compose/values
```scheme
(compose/values f1 f ...) -> procedure

  f1, f ... := procedures
```

Like `compose`, but the composed function accepts multiple arguments and all functions
can return multiple values, which are then applied as arguments to the next function in
the sequence.


### rcompose/values
```scheme
(rcompose/values f1 f ...) -> procedure

  f1, f ... := procedures
```

Like `compose/values`, but the values flow left-to-right.

### Functional composition macros
```scheme
(@compose1 f1 f ...)
(@compose f1 f ...)
(@compose/values f1 f ...)
(@rcompose1 f1 f ...)
(@rcompose f1 f ...)
(@rcompose/values f1 f ...)
```

These are macro versions of the functional composition operators; they generate
significantly more efficient code and allow the optimizer to see through the composition.

### pred-limit
``` scheme
(pred-limit pred limit) -> procedure

  pred  := predicate
  limit := number of times pred is allowed to return a truthy value
```

`pred-limit` returns a predicate which returns a truthy value only `limit` times,
if `limit` is not false.


::: tip Examples:
``` scheme
> (filter (pred-limit even? 1) [1 2 3 4 5 6])
(2)

(def (myfilter pred list (limit #f))
  (filter (pred-limit pred limit) list))

> (myfilter even? [1 2 3 4 5 6])
(2 4 6)

> (myfilter even? [1 2 3 4 5 6] 2)
(2 4)

> (myfilter even? [1 2 3 4 5 6] 0)
()
```
:::
