(in-package :bknr.utils)

(5am:in-suite :bknr.utils)

;;; MAKE-TEMPORARY-PATHNAME passes DEFAULTS to MAKE-PATHNAME, where it must
;;; be a pathname designator (CLHS MAKE-PATHNAME, glossary). NIL, the
;;; function's own default, means DEFAULTS was not supplied.

(5am:test make-temporary-pathname-without-defaults-returns-a-bare-name
  (let ((pathname (make-temporary-pathname)))
    (5am:is (pathnamep pathname))
    (5am:is (null (pathname-directory pathname)))
    (5am:is (equal (pathname-host *default-pathname-defaults*) (pathname-host pathname)))
    (5am:is (eql 0 (search "tmp-" (pathname-name pathname))))))

(5am:test make-temporary-pathname-treats-explicit-nil-defaults-as-omitted
  (let ((pathname (make-temporary-pathname :defaults nil)))
    (5am:is (pathnamep pathname))
    (5am:is (null (pathname-directory pathname)))))

(5am:test make-temporary-pathname-accepts-a-namestring
  (5am:is (equal '(:absolute "tmp")
                 (pathname-directory (make-temporary-pathname :defaults "/tmp/")))))

(5am:test make-temporary-pathname-accepts-a-pathname
  (5am:is (equal '(:absolute "tmp")
                 (pathname-directory (make-temporary-pathname :defaults #p"/tmp/")))))

(5am:test make-temporary-pathname-accepts-a-file-stream
  (with-temporary-file (file :defaults "/tmp/")
    (with-open-file (stream file :direction :output :if-does-not-exist :create)
      (5am:is (equal '(:absolute "tmp")
                     (pathname-directory (make-temporary-pathname :defaults stream)))))))

(5am:test make-temporary-pathname-takes-the-type-from-defaults
  (5am:is (equal "lisp" (pathname-type (make-temporary-pathname :defaults "/tmp/x.lisp")))))

(5am:test make-temporary-pathname-with-an-empty-name-starts-with-a-hyphen
  (let ((pathname (make-temporary-pathname :name "" :defaults "/tmp/")))
    (5am:is (eql 0 (search "-" (pathname-name pathname))))
    (5am:is-false (probe-file pathname))))

(5am:test make-temporary-pathname-refuses-a-non-designator
  (5am:signals error (make-temporary-pathname :defaults 42)))

;;; WITH-TEMPORARY-FILE deletes the file after BODY when it exists, through
;;; UNWIND-PROTECT.

(5am:test with-temporary-file-deletes-a-written-file
  (let ((seen nil))
    (with-temporary-file (file :defaults "/tmp/")
      (setf seen file)
      (with-open-file (out file :direction :output :if-does-not-exist :create)
        (write-line "x" out)))
    (5am:is-false (probe-file seen))))

(5am:test with-temporary-file-deletes-the-file-when-body-signals
  (let ((seen nil))
    (5am:signals simple-error
      (with-temporary-file (file :defaults "/tmp/")
        (setf seen file)
        (with-open-file (out file :direction :output :if-does-not-exist :create)
          (write-line "x" out))
        (error "signalled inside the block")))
    (5am:is-false (probe-file seen))))

(5am:test with-temporary-file-without-a-file-signals-nothing
  (5am:finishes (with-temporary-file (file) file)))

(5am:test with-temporary-file-after-body-deleted-the-file-signals-nothing
  (5am:finishes
    (with-temporary-file (file :defaults "/tmp/")
      (with-open-file (out file :direction :output :if-does-not-exist :create)
        (write-line "x" out))
      (delete-file file))))
