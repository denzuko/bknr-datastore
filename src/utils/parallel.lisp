(in-package :bknr.utils)

;;;; A small, reusable registry of dedicated lparallel kernels, one
;;;; per caller-chosen NAME, each lazily created and cached under a
;;;; lock. Extracted from a real pattern in tdrhq/bknr-datastore's
;;;; own fork (its dedicated snapshot kernel) and a real, found bug
;;;; already fixed once in denzuko/bknr.hashkv (ENSURE-KERNEL's own
;;;; unguarded check-then-set, which could leak a kernel under
;;;; concurrent first-call access): rather than have every consumer
;;;; reimplement this same lock-guarded lazy-init boilerplate, this
;;;; is that pattern, written once.
;;;;
;;;; Using lparallel's own shared/global *KERNEL* for library-
;;;; internal parallel work risks deadlock if that same kernel is
;;;; also used elsewhere to write to bknr.datastore, or more
;;;; generally if a worker thread from a shared pool ends up blocked
;;;; waiting on work submitted by another worker from the same pool.
;;;; A dedicated kernel per concern avoids that.

(defvar *dedicated-lparallel-kernels* (make-hash-table :test 'eq)
  "Maps a caller-chosen NAME to its own lparallel kernel, created on
first request by ENSURE-DEDICATED-LPARALLEL-KERNEL.")

(defvar *dedicated-lparallel-kernels-lock* (bt:make-lock)
  "Guards *DEDICATED-LPARALLEL-KERNELS*'s lazy initialization. The
lock only protects the hash-table lookup and creation, not any
subsequent parallel work done on the kernel it returns.")

(defun ensure-dedicated-lparallel-kernel (name &key (workers 4))
  "Returns the dedicated lparallel kernel for NAME (a symbol
identifying the caller, not shared with any other consumer's name),
creating one with WORKERS worker threads on first request and
caching it under NAME for every later request. Different NAMEs get
different, independent kernels; the same NAME always gets the same
kernel."
  (bt:with-lock-held (*dedicated-lparallel-kernels-lock*)
    (or (gethash name *dedicated-lparallel-kernels*)
        (setf (gethash name *dedicated-lparallel-kernels*)
              (lparallel:make-kernel workers :name (string name))))))
