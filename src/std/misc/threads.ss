;;; -*- Gerbil -*-
;;; (C) vyzo at hackzen.org
;;; miscellaneous thread utilities

(import :gerbil/gambit/threads
        :std/sugar
        :std/contract)
(export primordial-thread-group
        thread-group->thread-list* all-threads
        thread-dead?
        thread-group-kill!
        thread-raise! thread-abort! thread-abort?
        thread-async!
        on-all-processors)

(def (primordial-thread-group)
  (thread-thread-group ##primordial-thread))

(def (thread-group->thread-list* tg)
  (let lp ((rest (thread-group->thread-group-list tg))
           (r (thread-group->thread-list tg)))
    (match rest
      ([tg . rest]
       (lp (foldl cons rest (thread-group->thread-group-list tg))
           (foldl cons r (thread-group->thread-list tg))))
      (else r))))

(def (all-threads)
  (thread-group->thread-list* (primordial-thread-group)))

(extern thread-dead?)
(begin-foreign
  (namespace ("std/misc/threads#" thread-dead?))
  (define (thread-dead? thread)
    (not (macro-thread-end-condvar thread))))


;; thread-group-kill! kills all threads and children groups in the thread group
;; In addition, it detaches the thread group from its parent, making it unreachable
;; from the primordial thread-group structure and eligible for garbage collection.
;; A thread group that has been killed, should not be used again to spawn threads
;; in it.
;; Note: this procedure is a combination of the not yet implemented primitive
;;       thread-group-terminate! and a thread-group-detach! operation that
;;       makes the thread-group free-standing.
(extern thread-group-kill!)

(begin-foreign
  (namespace ("std/misc/threads#" thread-group-kill!
              tgroup-kill! tgroup-kill-threads! tgroup-detach!))

  (define (thread-group-kill! tg)
    (declare (not interrupts-enabled))

    (define (check-tgroup! tg)
      (let ((mytg (macro-thread-tgroup (##current-thread))))
        (let lp ((mytg mytg))
          (cond
           ((##eq? mytg tg)
            (error "Cannot kill thread group; thread-group includes current thread" tg))
           ((##not mytg))
           (else
            (lp (macro-tgroup-parent mytg)))))))

    (if (macro-tgroup? tg)
      (begin
        (check-tgroup! tg)
        (cond-expand
          (enable-smp
           ;; there may be more threads spawned in another processor from within the
           ;; tgroup while we are killing it; needs to iterate on SMP.
           (let lp ()
             (if (##fx> (tgroup-kill! tg) 0)
               (lp))))
          (else
           (tgroup-kill! tg)))
        (tgroup-detach! tg)
        (void))
      (error "Bad argument; expected thread-group" tg)))


  (define (tgroup-kill! tg)
    (declare (not interrupts-enabled))
    (let ((tgroups (##tgroup->tgroup-vector tg)))
      (let lp ((i 0) (r 0))
        (if (##fx< i (##vector-length tgroups))
          (let ((count (tgroup-kill! (##vector-ref tgroups i))))
            (lp (##fx+ i 1) (##fx+ r count)))
          (let ((count (tgroup-kill-threads! tg)))
            (##fx+ r count))))))

  (define (tgroup-kill-threads! tg)
    (declare (not interrupts-enabled))
    (let ((threads (##tgroup->thread-vector tg)))
      (let lp ((i 0))
        (if (##fx< i (##vector-length threads))
          (begin
            (##thread-terminate! (##vector-ref threads i))
            (lp (##fx+ i 1)))
          i))))

  (define (tgroup-detach! tg)
    (declare (not interrupts-enabled))
    (if (macro-tgroup-parent tg)
        (begin
          ;; this is broken:
          ;; (macro-tgroup-tgroups-deq-remove! tg)
          ;; so do it by hand instead
          (let ((next (macro-tgroup-tgroups-deq-next tg))
                (prev (macro-tgroup-tgroups-deq-prev tg)))
            (cond-expand
              (enable-smp
               (##vector-set! prev 2 next)
               (##vector-set! next 3 prev))
              (else
               (##vector-set! prev 1 next)
               (##vector-set! next 2 prev)))
            (macro-tgroup-tgroups-deq-next-set! tg tg)
            (macro-tgroup-tgroups-deq-prev-set! tg tg))
          ;; and mark it as unreachable
          (cond-expand
            (enable-smp
             ;; no parent field mutator defined
             (##vector-set! tg 8 #f))
            (else
             (macro-tgroup-parent-set! tg #f)))))))

;; asynchronous thread aborts
(defstruct thread-abort ()
  final: #t)

(defmethod {display-exception thread-abort}
  (lambda (self port)
    (display "thread aborted" port)
    (newline port)))

(def +thread-abort+
  (make-thread-abort))

(def (thread-abort! thread)
  (thread-raise! thread +thread-abort+))

(def/c (thread-raise! thread obj)
  (@contract (thread? thread))
  (if (eq? thread (current-thread))
    (raise obj)
    (thread-intr! thread (cut raise obj))))

(def/c (thread-async! thread thunk)
  (@contract (thread? thread) (procedure? thunk))
   (if (eq? thread (current-thread))
    (thunk)
    (thread-intr! thread thunk)))

(extern thread-intr!)

(begin-foreign
  (namespace ("std/misc/threads#" thread-intr!))

  (define (thread-intr! thread thunk)
    (declare (not interrupts-enabled))
    (if (and (macro-initialized-thread? thread)
             (##not (macro-terminated-thread-given-initialized? thread))
             (cond-expand
               (enable-smp
                (macro-started-thread? thread))
               (else
                (macro-started-thread-given-initialized? thread))))
      (begin
        (cond-expand
          (enable-smp
           (##thread-intr! thread #t thunk))
          (else
           (##thread-int! thread thunk)))
        (##void))
      #f)))

;; execute a thunk on all available processors
;; returns a list of threads for each processor; the threads are pinned on smp
(def (on-all-processors thunk)
  (cond-expand
    (gerbil-smp
     (let* ((count (##current-vm-processor-count))
            (processors (map ##processor (iota count)))
            (threads (map (lambda (proc)
                            (let (thr (make-thread thunk))
                              (##thread-pin! thr proc)
                              thr))
                          processors)))
       (for-each thread-start! threads)
       threads))
    (else
     [(spawn-thread thunk)])))
