# Utilities for FFI Programming

::: tip usage
(import :std/foreign)
:::

## begin-ffi
::: tip usage
```
(begin-ffi (id ...) body ...)

; expands to
(extern id ...)
(begin-foreign
  (namespace (<module-namespace> id ...))
  prelude-macros ...
  prelude-decls ...
  body ...
  prelude-defs ...)
```
:::

### Prelude Macros

The following prelude macros are made available within the body:
```
(define-c-lambda id args ret [name/code])
(define-const id)
(define-const* id)
(define-guard guard defn)
(define-with-errno id ffi-id args)
(define-c-struct struct-name members release-function compatible-tags as-typedef)
```

#### define-c-struct

```scheme
(define-c-struct struct-name [members [release-function [compatible-tags [as-typedef]]]])

<struct-name>:
  c-struct-tag: symbol     ; Where symbol->string is the C structure tag
  c-typedef-alias: symbol  ; Where symbol->string is the C typedef alias (with as-typedef = #t)

<members>:
  ( (member-name . sheme-notation-type) ... )  ; Any or all members need not be specified.

<release-function>:
  #f  ; The default, in which case "ffi_free" or, if string members are present,
      ; "<struct-name>_ffi_free" will be configured as cleanup function called by the gc.
  c-function-name: string  ; The name of a custom C function handling cleanup.

<compatible-tags>:
  (c_type ...)  ; Additional C type declarations, where symbol->string is a C type
                ; compatible with the type defined by this struct.

as-typedef: boolean  ; Default is #f. Set to #t when struct-name describes a typedef alias.
                     ; This is the case for defining an anonymous struct via a typedef.
```
The `define-c-struct` macro works to create the necessary Scheme foreign types, accessors,
and utility procedures useful for interfacing with C structs. It is operable on standard
structs, their compatible typedef alias', as well as typedef'd anonymous structs.

In the case of interfacing with stand-alone and typedef aliased structs, `struct-name`
should be a symbol matching that of the C structure tag. Additionally, in the case of a
typedef aliased struct, if the struct tag and typedef alias are differently named, the
alias type (along with any other compatible type) may be specified in `compatible-tags`.
This will ease the Scheme side foreign-object type checking and allow, for example, the
generated accessors to operate on these compatible types.

> Note that the use of 'tag' here in *'struct tag'* and *'compatible-tags'* are a
> clash of two completely different concepts. With *'struct tag'*, tag refers to the name
> given to the struct in C. A tag in the context of *'compatible-tags'*, are part of Gambit's
> solution of specifying compatible C types when working with its C-Interface mechanism.
> Without specifying compatible tags, the Scheme side of things has no way of knowing types
> defined by the struct and typedef are essentially the same.
>
> See Section [19.1 The Mapping of Types between C and Scheme](https://www.iro.umontreal.ca/~gambit/doc/gambit.html#mapping-of-types),
> paragraph 5: "The optional tags field of foreign type specifications..." for more details.

In the case of interfacing with a typedef'd anonymous struct, `struct-name` should be a
symbol matching that of the C typedef alias, and additionally, `as-typedef` should be set
to `#t`. This interfacing method may also be used with typedef aliased structs which are
tagged (non-anonymous), where a Scheme side foreign struct type is not needed.

`members` may be ommited, in which case one treats the struct as opaque. Furthermore, all
members need not be specified when not needed.

Note that when `release-function` is not provided, a default cleanup function will be
configured. When there are no string members, the default cleanup function is "ffi_free"
(defined in Prelude Definitions). When string members are present, a cleanup function is
provided by the macro which includes release of string members.

::: tip Example
```scheme
(import :std/foreign)
(export #t)

(begin-ffi ((struct stand_alone i a)
            (struct point x y)
            (struct anonymous msg))

  (c-declare #<<c-declare-end

// standard struct
struct stand_alone {
  int i;
  char* a;
}

// typedef struct with tag 'point', alias 'coords'
typedef struct point {
  int x;
  int y;
} coords;

// typedef anonymous struct
typedef struct {
  int k;
  char* msg;
} anonymous;

// a special cleanup function
___SCMOBJ some_special_cleanup (void *ptr) {
  free (ptr);
  // Other special stuff ...
  return ___FIX (___NO_ERR);
}

c-declare-end
  )

(define-c-struct stand_alone      ; `struct-name` matches C struct tag.
  ((i . int) (a . char-string)))  ; Declare accessors for both members.

(define-c-struct point   ; `struct-name` matches C struct tag.
  ((x . int) (y . int))  ; Declare accessors for both members.
  #f (coords))           ; Specify 'coords' as a compatible C type.

(define-c-struct anonymous  ; `struct-name` matches typedef alias.
  ((msg . char-string))     ; Only care about the 'msg' member.
  "some_special_cleanup"    ; Specify some special release-function.
  #f #t)                    ; Set `as-typedef` to `#t` for anonymous struct.

; Alternatively, where one only needs to deal with coords:
(define-c-struct coords
  ((x . int) (y . int)) #f #f #t)
```
:::



### Prelude Declarations

The following declarations are included before the body:
```
#include <stdlib.h>
#define U8_DATA(u8vector) ...
#define U8_LEN(u8vector) ...
static ___SCMOBJ ffi_free (void *ptr);
```

### Prelude Definitions

The following definitions are included after the body:
```
#ifndef ___HAVE_FFI_FREE
#define ___HAVE_FFI_FREE
___SCMOBJ ffi_free (void *ptr) { ... }
#endif
```
