;;;; src/ci.lisp
;;;;
;;;; GitHub Actions workflow. 40ants-ci writes it to .github/workflows/ci.yml
;;;; at the repository root when, in an image that has loaded this system,
;;;; (40ANTS-CI:GENERATE :BKNR.CI :PATH #P".github/workflows/") is evaluated
;;;; from the root. Without :PATH it writes under src/, next to this
;;;; system's asd file. Edit this file, not the generated YAML.
;;;;
;;;; The setup-lisp cache is off. It saves .qlot/ but not
;;;; ~/.cache/qlot/sources/, where qlot keeps git dependencies such as
;;;; sunny-side, so a restored cache leaves them as dangling symlinks.

(defpackage :bknr.ci
  (:use :cl)
  (:import-from #:40ants-ci/workflow #:defworkflow)
  (:import-from #:40ants-ci/jobs/lisp-job)
  (:import-from #:40ants-ci/steps/sh))

(in-package :bknr.ci)

(defworkflow ci
  :on-push-to "**"
  :on-pull-request t
  :cache nil
  :jobs ((40ants-ci/jobs/lisp-job:lisp-job
          :name "tests"
          :asdf-system "bknr.datastore"
          :steps ((40ants-ci/steps/sh:sh "All test suites" ".github/scripts/test.ros")))))
