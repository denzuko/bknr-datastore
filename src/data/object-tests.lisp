(in-package :bknr.datastore.tests)

(defun delete-directory (pathname)
  (when (probe-file pathname)
    #+cmu
    (loop for file in (directory pathname)
       when (pathname-name file)
       do (delete-file file)
       unless (pathname-name file)
       do (delete-directory file))
    #+allegro
    (excl:delete-directory-and-files pathname)
    #+cmu
    (unix:unix-rmdir (namestring pathname))
    #+sbcl
    (loop for file in (directory
                       (merge-pathnames
                        (make-pathname
                         :name    :wild
                         :type    :wild
                         :version :wild)
                        pathname))
       when (pathname-name file) do (delete-file file)
       unless (pathname-name file) do (delete-directory file))
    #+sbcl
    (sb-posix:rmdir (namestring pathname))
    #+openmcl
    (ccl::recursive-delete-directory pathname)))

(defvar *test-datastore* nil)

(define-test-class datastore-test-class)

(defun make-test-store-directory ()
  ;; bknr.utils:make-temporary-pathname does not really return a new
  ;; directory pathname that is guaranteed to be distinct.  Chances
  ;; that it returns the name of an existing directory are so slim
  ;; that we accept the risk.
  (ensure-directories-exist (format nil "~A/" (bknr.utils:make-temporary-pathname :defaults "/tmp/" :name "store-test"))))

(defmethod run-test :around ((test datastore-test-class) &optional (output *debug-io*))
  (let ((directory (make-test-store-directory))
        error)
    (make-instance 'mp-store :directory directory)
    (handler-bind ((error (lambda (e)
                            (declare (ignore e))
                            (setf error t))))
      (call-next-method))
    (close-store)
    (if error
        (format output ";; store directory ~A not deleted~%" directory)
        (delete-directory directory))))

(defvar *tests* (make-hash-table))

(defun do-run-test (thunk)
  "Run the test in THUNK, then verify that the store contains the
`same' objects after a restore and after snapshot and a restore."
  (let ((bknr.datastore::*store-verbose* nil) initial-objects)
    (funcall thunk)
    (let ((next-object-id (bknr.datastore::next-object-id (bknr.datastore::store-object-subsystem))))
      (setf initial-objects (object-classes-and-ids))
      (restore)
      (test-equal initial-objects (object-classes-and-ids))
      (test-equal next-object-id (bknr.datastore::next-object-id (bknr.datastore::store-object-subsystem)))
      (snapshot)
      (restore)
      (test-equal initial-objects (object-classes-and-ids))
      (test-equal next-object-id (bknr.datastore::next-object-id (bknr.datastore::store-object-subsystem))))))
 
(defmacro defdstest (name args &body body)
  (when args
    (error "unexpected arguments ~A to defdstest ~A" args name))
  `(setf (gethash ',name *tests*)
         (make-instance 'datastore-test-class
                        :unit :datastore
                        :name ',name
                        :body (lambda () (do-run-test (lambda () ,@body))))))
 
(defdstest store-setup ()
  (test-assert *store*))

(defdstest create-object ()
  (let ((obj (make-instance 'store-object)))
    (test-assert obj)
    (test-equal (list obj) (all-store-objects))))

(defdstest create-multiple-objects ()
  (let ((o1 (make-instance 'store-object))
        (o2 (make-instance 'store-object)))
    (test-assert o1)
    (test-assert o2)
    (test-equal (length (all-store-objects)) 2)
    (test-assert (subsetp (list o1 o2) (all-store-objects)))))

(defdstest delete-multiple-objects ()
  (let ((o1 (make-instance 'store-object))
        (o2 (make-instance 'store-object)))
    (test-assert o1)
    (test-assert o2)
    (test-equal (length (all-store-objects)) 2)
    (test-assert (subsetp (list o1 o2) (all-store-objects)))
    (delete-object o1)
    (test-equal (all-store-objects) (list o2))
    (delete-object o2)
    (test-equal (all-store-objects) nil)))

(defdstest restore ()
  (let ((object-id (store-object-id (make-instance 'store-object))))
    (restore)
    (test-equal 1 (length (all-store-objects)))
    (test-equal object-id (store-object-id (first (all-store-objects))))))

(defdstest snapshot-and-restore ()
  (let ((object-id (store-object-id (make-instance 'store-object))))
    (snapshot)
    (restore)
    (test-equal 1 (length (all-store-objects)))
    (test-equal object-id (store-object-id (first (all-store-objects))))))

(defdstest restore-multiple-objects ()
  (dotimes (i 10)
    (make-instance 'store-object))
  (restore)
  (test-equal 10 (length (all-store-objects))))

(defdstest snapshot-restore-multiple-objects ()
  (dotimes (i 10)
    (make-instance 'store-object))
  (snapshot)
  (restore)
  (test-equal (length (all-store-objects)) 10))

(defconstant +stress-size+ 10000)

(defdstest stress-test ()
  (format t "Creating ~A objects in two threads~%" +stress-size+)
  (time (bknr.datastore::without-sync ()
          (labels ((stress ()
                     (dotimes (i +stress-size+)
                       (make-instance 'store-object))))
            (let ((threads (list (bt:make-thread #'stress)
                                 (bt:make-thread #'stress))))
              (loop while (some #'bt:thread-alive-p threads)
                 do (sleep 1))))))
  (test-equal (length (all-store-objects)) (* 2 +stress-size+)))

(defdstest stress-test-2 ()
  (bknr.datastore::without-sync ()
    (format t "Creating ~A objects~%" +stress-size+)
    (time (dotimes (i +stress-size+)
            (make-instance 'store-object)))
    (format t "Deleting ~A objects~%" (length (all-store-objects)))
    (time (map-store-objects #'delete-object))
    (test-equal (all-store-objects) nil)))

(defdstest holes-test ()
  (dotimes (i +stress-size+)
    (let ((delete (zerop (random 2))))
      (with-transaction (:foo)
        (funcall (if delete #'delete-object #'identity)
                 (make-instance 'store-object))))))

(defdstest make-instance-in-anon-txn ()
  (with-transaction ()
    (make-instance 'store-object))
  (restore)
  (test-equal 1 (length (class-instances 'store-object))))

(defdstest make-instance-in-anon-txn ()
  (with-transaction ()
    (test-assert (make-instance 'store-object))))

(define-persistent-class parent ()
  ((child :update :initform nil :initarg nil)))

(define-persistent-class child ()
  ())

(defun object-classes-and-ids ()
  "Return a list of conses with the car being a class name and the cdr
  being the object id for all persistent objects in the store"
  (sort (mapcar (lambda (object)
                  (cons (class-name (class-of object))
                        (store-object-id object)))
                (all-store-objects))
        #'< :key #'cdr))

(defdstest make-referenced-object-in-anon-tx ()
  (with-transaction (:make)
    (make-instance 'parent :child (make-instance 'child))))

(defdstest serialize-circular-in-anon-txn ()
  (let ((parent (make-instance 'parent)))
    (with-transaction (:circular)
      (setf (parent-child parent) (make-instance 'child))))
  (restore)
  (test-equal (find-class 'child)
              (class-of (parent-child (first (class-instances 'parent))))))

(defdstest serialize-self-circular-in-anon-txn ()
  (let ((object (make-instance 'parent)))
    (with-transaction (:circular)
      (setf (parent-child object) object)))
  (restore)
  (let ((object (first (class-instances 'store-object))))
    (test-assert object)
    (test-equal object (parent-child object)))
  (snapshot)
  (restore)
  (let ((object (first (class-instances 'store-object))))
    (test-assert object)
    (test-equal object (parent-child object))))

(defdstest delete-object-in-anon-txn ()
  (let (object)
    (with-transaction (:make)
      (setf object (make-instance 'child)))
    (with-transaction (:delete)
      (delete-object object))
    (restore)
    (test-assert (object-destroyed-p object))))

(defdstest delete-object-and-check-object-id-of-next-1 ()
  (let (object-id)
    (with-transaction (:make)
      (let ((object (make-instance 'store-object)))
        (setf object-id (store-object-id object))
        (delete-object object)))
    (restore)
    (test-assert (< object-id (store-object-id (make-instance 'store-object))))))

(defdstest delete-object-and-check-object-id-of-next-2 ()
  (let (object-id)
    (with-transaction (:make)
      (let ((object (make-instance 'store-object)))
        (setf object-id (store-object-id object))))
    (snapshot)
    (restore)
    (test-assert (< object-id (store-object-id (make-instance 'store-object))))))

(defdstest delete-object-and-check-object-id-of-next-3 ()
  (let (object-id)
    (with-transaction (:make)
      (let ((object (make-instance 'store-object)))
        (setf object-id (store-object-id object))
        (delete-object object)))
    (snapshot)
    (restore)
    (test-assert (< object-id (store-object-id (make-instance 'store-object))))))

(define-persistent-class class-with-transient-slot ()
  ((slot :update
         :transient t
         :initform 0)))

(defdstest test-transient-slots ()
  (let ((object-id (store-object-id (make-instance 'class-with-transient-slot))))
    (restore)
    (test-equal 0 (class-with-transient-slot-slot (find-store-object object-id)))
    (setf (class-with-transient-slot-slot (find-store-object object-id)) 1)
    (restore)
    (test-equal 0 (class-with-transient-slot-slot (find-store-object object-id)))
    (snapshot)
    (restore)
    (test-equal 0 (class-with-transient-slot-slot (find-store-object object-id)))))

(define-persistent-class persistent-mixin ()
  ((mixin-slot :update
               :initform 2)))

(define-persistent-class inherit-multiple (persistent-mixin parent)
  ())

(defdstest multiple-inheritance-test ()
  (let* ((o1 (make-instance 'inherit-multiple :child (make-instance 'child)))
         (o2 (make-instance 'inherit-multiple :child o1)))
    (test-equal o1 (parent-child o2))))

(defdstest abort-anonymous-transaction ()
  (let ((parent (make-instance 'parent :child nil)))
    (ignore-errors
      (with-transaction (:abort)
        (setf (parent-child parent) (make-instance 'child))
        (error "abort")))
    (test-equal nil (parent-child parent))
    (test-equal nil (class-instances 'child))))

(define-persistent-class keyed-thing ()
  ((key :read :initarg :key
        :index-type string-unique-index
        :index-reader keyed-thing-with-key)))

(defdstest failed-duplicate-key-transaction-keeps-the-live-entry ()
  ;; The rolled-back object shares its key with the live one; undoing
  ;; its slot write must not remove the live object's index entry.
  (let ((live (make-instance 'keyed-thing :key "k")))
    (test-condition (with-transaction (:duplicate)
                      (make-instance 'keyed-thing :key "k"))
                    'index-existing-error)
    (test-equal live (keyed-thing-with-key "k"))
    (test-equal (list live) (class-instances 'keyed-thing))))

(defun id-counter ()
  "Return the store's next object id."
  (bknr.datastore::next-object-id (store-object-subsystem)))

(defdstest failed-transaction-removes-every-object-it-created ()
  ;; fc4e7be: undoing the id slot writes removes created objects from
  ;; their indices; the counter returns to its value at the start.
  (let ((counter (id-counter)))
    (ignore-errors
      (with-transaction (:fails)
        (let ((parent (make-instance 'parent)))
          (setf (parent-child parent) (make-instance 'child)))
        (error "rollback on purpose")))
    (test-equal nil (class-instances 'parent))
    (test-equal nil (class-instances 'child))
    (test-equal counter (id-counter))))

(defdstest failed-transaction-without-creation-leaves-the-counter ()
  (make-instance 'store-object)
  (let ((counter (id-counter)))
    (ignore-errors (with-transaction (:fails) (error "rollback on purpose")))
    (test-equal counter (id-counter))))

(setf (gethash 'failed-rollback-does-not-hand-out-ids-still-held *tests*)
      (make-instance
       'datastore-test-class
       :unit :datastore
       :name 'failed-rollback-does-not-hand-out-ids-still-held
       ;; Not DEFDSTEST: after a failed undo the live store and the log
       ;; differ, so DO-RUN-TEST's restore comparison does not
       ;; apply. When the undo itself fails, objects the transaction
       ;; created keep their ids. Ids stay unique (tutorial, object store
       ;; section), so the counter must not return to those ids.
       :body (lambda ()
               (let ((condition
                       (nth-value 1 (ignore-errors
                                      (with-transaction (:undo-fails)
                                        (make-instance 'keyed-thing :key "held")
                                        (push (list (lambda () (error "undo fails on purpose")))
                                              (bknr.datastore::anonymous-transaction-undo-log
                                               bknr.datastore::*current-transaction*))
                                        (error "rollback on purpose"))))))
                 (test-assert (typep condition 'bknr.datastore::rollback-failed))
                 (let ((held (keyed-thing-with-key "held"))
                       (next (make-instance 'keyed-thing :key "next")))
                   (test-assert held)
                   (test-assert (/= (store-object-id held) (store-object-id next)))
                   (test-equal held (store-object-with-id (store-object-id held)))
                   (test-equal next (store-object-with-id (store-object-id next))))))))

;;; A restore holds the store guard, and only the thread running it is inside
;;; the restore (object.lisp contract: other threads are outside any
;;; transaction). These tests pause a restore with a gate subsystem.

(defclass restore-gate ()
  ((entered :initform (bt:make-semaphore) :reader restore-gate-entered)
   (release :initform (bt:make-semaphore) :reader restore-gate-release)
   (armed :initform nil :accessor restore-gate-armed)
   (in-transaction-inside :initform :unset :accessor restore-gate-in-transaction-inside))
  (:documentation "Subsystem that, when armed, stops a restore inside
RESTORE-SUBSYSTEM until released, and records IN-TRANSACTION-P there."))

(defmethod restore-subsystem (store (gate restore-gate) &key until)
  (declare (ignore store until))
  (when (restore-gate-armed gate)
    (setf (restore-gate-in-transaction-inside gate) (in-transaction-p))
    (bt:signal-semaphore (restore-gate-entered gate))
    (bt:wait-on-semaphore (restore-gate-release gate))))

(defmethod snapshot-subsystem (store (gate restore-gate))
  (declare (ignore store))
  nil)

(defun call-with-paused-restore (function &key (after (constantly nil)))
  "Open a store with a keyed thing \"k\", snapshot it, and restore it in
another thread, paused after the snapshot is loaded. Call FUNCTION with
the gate and the restoring thread while the restore is paused, release
the restore and wait for it, then call AFTER. Close the store last."
  (let ((gate (make-instance 'restore-gate)))
    (make-instance 'mp-store
                   :directory (make-test-store-directory)
                   :subsystems (list (make-instance 'store-object-subsystem) gate))
    (unwind-protect
         (let ((store *store*))
           (make-instance 'keyed-thing :key "k")
           (snapshot)
           (setf (restore-gate-armed gate) t)
           (let ((restorer (bt:make-thread (lambda () (let ((*store* store)) (restore))))))
             (bt:wait-on-semaphore (restore-gate-entered gate))
             (unwind-protect (funcall function gate restorer)
               (setf (restore-gate-armed gate) nil)
               (bt:signal-semaphore (restore-gate-release gate))
               (bt:join-thread restorer)))
           (funcall after))
      (close-store))))

(defun register-restore-test (name body)
  "Register BODY as datastore test NAME. These tests open their own store
with a gate subsystem, so they are plain UNIT-TEST instances, like
DEFTEST makes, and not DATASTORE-TEST-CLASS, whose RUN-TEST :AROUND
opens a default store first."
  (setf (gethash name *tests*)
        (make-instance 'unit-test::unit-test :unit :datastore :name name :body body)))

(register-restore-test
 'in-transaction-p-during-a-restore-is-true-only-in-the-restoring-thread
 (lambda ()
   (let (outside)
     (call-with-paused-restore
      (lambda (gate restorer)
        (declare (ignore restorer))
        (setf outside (in-transaction-p))
        (test-equal t (restore-gate-in-transaction-inside gate))))
     (test-equal nil outside))))

(register-restore-test
 'with-transaction-from-another-thread-waits-for-a-restore
 (lambda ()
   (let (result writer)
     (call-with-paused-restore
      (lambda (gate restorer)
        (declare (ignore gate restorer))
        (setf writer (bt:make-thread
                      (lambda ()
                        (setf result (handler-case
                                         (with-transaction (:waits)
                                           (make-instance 'keyed-thing :key "made-during")
                                           :committed)
                                       (error (condition) condition))))))
        (sleep 0.2)
        (test-assert (bt:thread-alive-p writer))
        (test-equal nil (keyed-thing-with-key "made-during")))
      :after (lambda ()
               (bt:join-thread writer)
               (test-equal :committed result)
               (test-assert (keyed-thing-with-key "made-during")))))))

(register-restore-test
 'store-state-returns-to-opened-after-a-restore-another-thread-waited-on
 (lambda ()
   (let (writer)
     (call-with-paused-restore
      (lambda (gate restorer)
        (declare (ignore gate restorer))
        (setf writer (bt:make-thread
                      (lambda () (ignore-errors (make-instance 'keyed-thing :key "made-during"))))))
      :after (lambda ()
               (bt:join-thread writer)
               (test-equal :opened (bknr.datastore::store-state *store*)))))))

(register-restore-test
 'slot-write-from-another-thread-during-a-restore-is-refused
 (lambda ()
   (call-with-paused-restore
    (lambda (gate restorer)
      (declare (ignore gate restorer))
      (let ((thing (keyed-thing-with-key "k")))
        (test-condition (setf (slot-value thing 'key) "changed")
                        'bknr.datastore::persistent-slot-modified-outside-of-transaction)
        (test-equal "k" (slot-value thing 'key)))))))

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

(defun created-or-failed (index round)
  "Create a keyed thing outside any transaction on even INDEX; on odd INDEX,
create one inside an anonymous transaction that then fails. Errors are
ignored here and show up as missing objects."
  (ignore-errors
    (cond ((evenp index)
           (make-instance 'keyed-thing :key (format nil "~D-~D" index round)))
          (t (with-transaction (:fails)
               (make-instance 'keyed-thing :key (format nil "failed-~D-~D" index round))
               (error "fail on purpose"))))))

(defdstest failed-transactions-concurrent-with-creation-keep-ids-unique ()
  ;; A failing anonymous transaction rewinds the object id counter. The
  ;; rewind must never reach ids that other threads have allocated, or
  ;; later objects replace them in the id index.
  (run-in-threads 16 (lambda (index)
                       (dotimes (round 40)
                         (created-or-failed index round))))
  (let ((things (class-instances 'keyed-thing)))
    (test-equal (* 8 40) (length things))
    (test-equal (length things) (length (remove-duplicates (mapcar #'store-object-id things))))
    (test-assert (every (lambda (thing) (eq thing (store-object-with-id (store-object-id thing)))) things))
    (test-assert (every (lambda (thing) (eq thing (keyed-thing-with-key (keyed-thing-key thing)))) things))))

(defun run-datastore-test (name)
  (unit-test:run-test (gethash name *tests*)))
