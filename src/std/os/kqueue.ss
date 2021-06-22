;;; -*- Gerbil -*-
;;; (C) vyzo at hackzen.org
;;; OS kqueue interface [bsd]

(require bsd)

(import :gerbil/gambit/threads
        (only-in :gerbil/gambit/ports close-port)
        :std/foreign
        :std/os/error
        :std/os/fd
        :std/os/fcntl)

(export kqueue kqueue-close
        make-kevents kevent-set!
        kevent kqueue-poll
        kqueue-kevent-add kqueue-kevent-del kqueue-kevent-disable
        kevent-ident kevent-filter kevent-flags
        kevent-fflags kevent-data kevent-udata
        set-kevent-ident! set-kevent-filter! set-kevent-flags!
        set-kevent-fflags! set-kevent-data! set-kevent-udata!

        EV_ADD EV_ENABLE EV_DISABLE EV_DELETE EV_ONESHOT
        EV_CLEAR EV_EOF EV_ERROR EVFILT_READ EVFILT_WRITE EVFILT_VNODE
        EVFILT_PROC EVFILT_SIGNAL EVFILT_TIMER NOTE_WRITE NOTE_DELETE
        NOTE_EXTEND NOTE_ATTRIB NOTE_LINK NOTE_RENAME NOTE_REVOKE
        NOTE_LOWAT NOTE_EXIT NOTE_FORK NOTE_EXEC)

(cond-expand
  (openbsd
   (export EV_DISPATCH EV_RECEIPT EVFILT_DEVICE NOTE_TRUNCATE NOTE_TRACK
           NOTE_TRACKERR NOTE_CHANGE))
  (netbsd
   (export #;EV_DISPATCH #;EV_RECEIPT EVFILT_AIO #;EVFILT_FS NOTE_TRACK
                                      NOTE_TRACKERR))
  (freebsd
   (export EV_DISPATCH EV_RECEIPT EVFILT_AIO EVFILT_PROCDESC EVFILT_USER
           NOTE_CLOSE NOTE_CLOSE_WRITE NOTE_OPEN NOTE_READ NOTE_TRACK
           NOTE_SECONDS NOTE_MSECONDS NOTE_USECONDS NOTE_NSECONDS
           NOTE_FFNOP NOTE_FFAND NOTE_FFOR NOTE_FFCOPY
           NOTE_FFCTRLMASK NOTE_FFLAGSMASK))
  (darwin
   (export EV_OOBAND EV_RECEIPT #;EVFILT_EXCEPT EVFILT_AIO EVFILT_MACHPORT
           #;NOTE_OOB #;NOTE_FUNLOCK NOTE_EXITSTATUS
           NOTE_SIGNAL NOTE_REAP NOTE_SECONDS NOTE_USECONDS
           NOTE_NSECONDS #;NOTE_MACHTIME NOTE_ABSOLUTE NOTE_CRITICAL
           NOTE_BACKGROUND NOTE_LEEWAY)))

(def (kqueue)
  (let* ((fd (check-os-error (_kqueue) (kqueue)))
         (raw (fdopen fd 'in 'kqueue)))
    (fd-set-closeonexec raw)
    raw))

(def (kqueue-close kq)
  (close-port kq))

(def (make-kevents size)
  (check-ptr (make_kevents size)))

(def (kevent-set! kevts ix
                  ident: ident     filter:       filter
                  flags: (flags 0) filter-flags: (filter-flags 0)
                  data:  (data 0)  user-data:    (user-data #f))
  (ev_set kevts ix ident filter flags filter-flags data user-data))

(def (kevent kqueue change-list nchanges event-list nevents)
  (do-retry-nonblock
   (_kevent (fd-e kqueue) change-list nchanges event-list nevents
            timespec-zero)
   (kevent kqueue change-list nchanges event-list nevents)))

(def (kqueue-poll kqueue events nevents)
  (kevent kqueue #f 0 events nevents))

(def (kqueue-kevent-add kqueue dev filter (additional-flags 0) (filter-flags 0) (data 0))
  (let (kevt (get-kevent-ptr))
    (kevent-set! kevt 0
     ident: (if (fd? dev) (fd-e dev) dev)
     flags: (##fxior EV_ADD additional-flags)
     filter: filter
     filter-flags: filter-flags
     data: data)
    (kevent kqueue kevt 1 #f 0)))

(def (kqueue-kevent-del kqueue dev filter)
  (let (kevt (get-kevent-ptr))
    (kevent-set! kevt 0
     ident: (if (fd? dev) (fd-e dev) dev)
     flags: EV_DELETE
     filter: filter)
    (kevent kqueue kevt 1 #f 0)))

(def (kqueue-kevent-disable kqueue dev filter)
  (let (kevt (get-kevent-ptr))
    (kevent-set! kevt 0
     ident: (if (fd? dev) (fd-e dev) dev)
     flags: EV_DISABLE
     filter: filter)
    (kevent kqueue kevt 1 #f 0)))

(def kevent-ptr-key
  'std/os/kqueue#kevent-ptr)

(def (get-kevent-ptr)
  (cond
   ((thread-local-get kevent-ptr-key)
    => values)
   (else
    (let (kevent-ptr (check-ptr (make_kevents 1)))
      (thread-local-set! kevent-ptr-key kevent-ptr)
      kevent-ptr))))

(def timespec-zero (make-timespec 0 0))

(def (make-timespec seconds nanoseconds)
  (let (timespec (check-ptr (make_timespec)))
    (timespec_seconds_set timespec seconds)
    (timespec_nanoseconds_set timespec nanoseconds)
    timespec))

(def kevent-ident kevent_ident)
(def kevent-filter kevent_filter)
(def kevent-flags kevent_flags)
(def kevent-fflags kevent_fflags)
(def kevent-data kevent_data)
(def kevent-udata kevent_udata)

(def set-kevent-ident! kevent_ident_set)
(def set-kevent-filter! kevent_filter_set)
(def set-kevent-flags! kevent_flags_set)
(def set-kevent-fflags! kevent_fflags_set)
(def set-kevent-data! kevent_data_set)
(def set-kevent-udata! kevent_udata_set)

(cond-expand
  (openbsd
   (begin-foreign
     (define-cond-expand-feature openbsd)))
  (netbsd
   (begin-foreign
     (define-cond-expand-feature netbsd)))
  (freebsd
   (begin-foreign
     (define-cond-expand-feature freebsd)))
  (darwin
   (begin-foreign
     (define-cond-expand-feature darwin))))

(begin-ffi
  (EVFILT_AIO EVFILT_DEVICE EVFILT_EXCEPT EVFILT_FS EVFILT_MACHPORT
   EVFILT_PROC EVFILT_PROCDESC EVFILT_READ EVFILT_SIGNAL EVFILT_TIMER
   EVFILT_USER EVFILT_VNODE EVFILT_WRITE

   EV_ADD EV_CLEAR EV_DELETE EV_DISABLE EV_DISPATCH EV_ENABLE EV_EOF
   EV_ERROR EV_ONESHOT EV_OOBAND EV_RECEIPT

   NOTE_ABSOLUTE NOTE_ATTRIB NOTE_BACKGROUND NOTE_CHANGE NOTE_CLOSE
   NOTE_CLOSE_WRITE NOTE_CRITICAL NOTE_DELETE NOTE_EXEC NOTE_EXIT
   NOTE_EXITSTATUS NOTE_EXTEND NOTE_FFAND NOTE_FFCOPY NOTE_FFCTRLMASK
   NOTE_FFLAGSMASK NOTE_FFNOP NOTE_FFOR NOTE_FORK NOTE_FUNLOCK NOTE_LEEWAY
   NOTE_LINK NOTE_LOWAT NOTE_MACHTIME NOTE_MSECONDS NOTE_NSECONDS NOTE_OOB
   NOTE_OPEN NOTE_READ NOTE_REAP NOTE_RENAME NOTE_REVOKE NOTE_SECONDS
   NOTE_SIGNAL NOTE_TRACK NOTE_TRACKERR NOTE_TRUNCATE NOTE_USECONDS
   NOTE_WRITE

   kevent* timespec timespec*
   make_timespec timespec_seconds_set timespec_nanoseconds_set
   _kqueue _kevent
   __kqueue __kevent
   make_kevents
   kevent_ident kevent_ident_set
   kevent_filter kevent_filter_set
   kevent_flags kevent_flags_set
   kevent_fflags kevent_fflags_set
   kevent_data kevent_data_set
   kevent_udata kevent_udata_set
   ev_set)

  (c-declare "#include <sys/types.h>")
  (c-declare "#include <sys/event.h>")
  (c-declare "#include <sys/time.h>")

  (namespace ("std/os/kqueue#" kevent))

  ;; Flags
  (define-const EV_ADD)
  (define-const EV_ENABLE)
  (define-const EV_DISABLE)
  (define-const EV_DELETE)
  (define-const EV_ONESHOT)
  (define-const EV_CLEAR)
  (define-const EV_EOF)
  (define-const EV_ERROR)

  (cond-expand
    ((or openbsd freebsd)
     (define-const EV_RECEIPT)
     (define-const EV_DISPATCH))
    (netbsd
     #;(define-const EV_RECEIPT)
     #;(define-const EV_DISPATCH))
    (darwin
     (define-const EV_RECEIPT)
     (define-const EV_OOBAND)))

  ;; Filters
  (define-const EVFILT_READ)
  (define-const EVFILT_WRITE)
  (define-const EVFILT_VNODE)
  (define-const EVFILT_PROC)
  (define-const EVFILT_SIGNAL)
  (define-const EVFILT_TIMER)

  (cond-expand
    (openbsd
     (define-const EVFILT_DEVICE))
    (netbsd
     (define-const EVFILT_AIO)
     #;(define-const EVFILT_FS))
    (freebsd
     (define-const EVFILT_AIO)
     (define-const EVFILT_PROCDESC)
     (define-const EVFILT_USER))
    (darwin
     #;(define-const EVFILT_EXCEPT)
     (define-const EVFILT_AIO)
     (define-const EVFILT_MACHPORT)))

  ;; Filter Flags
  (define-const NOTE_WRITE)
  (define-const NOTE_DELETE)
  (define-const NOTE_EXTEND)
  (define-const NOTE_ATTRIB)
  (define-const NOTE_LINK)
  (define-const NOTE_RENAME)
  (define-const NOTE_REVOKE)
  (define-const NOTE_EXIT)
  (define-const NOTE_FORK)
  (define-const NOTE_EXEC)
  (define-const NOTE_LOWAT)

  (cond-expand
    (openbsd
     (define-const NOTE_TRUNCATE)
     (define-const NOTE_TRACK)
     (define-const NOTE_TRACKERR)
     (define-const NOTE_CHANGE))
    (netbsd
     (define-const NOTE_TRACK)
     (define-const NOTE_TRACKERR))
    (freebsd
     (define-const NOTE_CLOSE)
     (define-const NOTE_CLOSE_WRITE)
     (define-const NOTE_OPEN)
     (define-const NOTE_READ)
     (define-const NOTE_TRACK)
     (define-const NOTE_SECONDS)
     (define-const NOTE_MSECONDS)
     (define-const NOTE_USECONDS)
     (define-const NOTE_NSECONDS)
     (define-const NOTE_FFNOP)
     (define-const NOTE_FFAND)
     (define-const NOTE_FFOR)
     (define-const NOTE_FFCOPY)
     (define-const NOTE_FFCTRLMASK)
     (define-const NOTE_FFLAGSMASK))
    (darwin
     #;(define-const NOTE_OOB)
     #;(define-const NOTE_FUNLOCK)
     (define-const NOTE_EXITSTATUS)
     (define-const NOTE_SIGNAL)
     (define-const NOTE_REAP)
     (define-const NOTE_SECONDS)
     (define-const NOTE_USECONDS)
     (define-const NOTE_NSECONDS)
     #;(define-const NOTE_MACHTIME)
     (define-const NOTE_ABSOLUTE)
     (define-const NOTE_CRITICAL)
     (define-const NOTE_BACKGROUND)
     (define-const NOTE_LEEWAY)))

  (c-define-type kevent (struct "kevent"))
  (c-define-type kevent*
    (pointer kevent (kevent*) "ffi_free"))

  (define-guard ffi-have-timespec
    (c-define-type timespec (struct "timespec")))
  (define-guard ffi-have-timespec*
    (c-define-type timespec*
      (pointer timespec (timespec*) "ffi_free")))

  (define-c-lambda make_timespec () timespec*
    "___return ((struct timespec*)malloc(sizeof(struct timespec)));")
  (define-c-lambda timespec_seconds_set (timespec* int) void
    "___arg1->tv_sec = ___arg2; ___return ;")
  (define-c-lambda timespec_nanoseconds_set (timespec* int) void
    "___arg1->tv_nsec = ___arg2; ___return ;")

  (define-c-lambda __kqueue () int
    "kqueue")
  (define-c-lambda __kevent (int kevent* int kevent* int timespec*) int
    "kevent")

  (define-with-errno _kqueue __kqueue ())
  (define-with-errno _kevent __kevent (kqfd chgs nchgs evts nevts timeo))

  (define-c-lambda make_kevents (int) kevent*
    "___return ((struct kevent*)malloc (___arg1 * sizeof (struct kevent)));")

  (define-c-lambda kevent_ident (kevent* int) unsigned-int
    "___return (___arg1[___arg2].ident);")
  (define-c-lambda kevent_ident_set (kevent* int unsigned-int) void
    "___arg1[___arg2].ident = ___arg3; ___return;")

  (define-c-lambda kevent_filter (kevent* int) short
    "___return (___arg1[___arg2].filter);")
  (define-c-lambda kevent_filter_set (kevent* int short) void
    "___arg1[___arg2].filter = ___arg3; ___return;")

  (define-c-lambda kevent_flags (kevent* int) unsigned-short
    "___return (___arg1[___arg2].flags);")
  (define-c-lambda kevent_flags_set (kevent* int unsigned-short) void
    "___arg1[___arg2].flags = ___arg3; ___return;")

  (define-c-lambda kevent_fflags (kevent* int) unsigned-int
    "___return (___arg1[___arg2].fflags);")
  (define-c-lambda kevent_fflags_set (kevent* int unsigned-int) void
    "___arg1[___arg2].fflags = ___arg3; ___return;")

  (define-c-lambda kevent_data (kevent* int) int64
    "___return (___arg1[___arg2].data);")
  (define-c-lambda kevent_data_set (kevent* int int64) void
    "___arg1[___arg2].data = ___arg3; ___return;")

  (cond-expand
    (netbsd
     (define-c-lambda kevent_udata (kevent* int) int
       "___return (___arg1[___arg2].udata);")
     (define-c-lambda kevent_udata_set (kevent* int int) void
       "___arg1[___arg2].udata = ___arg3; ___return;"))
    (else
     (define-c-lambda kevent_udata (kevent* int) int
       "___return ((long)(___arg1[___arg2].udata));")
     (define-c-lambda kevent_udata_set (kevent* int int) void
       "___arg1[___arg2].udata = (void *)((long)___arg3); ___return;")))

  (define-c-lambda ev_set
    (kevent* int unsigned-int short unsigned-short unsigned-int int64 (pointer void)) void
    "EV_SET(&___arg1[___arg2], ___arg3, ___arg4, ___arg5, ___arg6, ___arg7, ___arg8); ___return;"))
