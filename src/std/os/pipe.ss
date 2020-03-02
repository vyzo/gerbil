;;; -*- Gerbil -*-
;;; (C) vyzo at hackzen.org
;;; OS pipes

(import :std/foreign
        :std/contract
        :std/os/error
        :std/os/fd
        :std/os/fcntl)
(export pipe)

(def/c (pipe (direction 'inout) (closeonexec #t))
  (@contract (memq direction '(in out inout none)))
  (let* ((ptr (check-ptr (make_pipe_ptr)))
         (_ (check-os-error (_pipe ptr) (pipe)))
         (ifd (pipe_ptr_ref ptr 0))
         (ofd (pipe_ptr_ref ptr 1))
         (set-nonblock
          (if closeonexec
            fd-set-nonblock/closeonexec
            fd-set-nonblock)))
    (case direction
      ((in)
       (let (iraw (fdopen ifd 'in 'pipe))
         (set-nonblock iraw)
         (values iraw ofd)))
      ((out)
       (let (oraw (fdopen ofd 'out 'pipe))
         (set-nonblock oraw)
         (values ifd oraw)))
      ((inout)
       (let ((iraw (fdopen ifd 'in 'pipe))
             (oraw (fdopen ofd 'out 'pipe)))
         (set-nonblock iraw)
         (set-nonblock oraw)
         (values iraw oraw)))
      ((none)
       (values ifd ofd)))))

(begin-ffi (_pipe make_pipe_ptr pipe_ptr_ref)
  (c-declare "#include <unistd.h>")

  (namespace ("std/os/pipe#" __pipe))

  (c-define-type pipe*
    (pointer int (pipe*) "ffi_free"))

  (define-c-lambda __pipe (pipe*) int
    "pipe")
  (define-with-errno _pipe __pipe (pipe-ptr))

  (define-c-lambda make_pipe_ptr () pipe*
    "___return ((int*)malloc (2 * sizeof (int)));")
  (define-c-lambda pipe_ptr_ref (pipe* int) int
    "___return (___arg1[___arg2]);"))
