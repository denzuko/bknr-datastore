;; -*-Lisp-*-

(defsystem :bknr.datastore
  :name "baikonour datastore"
  :author "Hans Huebner <hans@huebner.org>"
  :author "Manuel Odendahl <manuel@bl0rg.net>"
  :version "0"
  :maintainer "Hans Huebner <hans@huebner.org>"
  :licence "BSD"
  :description "baikonour - launchpad for lisp satellites"
  :depends-on (:cl-interpol
               :closer-mop
               :alexandria
               :unit-test
               :bknr.utils
               :bknr.indices
               :yason
               :trivial-utf-8
               #+sbcl :sb-posix)
  :components ((:module "data"
                :components
                ((:file "package")
                 (:file "encoding" :depends-on ("package"))
                 (:file "txn" :depends-on ("encoding" "package"))
                 (:file "object" :depends-on ("txn" "package"))
                 (:file "object-tests" :depends-on ("object" "package"))
                 (:file "json" :depends-on ("object"))
                 (:file "blob" :depends-on ("txn" "object" "package")))))
  :in-order-to ((test-op (test-op :bknr.datastore/test))))

(defsystem :bknr.datastore/test  
  :depends-on (:bknr.datastore :fiveam :cl-store :bknr.utils)
  :components ((:module "data"
                :components
                ((:file "encoding-test")
                 (:file "object-tests"))))
  :perform (test-op (o c)
             (symbol-call :fiveam :run! :bknr.datastore)))

(defsystem :bknr.datastore/bdd
  :description "Gherkin features for bknr.datastore, run through sunny-side."
  :depends-on (:bknr.datastore :sunny-side :fiveam :bordeaux-threads :uiop)
  :pathname "../features/step_definitions/"
  :components ((:file "transaction-rollback-steps")
               (:file "restore-concurrent-writes-steps"))
  :perform (test-op (o c)
             (symbol-call :bknr.datastore.bdd :run-bdd)))
