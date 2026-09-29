;;;; bknr.ci.asd

(defsystem :bknr.ci
  :description "40ants-ci definition of the GitHub Actions workflow."
  :depends-on (:40ants-ci)
  :components ((:file "ci")))
