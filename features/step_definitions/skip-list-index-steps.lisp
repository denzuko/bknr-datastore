;;;; features/step_definitions/skip-list-index-steps.lisp
;;;;
;;;; Steps for features/skip-list-index.feature, run as FiveAM tests
;;;; through sunny-side. Every step closes over one lexical WORLD.

(defpackage :bknr.indices.bdd
  (:use :cl :sunny-side :bknr.datastore :bknr.indices)
  (:import-from :fiveam #:is #:is-true #:is-false)
  (:export #:run-bdd))

(in-package :bknr.indices.bdd)

(defmacro define-ranked-thing ()
  "Define RANKED-THING. A scenario evaluates this again to redefine it."
  '(define-persistent-class ranked-thing ()
    ((rank :read :initarg :rank
           :index-type skip-list-index
           :index-reader ranked-thing-with-rank))
    (:documentation "Persistent class whose RANK slot has a skip-list index.")))

(define-ranked-thing)

(defclass rank-holder ()
  ((rank :initarg :rank))
  (:documentation "Plain object with a RANK slot, never added to the index.
INDEX-REMOVE reads only the key slot, so it stands in for an object the
index does not hold."))

(defstruct world
  "State one scenario builds up and later steps check."
  first-id signalled)

(defun scratch-directory ()
  "Return an unused directory under the system temporary directory."
  (ensure-directories-exist
   (uiop:ensure-directory-pathname
    (merge-pathnames (format nil "bknr-skip-list-bdd-~36R~36R" (get-universal-time) (random (expt 36 8)))
                     (uiop:temporary-directory)))))

(defun rank-index ()
  "Return the skip-list index on RANKED-THING's RANK slot."
  (bknr.indices::class-slot-index (find-class 'ranked-thing) 'rank))

(defun ranked-things ()
  "Return every RANKED-THING in the store."
  (class-instances 'ranked-thing))

(defun signalled-by (function)
  "Call FUNCTION and return the error it signals, or NIL."
  (handler-case (progn (funcall function) nil)
    (error (condition) condition)))

(defun run-in-threads (count function)
  "Run FUNCTION with each index below COUNT on its own thread, release the
threads together, and wait for all of them."
  (let* ((gate (bt:make-semaphore))
         (threads (loop for index below count
                        collect (let ((index index))
                                  (bt:make-thread (lambda ()
                                                    (bt:wait-on-semaphore gate)
                                                    (funcall function index)))))))
    (bt:signal-semaphore gate :count count)
    (mapc #'bt:join-thread threads)))

(let ((world (make-world)))

  (Given! "^an empty store with a class keyed by a skip-list index$" ()
    (close-store)
    (setf world (make-world))
    (make-instance 'mp-store :directory (scratch-directory)))

  (Given! "^a ranked thing with rank (\\d+)$" (rank)
    (setf (world-first-id world)
          (store-object-id (make-instance 'ranked-thing :rank (parse-integer rank)))))

  (When! "^the ranked thing with rank (\\d+) is removed from the index$" (rank)
    (index-remove (rank-index) (ranked-thing-with-rank (parse-integer rank))))

  (When! "^an unindexed ranked thing with rank (\\d+) is removed from the index$" (rank)
    (setf (world-signalled world)
          (signalled-by (lambda ()
                          (index-remove (rank-index)
                                        (make-instance 'rank-holder :rank (parse-integer rank)))))))

  (When! "^an unindexed ranked thing with no rank is removed from the index$" ()
    (setf (world-signalled world)
          (signalled-by (lambda () (index-remove (rank-index) (make-instance 'rank-holder))))))

  (When! "^a transaction creates a ranked thing with the duplicate rank (\\d+)$" (rank)
    (setf (world-signalled world)
          (signalled-by (lambda ()
                          (with-transaction (:duplicate)
                            (make-instance 'ranked-thing :rank (parse-integer rank)))))))

  (When! "^(\\d+) threads each create (\\d+) ranked things in transactions$" (threads count)
    (let ((count (parse-integer count)))
      (run-in-threads (parse-integer threads)
                      (lambda (thread)
                        (dotimes (index count)
                          (with-transaction (:create)
                            (make-instance 'ranked-thing :rank (+ (* 1000 thread) index))))))))

  (When! "^the store is reloaded$" ()
    (restore))

  (When! "^the ranked thing class is defined again$" ()
    (eval '(define-ranked-thing)))

  (Then! "^no ranked thing should be found under rank (\\d+)$" (rank)
    (is-false (ranked-thing-with-rank (parse-integer rank))))

  (Then! "^the first ranked thing should be found under rank (\\d+)$" (rank)
    (let ((found (ranked-thing-with-rank (parse-integer rank))))
      (is-true found)
      (is (eql (world-first-id world) (and found (store-object-id found))))))

  (Then! "^the removal should have signalled nothing$" ()
    (is-false (world-signalled world)))

  (Then! "^the duplicate rank should have been refused with an index error$" ()
    (is (typep (world-signalled world) 'index-existing-error)))

  (Then! "^(\\d+) ranked things? should exist$" (count)
    (is (= (parse-integer count) (length (ranked-things)))))

  (Then! "^every ranked thing should be found under its rank$" ()
    (is (every (lambda (thing) (eq thing (ranked-thing-with-rank (slot-value thing 'rank))))
               (ranked-things)))))

(define-feature-tests
    #.(asdf:system-relative-pathname :bknr.indices "../features/skip-list-index.feature")
  :suite skip-list-index-suite)

(defun run-bdd ()
  "Run the skip-list index feature, close the store, and return T when
every scenario passed."
  (unwind-protect (fiveam:run! 'skip-list-index-suite)
    (close-store)))
