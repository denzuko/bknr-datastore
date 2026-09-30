;;;; features/step_definitions/snapshot-class-changes-steps.lisp
;;;;
;;;; Steps for features/snapshot-class-changes.feature. Each scenario
;;;; defines MIGRATING-THING in its first form, snapshots a store, closes
;;;; it, redefines the class, and reopens the store from the snapshot.

(defpackage :bknr.datastore.snapshot-bdd
  (:use :cl :sunny-side :bknr.datastore)
  (:import-from :fiveam #:is #:is-true)
  (:export #:run-bdd))

(in-package :bknr.datastore.snapshot-bdd)

(defun class-form (&rest level-slot)
  "Return the definition of MIGRATING-THING: a NAME slot, plus a LEVEL slot
defined by LEVEL-SLOT when it is given."
  `(define-persistent-class migrating-thing ()
     ((name :update :initarg :name)
      ,@(when level-slot (list (cons 'level level-slot))))))

(defun scratch-directory ()
  "Return an unused directory under the system temporary directory."
  (ensure-directories-exist
   (uiop:ensure-directory-pathname
    (merge-pathnames (format nil "bknr-snapshot-bdd-~36R~36R" (get-universal-time) (random (expt 36 8)))
                     (uiop:temporary-directory)))))

(defun migrating-things ()
  "Return every MIGRATING-THING in the store."
  (class-instances 'migrating-thing))

(defun open-store-at (directory)
  "Open the store in DIRECTORY, restoring it from its snapshot and log."
  (make-instance 'mp-store :directory directory))

(defun every-thing-p (predicate)
  "True when there is at least one MIGRATING-THING and each satisfies PREDICATE."
  (let ((things (migrating-things)))
    (and things (every predicate things))))

(let ((directory nil))
  (flet ((create-and-snapshot (count &rest initargs)
           (eval (class-form))
           (dotimes (index count)
             (apply #'make-instance 'migrating-thing initargs))
           (snapshot)
           (close-store)))

    (Given! "^an empty store for migrating things$" ()
      (close-store)
      (setf directory (scratch-directory))
      (open-store-at directory))

    (Given! "^(\\d+) migrating things? with name \"([^\"]*)\", snapshotted under the first class$" (count name)
      (create-and-snapshot (parse-integer count) :name name))

    (Given! "^(\\d+) migrating things? with no name, snapshotted under the first class$" (count)
      (create-and-snapshot (parse-integer count)))

    (When! "^the class gains a slot \"level\" with initform (\\d+)$" (value)
      (eval (class-form :update :initform (parse-integer value))))

    (When! "^the class gains a slot \"level\" with no initform$" ()
      (eval (class-form :update)))

    (When! "^the store is reopened$" ()
      (open-store-at directory))

    (When! "^the store is snapshotted and reopened again$" ()
      (snapshot)
      (close-store)
      (open-store-at directory))

    (Then! "^every migrating thing should have level (\\d+)$" (value)
      (is-true (every-thing-p (lambda (thing)
                                (and (slot-boundp thing 'level)
                                     (eql (parse-integer value) (slot-value thing 'level)))))))

    (Then! "^every migrating thing should keep its name \"([^\"]*)\"$" (name)
      (is-true (every-thing-p (lambda (thing)
                                (and (slot-boundp thing 'name)
                                     (equal name (slot-value thing 'name)))))))

    (Then! "^every migrating thing should have no name$" ()
      (is-true (every-thing-p (lambda (thing) (not (slot-boundp thing 'name))))))

    (Then! "^every migrating thing should have no level$" ()
      (is-true (every-thing-p (lambda (thing) (not (slot-boundp thing 'level))))))))

(define-feature-tests
    #.(asdf:system-relative-pathname :bknr.datastore "../features/snapshot-class-changes.feature")
  :suite snapshot-class-changes-suite)

(defun run-bdd ()
  "Run the snapshot class-change feature, close the store, and return T
when every scenario passed."
  (unwind-protect (fiveam:run! 'snapshot-class-changes-suite)
    (close-store)))
