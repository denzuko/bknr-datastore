(in-package :bknr.utils)

(5am:def-suite :bknr.utils)
(5am:in-suite :bknr.utils)

;;; ENSURE-DEDICATED-LPARALLEL-KERNEL had no permanent test before
;;; this: its own commit relied on live verification alone, noting
;;; "no test system exists for bknr.utils at all" as a separate,
;;; unbundled gap. This closes that gap.

(5am:test ensure-dedicated-lparallel-kernel-is-safe-under-concurrent-first-call
  (clrhash *dedicated-lparallel-kernels*)
  (let* ((n 50)
         (results (make-array n))
         (threads (loop for i from 0 below n
                         collect (let ((idx i))
                                   (bt:make-thread
                                    (lambda ()
                                      (setf (aref results idx)
                                            (ensure-dedicated-lparallel-kernel 'concurrency-test-kernel))))))))
    (mapc #'bt:join-thread threads)
    (5am:is (= 1 (length (remove-duplicates (coerce results 'list)))))))

(5am:test ensure-dedicated-lparallel-kernel-returns-the-same-kernel-for-the-same-name
  (clrhash *dedicated-lparallel-kernels*)
  (5am:is (eq (ensure-dedicated-lparallel-kernel 'same-name-test)
              (ensure-dedicated-lparallel-kernel 'same-name-test))))

(5am:test ensure-dedicated-lparallel-kernel-returns-different-kernels-for-different-names
  (clrhash *dedicated-lparallel-kernels*)
  (5am:is (not (eq (ensure-dedicated-lparallel-kernel 'name-one)
                    (ensure-dedicated-lparallel-kernel 'name-two)))))
