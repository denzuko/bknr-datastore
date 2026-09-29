;;;; features/step_definitions/restore-concurrent-writes-steps.lisp
;;;;
;;;; Steps for features/restore-concurrent-writes.feature. A gate subsystem
;;;; holds a restore open after the object subsystem has loaded the snapshot,
;;;; so other threads can act while the store is in the :RESTORE state.

(defpackage :bknr.datastore.restore-bdd
  (:use :cl :sunny-side :bknr.datastore :bknr.indices)
  (:import-from :fiveam #:is #:is-true #:is-false)
  (:export #:run-bdd))

(in-package :bknr.datastore.restore-bdd)

(define-persistent-class restore-thing ()
  ((key :read :initarg :key
        :index-type string-unique-index
        :index-reader restore-thing-with-key)
   (note :update :initarg :note :initform nil))
  (:documentation "Persistent class with a unique key, for the restore scenarios."))

(defclass gate-subsystem ()
  ((armed :initform nil :accessor gate-armed)
   (entered :initform (bt:make-semaphore) :reader gate-entered)
   (release :initform (bt:make-semaphore) :reader gate-release))
  (:documentation "Subsystem that, when armed, stops the restore inside
RESTORE-SUBSYSTEM until released. Listed after the object subsystem, so
the snapshot is loaded when it stops."))

(defmethod restore-subsystem (store (subsystem gate-subsystem) &key until)
  (declare (ignore store until))
  (when (gate-armed subsystem)
    (bt:signal-semaphore (gate-entered subsystem))
    (bt:wait-on-semaphore (gate-release subsystem))))

(defmethod snapshot-subsystem (store (subsystem gate-subsystem))
  (declare (ignore store))
  nil)

(defstruct world
  "State one scenario builds up and later steps check."
  gate restorer counter-at-pause signalled creators creator-errors
  live-ids live-counter)

(defun scratch-directory ()
  "Return an unused directory under the system temporary directory."
  (ensure-directories-exist
   (uiop:ensure-directory-pathname
    (merge-pathnames (format nil "bknr-restore-bdd-~36R~36R" (get-universal-time) (random (expt 36 8)))
                     (uiop:temporary-directory)))))

(defun id-counter ()
  "Return the store's next object id."
  (bknr.datastore::next-object-id (store-object-subsystem)))

(defun things ()
  "Return every RESTORE-THING in the store."
  (class-instances 'restore-thing))

(defun sorted-ids ()
  "Return the ids of every RESTORE-THING, ascending."
  (sort (mapcar #'store-object-id (things)) #'<))

(defun found-by-key-and-id-p (thing)
  "True when THING is what both its key and its id look up."
  (and (eq thing (restore-thing-with-key (slot-value thing 'key)))
       (eq thing (store-object-with-id (store-object-id thing)))))

(defun signalled-by (function)
  "Call FUNCTION and return the error it signals, or NIL."
  (handler-case (progn (funcall function) nil)
    (error (condition) condition)))

(defun wait-for-threads (threads seconds)
  "Wait up to SECONDS for every thread in THREADS to finish. Return T when
all finished, NIL when the time ran out."
  (loop repeat (* 20 seconds)
        until (notany #'bt:thread-alive-p threads)
        do (sleep 0.05))
  (notany #'bt:thread-alive-p threads))

(defun release-restore (world)
  "Release a paused restore in WORLD and wait for its thread."
  (let ((gate (world-gate world)))
    (when (and gate (gate-armed gate))
      (setf (gate-armed gate) nil)
      (bt:signal-semaphore (gate-release gate))
      (wait-for-threads (list (world-restorer world)) 30))))

(let ((world (make-world)))
  (labels ((start-creator (keys)
             (let ((lock (bt:make-lock)))
               (push (bt:make-thread
                      (lambda ()
                        (dolist (key keys)
                          (let ((condition (signalled-by (lambda () (make-instance 'restore-thing :key key)))))
                            (when condition
                              (bt:with-lock-held (lock)
                                (push condition (world-creator-errors world))))))))
                     (world-creators world)))))

    (Given! "^a store holding a record with key \"([^\"]*)\" and note \"([^\"]*)\", snapshotted$" (key note)
      (release-restore world)
      (close-store)
      (setf world (make-world :gate (make-instance 'gate-subsystem)))
      (make-instance 'mp-store
                     :directory (scratch-directory)
                     :subsystems (list (make-instance 'store-object-subsystem) (world-gate world)))
      (make-instance 'restore-thing :key key :note note)
      (snapshot))

    (Given! "^a restore paused after the snapshot is loaded, in its own thread$" ()
      (let ((gate (world-gate world))
            (store *store*))
        (setf (gate-armed gate) t
              (world-restorer world) (bt:make-thread (lambda ()
                                                       (let ((*store* store))
                                                         (restore)))))
        (bt:wait-on-semaphore (gate-entered gate))
        (setf (world-counter-at-pause world) (id-counter))))

    (When! "^this thread sets the note of \"([^\"]*)\" to \"([^\"]*)\"$" (key note)
      (setf (world-signalled world)
            (signalled-by (lambda () (setf (slot-value (restore-thing-with-key key) 'note) note)))))

    (When! "^the restore is released$" ()
      (release-restore world))

    (When! "^another thread creates a record with key \"([^\"]*)\"$" (key)
      (start-creator (list key)))

    (When! "^(\\d+) other threads each create (\\d+) records$" (threads count)
      (dotimes (thread (parse-integer threads))
        (start-creator (loop for index below (parse-integer count)
                             collect (format nil "made-~D-~D" thread index)))))

    (When! "^the store is restored again$" ()
      (setf (world-live-ids world) (sorted-ids)
            (world-live-counter world) (id-counter))
      (restore))

    (Then! "^the write should have signalled a modified-outside-of-transaction error$" ()
      (is (typep (world-signalled world) 'bknr.datastore::persistent-slot-modified-outside-of-transaction)))

    (Then! "^the note of record \"([^\"]*)\" should be \"([^\"]*)\"$" (key note)
      (is (equal note (slot-value (restore-thing-with-key key) 'note))))

    (Then! "^that creation should still be waiting after (\\d+) milliseconds$" (milliseconds)
      (sleep (/ (parse-integer milliseconds) 1000))
      (is (some #'bt:thread-alive-p (world-creators world))))

    (Then! "^the id counter should be unchanged while the restore is paused$" ()
      (is (= (world-counter-at-pause world) (id-counter))))

    (Then! "^the creations? should finish$" ()
      (is-true (wait-for-threads (world-creators world) 30))
      (is-false (world-creator-errors world)))

    (Then! "^the record with key \"([^\"]*)\" should be found by its key and by its id$" (key)
      (let ((thing (restore-thing-with-key key)))
        (is-true thing)
        (is-true (and thing (found-by-key-and-id-p thing)))))

    (Then! "^(\\d+) records should exist$" (count)
      (is (= (parse-integer count) (length (things)))))

    (Then! "^every record should have a unique id$" ()
      (let ((ids (sorted-ids)))
        (is (= (length ids) (length (remove-duplicates ids))))))

    (Then! "^the restored record ids and id counter should match the live store$" ()
      (is (equal (world-live-ids world) (sorted-ids)))
      (is (= (world-live-counter world) (id-counter))))

    (defun run-bdd ()
      "Run the restore feature, release any restore a failed scenario left
paused, close the store, and return T when every scenario passed."
      (unwind-protect (fiveam:run! 'restore-concurrent-writes-suite)
        (release-restore world)
        (close-store)))))

(define-feature-tests
    #.(asdf:system-relative-pathname :bknr.datastore "../features/restore-concurrent-writes.feature")
  :suite restore-concurrent-writes-suite)
