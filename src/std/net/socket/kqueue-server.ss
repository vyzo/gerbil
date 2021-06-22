;;; -*- Gerbil -*-
;;; (C) vyzo at hackzen.org
;;; synchronous sockets  -- kqueue server implementation

(require bsd)

(import :gerbil/gambit/threads
        :gerbil/gambit/ports
        :gerbil/gambit/misc
        :std/net/socket/base
        :std/net/socket/basic-server
        :std/os/fd
        :std/os/kqueue
        :std/iter)

(export kqueue-socket-server)

(declare
  (fixnum))

(def (kqueue-socket-server)
  (def fdtab (make-hash-table-eq))
  (def kq (kqueue))
  (def maxevts 8192)
  (def evts (make-kevents maxevts))
  (def nchanges 0)

  (def (do-kevent)
    (let (count (kevent kq evts nchanges evts maxevts))
      (when (##fxpositive? count)
        (let lp ((k 0))
          (when (##fx< k count)
            (with ((!socket-state _ io-in io-out)
                   (hash-ref fdtab (kevent-ident evts k)))
              (let ((filter (kevent-filter evts k)))
                (cond
                  ((and io-in (##fx= filter EVFILT_READ))
                   (io-state-signal-ready! io-in 'ready))
                  ((and io-out (##fx= filter EVFILT_WRITE))
                   (io-state-signal-ready! io-out 'ready)))))
            (lp (fx1+ k)))))))

  (def (event-set! ident filter flags filter-flags data)
    (kevent-set! evts nchanges
                 ident: ident
                 filter: filter
                 flags: flags
                 filter-flags: filter-flags
                 data: data)
    (set! nchanges (fx1+ nchanges)))

  (def (add-socket sock)
    (let* ((self (current-thread))
           (fd (fd-e sock))
           (io-in
            (and (fd-io-in sock)
                 (make-!io-state)))
           (wait-in
            (and io-in
                 (lambda (ssock timeo)
                   (io-state-wait-io! io-in timeo 'input))))
           (io-out
            (and (fd-io-out sock)
                 (make-!io-state)))
           (wait-out
            (and io-out
                 (lambda (ssock timeo)
                   (io-state-wait-io! io-out timeo 'output))))
           (close
            (lambda (ssock dir shutdown)
              (!!socket-server.close self ssock dir shutdown)))
           (ssock
            (make-!socket sock wait-in wait-out close))
           (state
            (make-!socket-state sock io-in io-out)))
      (when io-in
        (event-set! (fd-e sock) EVFILT_READ (##fxior EV_ADD EV_CLEAR)
                    NOTE_LOWAT 1))
      (when io-out
        (event-set! (fd-e sock) EVFILT_WRITE (##fxior EV_ADD EV_CLEAR)
                    NOTE_LOWAT 1))
      ; register the events before the next call to ##wait-for-io!
      (kevent kq evts nchanges #f 0)
      (set! nchanges 0)
      (make-will ssock (cut close <> 'inout #f))
      (hash-put! fdtab fd state)
      ssock))

  (def (close-socket ssock dir shutdown)
    (def (close-io-in! io-in sock)
      (io-state-close-in! io-in sock shutdown))
    (def (close-io-out! io-out sock)
      (io-state-close-out! io-out sock shutdown))

    (with ((!socket sock wait-in wait-out) ssock)
      (when (or wait-in wait-out)
        (let (state (hash-get fdtab (fd-e sock)))
          (match state
            ((!socket-state _ io-in io-out)
             (case dir
               ((in)
                (set! (!socket-wait-in ssock) #f)
                (set! (!socket-state-io-in state) #f)
                (close-io-in! io-in sock)
                (unless io-out
                  (hash-remove! fdtab (fd-e sock))
                  (close-port sock)))
               ((out)
                (set! (!socket-wait-out ssock) #f)
                (set! (!socket-state-io-out state) #f)
                (close-io-out! io-out sock)
                (unless io-in
                  (hash-remove! fdtab (fd-e sock))
                  (close-port sock)))
               ((inout)
                (when io-in
                  (set! (!socket-wait-in ssock) #f)
                  (set! (!socket-state-io-in state) #f)
                  (close-io-in! io-in sock))
                (when io-out
                  (set! (!socket-wait-out ssock) #f)
                  (set! (!socket-state-io-out state) #f)
                  (close-io-out! io-out sock))
                (hash-remove! fdtab (fd-e sock))
                (close-port sock))
               (else
                (error "Bad direction" dir))))
            (else (void)))))))

  (def (shutdown!)
    (close-port kq)
    (for (state (in-hash-values fdtab))
      (with ((!socket-state sock io-in io-out) state)
        (when io-in
          (io-state-close-in! io-in sock #f))
        (when io-out
          (io-state-close-out! io-out sock #f))
        (close-port sock)))
    ;; release refs to raw devices
    (set! fdtab #f)
    (set! kq #f))

  (server-loop (fd-io-in kq) do-kevent add-socket close-socket shutdown!))
