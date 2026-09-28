;;;; features/step_definitions/transaction-rollback-steps.lisp
;;;;
;;;; Steps for features/transaction-rollback.feature, run as FiveAM tests
;;;; through sunny-side. Every step closes over one lexical WORLD; the
;;;; Background step replaces it at the start of each scenario.

(defpackage :bknr.datastore.bdd
  (:use :cl :sunny-side :bknr.datastore :bknr.indices)
  (:import-from :fiveam #:is #:is-true #:is-false)
  (:export #:run-bdd))

(in-package :bknr.datastore.bdd)

(define-persistent-class thing ()
  ((key :read :initarg :key
        :index-type string-unique-index
        :index-reader thing-with-key)
   (note :update :initarg :note :initform nil))
  (:documentation "Persistent class with a unique key, for the rollback scenarios."))

(defstruct world
  "State one scenario builds up and later steps check."
  signalled live-ids live-counter)

(defun scratch-directory ()
  "Return an unused directory under the system temporary directory."
  (ensure-directories-exist
   (uiop:ensure-directory-pathname
    (merge-pathnames (format nil "bknr-bdd-~36R~36R" (get-universal-time) (random (expt 36 8)))
                     (uiop:temporary-directory)))))

(defun id-counter ()
  "Return the store's next object id."
  (bknr.datastore::next-object-id (bknr.datastore::store-object-subsystem)))

(defun things ()
  "Return every THING in the store."
  (class-instances 'thing))

(defun sorted-ids ()
  "Return the ids of every THING, ascending."
  (sort (mapcar #'store-object-id (things)) #'<))

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

(defun found-by-key-and-id-p (thing)
  "True when THING is what both its key and its id look up."
  (and (eq thing (thing-with-key (slot-value thing 'key)))
       (eq thing (store-object-with-id (store-object-id thing)))))

(defun create-or-fail (index round)
  "Create a thing outside any transaction on even INDEX; on odd INDEX,
create one inside a transaction that then signals. Errors surface as
missing things."
  (ignore-errors
    (cond ((evenp index)
           (make-instance 'thing :key (format nil "made-~D-~D" index round)))
          (t (with-transaction (:fails)
               (make-instance 'thing :key (format nil "failed-~D-~D" index round))
               (error "rollback on purpose"))))))

(let ((world (make-world)))

  (Given! "^an empty store$" ()
    (close-store)
    (setf world (make-world))
    (make-instance 'mp-store :directory (scratch-directory)))

  (Given! "^a thing with key \"([^\"]*)\" and note \"([^\"]*)\"$" (key note)
    (make-instance 'thing :key key :note note))

  (When! "^a transaction creates a thing with key \"([^\"]*)\"$" (key)
    (with-transaction (:creates)
      (make-instance 'thing :key key)))

  (When! "^a transaction creates a thing with key \"([^\"]*)\" and then signals an error$" (key)
    (setf (world-signalled world)
          (signalled-by (lambda ()
                          (with-transaction (:fails)
                            (make-instance 'thing :key key)
                            (error "rollback on purpose"))))))

  (When! "^a transaction sets the note of \"([^\"]*)\" to \"([^\"]*)\" and then signals an error$" (key note)
    (setf (world-signalled world)
          (signalled-by (lambda ()
                          (with-transaction (:fails)
                            (setf (slot-value (thing-with-key key) 'note) note)
                            (error "rollback on purpose"))))))

  (When! "^a transaction creates a thing with the duplicate key \"([^\"]*)\"$" (key)
    (setf (world-signalled world)
          (signalled-by (lambda ()
                          (with-transaction (:duplicate)
                            (make-instance 'thing :key key))))))

  (When! "^a transaction that creates nothing signals an error$" ()
    (setf (world-signalled world)
          (signalled-by (lambda ()
                          (with-transaction (:fails)
                            (error "rollback on purpose"))))))

  (When! "^a thing with key \"([^\"]*)\" is created outside a transaction$" (key)
    (make-instance 'thing :key key))

  (When! "^(\\d+) threads create things while (\\d+) threads run failing transactions, (\\d+) rounds each$"
      (creators failers rounds)
    (let ((rounds (parse-integer rounds)))
      (run-in-threads (+ (parse-integer creators) (parse-integer failers))
                      (lambda (index)
                        (dotimes (round rounds)
                          (create-or-fail index round))))))

  (When! "^the store is restored$" ()
    (setf (world-live-ids world) (sorted-ids)
          (world-live-counter world) (id-counter))
    (restore))

  (When! "^the store is snapshotted and restored$" ()
    (setf (world-live-ids world) (sorted-ids)
          (world-live-counter world) (id-counter))
    (snapshot)
    (restore))

  (Then! "^(\\d+) things? should exist$" (count)
    (is (= (parse-integer count) (length (things)))))

  (Then! "^no thing should be found under the key \"([^\"]*)\"$" (key)
    (is-false (thing-with-key key)))

  (Then! "^the thing with key \"([^\"]*)\" should be found by its key and by its id$" (key)
    (let ((thing (thing-with-key key)))
      (is-true thing)
      (is-true (and thing (found-by-key-and-id-p thing)))))

  (Then! "^the note of \"([^\"]*)\" should be \"([^\"]*)\"$" (key note)
    (is (equal note (slot-value (thing-with-key key) 'note))))

  (Then! "^the thing with key \"([^\"]*)\" should have note \"([^\"]*)\"$" (key note)
    (let ((thing (thing-with-key key)))
      (is-true thing)
      (is (equal note (and thing (slot-value thing 'note))))))

  (Then! "^the transaction should have signalled an index error$" ()
    (is (typep (world-signalled world) 'index-existing-error)))

  (Then! "^the id counter should be (\\d+)$" (count)
    (is (= (parse-integer count) (id-counter))))

  (Then! "^the thing with key \"([^\"]*)\" should have id (\\d+)$" (key id)
    (let ((thing (thing-with-key key)))
      (is-true thing)
      (is (eql (parse-integer id) (and thing (store-object-id thing))))))

  (Then! "^every thing should have a unique id$" ()
    (let ((ids (sorted-ids)))
      (is (= (length ids) (length (remove-duplicates ids))))))

  (Then! "^every thing should be found by its key and by its id$" ()
    (is (every #'found-by-key-and-id-p (things))))

  (Then! "^the restored ids and id counter should match the live store$" ()
    (is (equal (world-live-ids world) (sorted-ids)))
    (is (= (world-live-counter world) (id-counter)))))

(define-feature-tests
    #.(asdf:system-relative-pathname :bknr.datastore "../features/transaction-rollback.feature")
  :suite transaction-rollback-suite)

(defun run-bdd ()
  "Run the rollback feature, close the store the last scenario opened,
and return T when every scenario passed."
  (unwind-protect (fiveam:run! 'transaction-rollback-suite)
    (close-store)))
