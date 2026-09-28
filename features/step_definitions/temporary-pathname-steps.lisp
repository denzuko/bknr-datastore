;;;; features/step_definitions/temporary-pathname-steps.lisp
;;;;
;;;; Steps for features/temporary-pathname.feature, run as FiveAM tests
;;;; through sunny-side. Every step closes over one lexical WORLD.

(defpackage :bknr.utils.bdd
  (:use :cl :sunny-side)
  (:import-from :fiveam #:is #:is-true #:is-false)
  (:export #:run-bdd))

(in-package :bknr.utils.bdd)

(defstruct world
  "State one scenario builds up and later steps check."
  pathname pathnames expected signalled)

(defun signalled-by (function)
  "Call FUNCTION and return the error it signals, or NIL."
  (handler-case (progn (funcall function) nil)
    (error (condition) condition)))

(defun write-scratch-file (pathname)
  "Write one line to PATHNAME, creating the file."
  (with-open-file (out pathname :direction :output :if-does-not-exist :create)
    (write-line "scratch" out)))

(defun collect-in-threads (threads count function)
  "Run FUNCTION COUNT times on each of THREADS threads, released together,
and return every value it returned."
  (let* ((lock (bt:make-lock))
         (gate (bt:make-semaphore))
         (values '())
         (workers (loop repeat threads
                        collect (bt:make-thread
                                 (lambda ()
                                   (bt:wait-on-semaphore gate)
                                   (loop repeat count
                                         do (let ((value (funcall function)))
                                              (bt:with-lock-held (lock) (push value values)))))))))
    (bt:signal-semaphore gate :count threads)
    (mapc #'bt:join-thread workers)
    values))

(let ((world (make-world)))
  (flet ((make (&rest arguments)
           (setf world (make-world))
           (setf (world-signalled world)
                 (signalled-by (lambda ()
                                 (setf (world-pathname world)
                                       (apply #'bknr.utils:make-temporary-pathname arguments))))))
         (in-block (defaults &key write fail)
           (setf world (make-world))
           (setf (world-signalled world)
                 (signalled-by (lambda ()
                                 (bknr.utils:with-temporary-file (pathname :defaults defaults)
                                   (setf (world-pathname world) pathname)
                                   (when write (write-scratch-file pathname))
                                   (when fail (error "signalled inside the block")))))))
         (name-starts-with-p (prefix)
           (eql 0 (search prefix (pathname-name (world-pathname world))))))

    (When! "^I make a temporary pathname with no arguments$" ()
      (make))

    (When! "^I make a temporary pathname with defaults \"([^\"]*)\"$" (defaults)
      (make :defaults defaults))

    (When! "^I make a temporary pathname with the name \"([^\"]*)\"$" (name)
      (make :name name))

    (When! "^I make a temporary pathname with the number (\\d+) as defaults$" (number)
      (make :defaults (parse-integer number)))

    (When! "^(\\d+) threads each make (\\d+) temporary pathnames with defaults \"([^\"]*)\"$" (threads count defaults)
      (setf world (make-world :expected (* (parse-integer threads) (parse-integer count))))
      (setf (world-pathnames world)
            (collect-in-threads (parse-integer threads) (parse-integer count)
                                (lambda () (bknr.utils:make-temporary-pathname :defaults defaults)))))

    (When! "^I write a file inside WITH-TEMPORARY-FILE with defaults \"([^\"]*)\"$" (defaults)
      (in-block defaults :write t))

    (When! "^I write a file inside WITH-TEMPORARY-FILE with defaults \"([^\"]*)\" and then signal an error$" (defaults)
      (in-block defaults :write t :fail t))

    (When! "^I run WITH-TEMPORARY-FILE with defaults \"([^\"]*)\" without writing$" (defaults)
      (in-block defaults))

    (Then! "^its name should start with \"([^\"]*)\"$" (prefix)
      (is-false (world-signalled world))
      (is-true (and (world-pathname world) (name-starts-with-p prefix))))

    (Then! "^it should have no directory$" ()
      (is (null (pathname-directory (world-pathname world)))))

    (Then! "^its host should be the host of the default pathname defaults$" ()
      (is (equal (pathname-host *default-pathname-defaults*)
                 (pathname-host (world-pathname world)))))

    (Then! "^its directory should be \"([^\"]*)\"$" (directory)
      (is-false (world-signalled world))
      (is (equal (pathname-directory (pathname directory))
                 (pathname-directory (world-pathname world)))))

    (Then! "^it should name no existing file$" ()
      (is-false (probe-file (world-pathname world))))

    (Then! "^every pathname should name no existing file$" ()
      (is (= (world-expected world) (length (world-pathnames world))))
      (is (notany #'probe-file (world-pathnames world))))

    (Then! "^an error should have been signalled$" ()
      (is (typep (world-signalled world) 'error)))

    (Then! "^no error should have been signalled$" ()
      (is-false (world-signalled world)))

    (Then! "^the file should not exist after the block$" ()
      (is-true (world-pathname world))
      (is-false (probe-file (world-pathname world))))

    (Then! "^the error should have reached the caller$" ()
      (is (search "signalled inside the block" (princ-to-string (world-signalled world)))))))

(define-feature-tests
    #.(asdf:system-relative-pathname :bknr.utils "../features/temporary-pathname.feature")
  :suite temporary-pathname-suite)

(defun run-bdd ()
  "Run the temporary pathname feature and return T when every scenario passed."
  (fiveam:run! 'temporary-pathname-suite))
