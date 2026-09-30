(in-package :bknr.datastore.tests)

;;; Restoring a snapshot written under an older class definition. The
;;; snapshot writer records every persistent slot of the class at the time
;;; (object.lisp); CLHS 4.3.6 initialises slots added to a class from their
;;; initforms and leaves the values of existing slots alone. These tests
;;; open their own store, so they are plain UNIT-TEST instances.

(defun define-migrating (&rest slots)
  "Define MIGRATING-RECORD with SLOTS, each a slot specifier."
  (eval `(define-persistent-class migrating-record () ,slots)))

(defun call-with-reloaded-snapshot (count first-slots initargs second-slots function)
  "Define MIGRATING-RECORD with FIRST-SLOTS, create COUNT records with
INITARGS, snapshot, close, redefine with SECOND-SLOTS, reopen the store and
call FUNCTION with the records. Close the store afterwards."
  (let ((directory (make-test-store-directory)))
    (apply #'define-migrating first-slots)
    (make-instance 'mp-store :directory directory)
    (dotimes (index count)
      (apply #'make-instance 'migrating-record initargs))
    (snapshot)
    (close-store)
    (apply #'define-migrating second-slots)
    (make-instance 'mp-store :directory directory)
    (unwind-protect (funcall function (class-instances 'migrating-record))
      (close-store))))

(defun register-migration-test (name body)
  "Register BODY as datastore test NAME."
  (setf (gethash name *tests*)
        (make-instance 'unit-test::unit-test :unit :datastore :name name :body body)))

(register-migration-test
 'snapshot-reload-initialises-an-added-slot
 (lambda ()
   (call-with-reloaded-snapshot
    2 '((a :update :initarg :a)) '(:a 1)
    '((a :update :initarg :a) (b :update :initform 42))
    (lambda (records)
      (test-equal 2 (length records))
      (test-assert (every (lambda (record) (eql 42 (slot-value record 'b))) records))
      (test-assert (every (lambda (record) (eql 1 (slot-value record 'a))) records))))))

(register-migration-test
 'snapshot-reload-keeps-a-stored-value-when-the-initform-changes
 (lambda ()
   (call-with-reloaded-snapshot
    1 '((a :update :initarg :a :initform 1)) '()
    '((a :update :initarg :a :initform 2))
    (lambda (records)
      (test-equal 1 (slot-value (first records) 'a))))))

(register-migration-test
 'snapshot-reload-evaluates-the-initform-once-per-record
 (lambda ()
   (call-with-reloaded-snapshot
    2 '((a :update :initarg :a)) '(:a 1)
    '((a :update :initarg :a) (b :update :initform (list 0)))
    (lambda (records)
      (test-equal '(0) (slot-value (first records) 'b))
      (test-assert (not (eq (slot-value (first records) 'b)
                            (slot-value (second records) 'b))))))))

;;; RESTORE-SUBSYSTEM already calls INITIALIZE-TRANSIENT-SLOTS on every
;;; object, which sets transient slots from their initforms. This guards
;;; that existing behaviour.
(register-migration-test
 'snapshot-reload-initialises-an-added-transient-slot
 (lambda ()
   (call-with-reloaded-snapshot
    1 '((a :update :initarg :a)) '(:a 1)
    '((a :update :initarg :a) (b :update :transient t :initform 42))
    (lambda (records)
      (test-equal 42 (slot-value (first records) 'b))))))
