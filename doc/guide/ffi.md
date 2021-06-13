# Getting Started with FFI

This is a quick guide to help you with your first FFI steps with Gerbil.

The first thing to note is that FFI in Gerbil is actually delegated to Gambit, where the
mechanism to interface with C is known as the C-interface. It is therefor important to read
section [19. C-interface](https://www.iro.umontreal.ca/~gambit/doc/gambit.html#C_002dinterface)
of the Gambit manual for a complete detailing of the interface.

The primary mechanism for delegating code directly to Gambit is the `begin-foreign` special form:
```
(begin-foreign body ...)
```
Using the form, the `body` is included unexpanded directly to the generated Gambit code for compilation with gsc.

## Basic FFI

We'll start our foray with a basic example: we are going to query for the version of glibc on the current machine. The C code that achieves this:

```c
#include <stdio.h>
#include <gnu/libc-version.h>
int main (void) { puts (gnu_get_libc_version ()); return 0; }
```

We need to write a file module that will define and export an identifier `get-glibc-version`. Subsequently, we'll import that identifier and use it in the Gerbil runtime.

```
# Create a gerbil.pkg file for our project
$ cat > gerbil.pkg <<EOF
(package: myuser)
EOF
$ cat > libc-version.ss <<EOF
(export get-glibc-version)
(extern get-glibc-version)
(begin-foreign
  (namespace ("myuser/libc-version#" get-glibc-version))
  (c-declare "#include  <gnu/libc-version.h>")
  (define get-glibc-version (c-lambda () char-string "gnu_get_libc_version")))
EOF
```

File modules take their name from the including file, so this module is named 'libc-version' in the 'myuser' package and as a result uses `myuser/libc-version#` as the namespace prefix.

To feed code straight to the Gambit compiler from Gerbil we use the `begin-foreign` special form. We namespace the identifier with the package and module to adhere to the canonical namespace of the module.

We compile the module.

```bash
$ gxc libc-version.ss
```

We're now ready to use the module.

```bash
$ gxi
> (import :myuser/libc-version)
> (get-glibc-version)
"2.26"
```

Did you notice the compilation warning?

```
/usr/local/Gambit/v4.8.9/include/gambit.h:7262:32: warning: assignment discards ‘const’ qualifier from pointer target type [-Wdiscarded-qualifiers]
 #define ___CFUN_ASSIGN(r,val)r = val;
                                ^
libc-version__0.c:179:1: note: in expansion of macro ‘___CFUN_ASSIGN’
 ___CFUN_ASSIGN(___result,gnu_get_libc_version())
 ^~~~~~~~~~~~~~
```

That is because gsc doesn't have a const qualifier. We can work around it by replacing the original call with an equivalent call that performs explicit casting.

```
(define get-glibc-version (c-lambda () char-string "___return((char*)gnu_get_libc_version());"))
```
Et voilà, no more compilation warning!

## The begin-ffi macro

In order to simplify writing FFI code, Gerbil offers the `begin-ffi` macro in the `:std/foreign` library.

The macro takes care of providing the extern and namespace declarations for your identifiers.

It also defines some common utility macros:
- `(define-c-lambda id args ret [name/code])` which expands to the definition of a c-lambda.
- `(define-const id)` which expands to a definition that evals the constant in C.
- `(define-const* id)` which conditionally defines the constant to a value of `#f` if it is undefined in the C preprocessor.
- `(define-guard defn)` which conditionally expands a definition with an accompanied cond-expand feature.
- `(define-with-errno id ffi-id args)` which expands to a definition of `(id args ...)` which calls `(ffi-id args ...)` and returns the negated errno if the result is negative.
  This is useful for wrapping C/POSIX FFI functions that report errors using `errno`.
- `(define-c-struct struct-name members release-function compatible-tags as-typedef)` which is detailed below.

In addition, it provides a few other preprocessor macros and a definition of `ffi_free`, a function suitable as a release function for FFI types.

Using `begin-ffi` the previous example would be written as follows:
```
(import :std/foreign)
(export get-glibc-version)
(begin-ffi (get-glibc-version)
  (c-declare "#include  <gnu/libc-version.h>")
  (define-c-lambda get-glibc-version () char-string "gnu_get_libc_version"))
```

If you want to find more about Gerbil FFI programming, the std lib sources for the [os package](https://github.com/vyzo/gerbil/tree/master/src/std/os) are a good starting point.

## Interfacing with C structs

In order to make interfacing with C structs a bit easier, the macro `define-c-struct`
is provided to be used inside the `begin-ffi` block. It will create a number of Scheme
foreign types, allocation and utility procedures, as well as accessors for optionally
declared struct members.

### Overview

Consider a C struct `X` with members `a` of type `t1` and `b` of type `t2`. The most basic
usage of `define-c-struct` is to simply provide `struct-name` as a symbol matching the
structure's *tag* of `X`:

```scheme
(c-declare "

struct X {
  t1 a;
  t2 b;
}

")

(define-c-struct X)
```

Without speciying any members, the interface treats `X` as opaque, as no accessors are
generated. The following Scheme foreign types are generated by the macro:

```scheme
(c-define-type X  (struct "X" (X)))  ; The struct type.

; Pointer type to which the custom release function is provided:
(c-define-type X* (pointer X (X*) <configurable-release>))
; <configurable-release>:
;   "ffi_free"                 ; Default, no string members
;   "<struct-name>_ffi_free"   ; Generated when string members present
;   "custom_release_function"  ; User specified `release-function`

; Similar to X*, but with no release function:
(c-define-type X-borrowed-ptr* (pointer X (X*)))

; Similar to X*, but with release function of "ffi_free".
; (Only generated when string members present):
(c-define-type X-shallow-ptr* (pointer X (X*) "ffi_free"))
```

Note that in the case above, if `t1` or `t2` are string types, then a C function
"X_ffi_free" is generated and assigned as the release-function of the pointer type
to perform cleanup of strings in addition to the struct. Where a user specified
release-function is provided, as in the case below, it would take precedent, and
care should be taken to provide the neccessary cleanup.

Furthermore, the following procedures are generated by the macro:

```scheme
(X-ptr? foreign-obj)  ; X Predicate test using `foreign-tags`
(malloc-X)            ; malloc X and return a X* to it
(ptr->X x-ptr)        ; Dereference a pointer to an X
(malloc-X-array n)    ; malloc N * sizeof X
  ; The returned pointer type is X-shallow-ptr* when string
  ; members are present, otherwise the type is X*
(X-array-ref x-ptr i) ; Obtain an X-borrowed-ptr* with offset
  ; `i` starting at `x-ptr`
(X-array-set! x-ptr i val-ptr) ; Set the value of `x-ptr` offset
  ; by `i` to be `val-ptr`
```

Specifying members of the struct will additionally generate accessors for those members.
All members of the struct need not be specified. The below use of `define-c-struct`
refines the call above to specify an interest only in member `b`, along with the a user
defined `release-function` called "my_release_function":

```scheme
(define-c-struct X ((b . t2)) "my_release_function")
```

This would generate the following accessors for member `b`:

```scheme
(X-b x-ptr)              ; Getter for member `b`
(X-b-set! x-ptr t2-val)  ; Setter for member `b`
```

Special compatibility is provided for setting new values to members of string types.
New values are `strdup` before being set to the member. When the member is already
pointing to another string, it is freed prior to assigning the new value.

In order to export the generated procedures, one would include `(struct X a b)` as an
'id' in the externs part of the `begin-ffi` form as follows:
```scheme
(begin-ffi (... (struct X a b) ...) ...)
```

### `typedef` Aliased Structs

It is common for C structs to be aliased by `typedef`, and many times the structs 
themselves are anonymous. On the C side of things, compilers are smart enough to 
recognize that a struct tag and a typedef alias may be different names for the same
type. But without some extra help, the Scheme side of things has no way of knowing
about the compatibility of a foreign type representing the struct and one representing
the typedef by a different name. Expectedly, Gambit has a solution as part of its
C-interface, what it refers to as *"The optional tags field of foreign type
specifications,"* as detailed in section
[19.1 The Mapping of Types between C and Scheme](https://www.iro.umontreal.ca/~gambit/doc/gambit.html#mapping-of-types)
paragraph 5.

With `define-c-struct`, an optional list of `compatible-tags` may be specified. This
has the effect of easing Scheme side foreign-object type checking (without completely
disabling it) and allows, for example, the generated accessors to operate on these
compatible types.

In the following example, a struct detailing a cartesian `point` is aliased as `coords`:

```scheme
(c-declare "

// struct tag 'point' differs from typedef alias 'coords'
typedef struct point {
  int x;
  int y;
} coords;

// Consider an inconsistant codebase, where functions may type their
// parameters and return values with both `struct point` and the
// typedef alias `coords`.

coords *skew_coords(coords *c) { ... }
struct point *legacy_function(struct point *pnt) { ... }

")

; Standard foreign-object type declaration for `coords`.
; Notice the addition of `point` and `points*` to the tags fields:
; It allows for a `point*` to be sent to `skew_coords`.
(c-define-type coords  (type "coords" (coords point)))
(c-define-type coords* (pointer coords (coords* point*)))

(define-c-struct point   ; `point` matches C struct tag.
  ((x . int) (y . int))  ; Declare accessors for both members.
  #f (coords))           ; Specify 'coords' as a compatible C type:
  ; It allows for accessors `point-x`, etc. to be used on `coords*`,
  ; and for foreign-objects typed `coords*` to be passed to
  ; `legacy_function`.
```

Because the foreign-object types for `coords` and `point` include eachother's type
as part of their *foreign tags,* it is accepted by the C-interface that objects of
these types be interchangable.

Whether it is neccessary to deal with both a struct type and a typedef type, depends
on the C code being interfaced. If in the C code, function parameters and return
values are typed with both `struct point` and `coords`, a configuration like the
above is required. However, if the C code is careful to use only the alias type
for instance, as in the case with typedef anonymous structs, one may forego the
issue of compatible types all together as illustracted in the following refined
example:

```scheme
(c-declare "

// typedef anonymous struct, no struct tag given
typedef struct {
  int x;
  int y;
} coords;

coords *skew_coords(coords *c) { ... }

")

; If one used the standard foreign-object type declaration for `coords`,
; it would be treated as an opaque object, without access to members.
;(c-define-type coords  (type "coords"))
;(c-define-type coords* (pointer coords))

; Instead, configure `define-c-struct` to operate on the typedef alias:
(define-c-struct coords  ; `coords` matches typedef alias. *!*
  ((x . int) (y . int))  ; Declare accessors for both members.
  #f #f #t)  ; Set `as-typedef` to `#t` for anonymous struct.
```

As you can see the macro offers flexibility for providing access to C structs
with regards to the variety of ways they may be declared and used in C.

### Sample

In the following contrived sample 'point-polar.ss', three structs are used to illustrate features
of `define-c-struct`, and particularly foreign-object *compatible types*. Two
structs represent cartesian and polar coordinates, respectively. The third collects
formatted strings for a question and answer. The C function `point_to_polar` converts
a cartesian coordinate to a polar coordinate, while `print_q_and_a` takes references
to each of the three structs to output the formatted results.

```scheme
package: sample

(import :std/foreign)

(export #t)

(begin-ffi ((struct cartesian_coord x y)
            (struct polar_coord r a)
            (struct q_and_a q a)
            point-to-polar
            print-q-and-a)

  (c-declare #<<c-declare-end

#include <stdio.h>
#include <math.h>

#define PI 3.141592654

// A typedef struct representing a cartesian coordinate.
typedef struct cartesian_coord {
  double x;
  double y;
} point;

// A typedef struct representing a polar coordinate.
typedef struct polar_coord {
  double r;
  double a;
} polar;

// A typedef anonymous struct representing
// a formatted question and answer.
typedef struct {
  char* q;
  char* a;
} q_and_a;

// A function to convert a cartesian coordinate to
// a polar coordinate.
polar *point_to_polar(point *pnt) {
  polar *plr = (polar *) malloc(sizeof(polar));
  plr->r = hypot(pnt->x, pnt->y);
  plr->a = 0.0;
  if(pnt->x == 0.0) {
    if(pnt->y > 0.0) plr->a =  PI / 2.0;
    if(pnt->y < 0.0) plr->a = -PI / 2.0;
  } else {
    plr->a = atan2(pnt->y, pnt->x);
  }
  return plr;
}

// A function to print out the question and answer
// to a cartesian to polar coordinate conversion.
void print_q_and_a(q_and_a *qa, struct cartesian_coord *pnt, struct polar_coord *plr) {
  printf(qa->q, pnt->x, pnt->y);
  printf(qa->a, plr->r, plr->a);
}

c-declare-end
  )

  ; Foreign-object type declarations for `point` and `polar`.
  ; Notice the addition of `cartesian_coord*` as a non-primary tag for
  ; `point*`. This tells Scheme that a foreign-object tagged `cartesian_coord*`
  ; is acceptable (and type compatible) where one of `point*` is expected. It
  ; is what allows for `cc-ref` to be passed as an argument to `point-to-polar`
  ; in the interactive session below.
  (c-define-type point  (type "point" (point cartesian_coord)))
  (c-define-type point* (pointer point (point* cartesian_coord*)))
  (c-define-type polar  (type "polar" (polar polar_coord)))
  (c-define-type polar* (pointer polar (polar* polar_coord*)))

  (define-c-struct cartesian_coord
    ((x . double) (y . double))
    #f (point))  ; Likewise, `point` is specified as a compatible type where a
                 ; foreign-object tagged `cartesian_coord` is expected. Such is
                 ; the case with the generated accessors for this struct type.

  (define-c-struct polar_coord
    ((r . double) (a . double))
    #f (polar))  ; `polar` is specified as a compatible type of `polar_coord`.
                 ; Similarly, it is what allows the generated accessors to
                 ; opperate on foreign-objects tagged `polar`, and for `polar-ref`
                 ; to be passed as an argument to `print_q_and_a`, as shown in
                 ; the interactive session below.

  (define-c-struct q_and_a  ; `q_and_a` matches the typedef alias. *!*
    ((q . char-string) (a . char-string))
    #f #f #t)    ; Set `as-typedef` as #t for anonymous struct.

  ; Interface with the C functions.
  (define-c-lambda point-to-polar (point*) polar* "point_to_polar")
  (define-c-lambda print-q-and-a  (q_and_a* cartesian_coord* polar_coord*) void "print_q_and_a"))
```

The following interactive session shows use of the interface defined above.

```
$ gxi
> (import :sample/point-polar)
> (import :std/foreign)
> (def cc-ref (malloc-cartesian_coord))
> (foreign-tags cc-ref)
(cartesian_coord* point*)
> (cartesian_coord-x-set! cc-ref 12.)
> (cartesian_coord-y-set! cc-ref 5.)
> (def polar-ref (point-to-polar cc-ref))
> (foreign-tags polar-ref)
(polar* polar_coord*)
> (polar_coord-r polar-ref)
13.
> (polar_coord-a polar-ref)
.3947911196997615
> (def q&a (malloc-q_and_a))
> (foreign-tags q&a)
(q_and_a*)
> (q_and_a-q-set! q&a "What are the polar coordinates of point (x = %.1lf, y = %.1lf)? \n")
> (q_and_a-a-set! q&a "The polar coordinates are (r = %.1lf, a = %.1lf). \n")
> (print-q-and-a q&a cc-ref polar-ref)
What are the polar coordinates of point (x = 12.0, y = 5.0)? 
The polar coordinates are (r = 13.0, a = 0.4). 
```

## Interfacing with a custom C program

This example shows how to compile and link a C module to a Gerbil module, in order to call functions and return constants from the former.

Consider a simple module written in C defining two functions, f1 and f2:

```
$ cat ffi-pi.h
#ifndef _ffi_pi_h
#define _ffi_pi_h
double f1(void); 
double f2(double x);
#endif

$ cat ffi-pi.c
#include <stdlib.h>
#include <math.h>
#include "ffi-pi.h"

double f1(void) {
  return M_PI;
}

double f2(double x) {
  return asin(x) - asin(-x);
}
```

Compiling ffi-pi.c:

```
$ gcc -Wall -c ffi-pi.c
```

Now, the Gerbil code: 

```
$ cat ffi-pi.ss
package: ffi-example

(import :std/foreign
        :std/format
        :std/iter)

(export #t)

(begin-ffi (M_PI f1 f2)
  (c-declare "#include <math.h>")
  (c-declare "#include \"ffi-pi.h\"")
  (define M_PI ((c-lambda () double "___return(M_PI);")))
  (define pi (c-lambda () double "___return(M_PI);"))
  (define-c-lambda f1 () double "f1")
  (define-c-lambda f2 (double) double "f2")
  )
```

Note that there are two definitions for number pi: the first, M_PI is a constant and the second is a function.

Compile that with:

```
gxc -ld-options `pwd`/ffi-pi.o -cc-options -I`pwd` ffi-pi.ss
```

And use the module:

```
$ gxi
Gerbil v0.16-133-gfdfdcb5d on Gambit v4.9.3-1232-gbba388b8
> (import :ffi-example/ffi-pi)
> (= M_PI (pi))
#t
> (= M_PI (f1))
#t
> (= (f1) (f2 1.0))
#t
```
