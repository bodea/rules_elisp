;;; runner.el --- run ERT tests with Bazel      -*- lexical-binding: t; -*-

;; Copyright 2020 Google LLC
;;
;; Licensed under the Apache License, Version 2.0 (the "License");
;; you may not use this file except in compliance with the License.
;; You may obtain a copy of the License at
;;
;;     https://www.apache.org/licenses/LICENSE-2.0
;;
;; Unless required by applicable law or agreed to in writing, software
;; distributed under the License is distributed on an "AS IS" BASIS,
;; WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
;; See the License for the specific language governing permissions and
;; limitations under the License.

;;; Commentary:

;; This library runs ERT tests under Bazel.  It provides support for the
;; --test_filter flag, as described in
;; https://docs.bazel.build/versions/3.0.0/test-encyclopedia.html#initial-conditions.

;;; Code:

(require 'backtrace nil :noerror)  ; only in Emacs 27
(require 'bytecomp)
(require 'cl-lib)
(require 'debug)
(require 'edebug)
(require 'ert)
(require 'json)
(require 'pp)
(require 'rx)

(defun elisp/ert/run-batch-and-exit ()
  "Run ERT tests in batch mode.
This is similar to ‘ert-run-tests-batch-and-exit’, but uses the
TESTBRIDGE_TEST_ONLY environmental variable as test selector.
Treat all remaining command-line arguments as names of test
source files and load them."
  (or noninteractive (error "This function works only in batch mode"))
  (let* ((attempt-stack-overflow-recovery nil)
         (attempt-orderly-shutdown-on-fatal-signal nil)
         (print-escape-newlines t)
         (pp-escape-newlines t)
         (print-circle t)
         (print-gensym t)
         (print-level 8)
         (print-length 50)
         (edebug-initial-mode 'Go-nonstop)  ; ‘step’ doesn’t work in batch mode
         (report-file (elisp/ert/pop--option "--report"))
         (test-filter (getenv "TESTBRIDGE_TEST_ONLY"))
         (random-seed (or (getenv "TEST_RANDOM_SEED") ""))
         (coverage-enabled (equal (getenv "COVERAGE") "1"))
         (coverage-dir (getenv "COVERAGE_DIR"))
         (selector (if (member test-filter '(nil "")) t (read test-filter)))
         (load-suffixes
          ;; Prefer source files when coverage is requested, as only those can
          ;; be instrumented.
          (if coverage-enabled (cons ".el" load-suffixes) load-suffixes))
         (load-buffers ())
         (load-source-file-function
          (if coverage-enabled
              (lambda (fullname file noerror _nomessage)
                (cond
                 ((file-readable-p fullname)
                  (push (elisp/ert/load--instrument fullname file)
                        load-buffers))
                 (noerror nil)
                 (t (signal 'file-error (list "Cannot open load file" file)))))
            load-source-file-function)))
    (and coverage-enabled (member coverage-dir '(nil ""))
         (error "Coverage requested but COVERAGE_DIR not set"))
    (random random-seed)
    (mapc #'load command-line-args-left)
    (let ((tests (ert-select-tests selector t))
          (unexpected 0)
          (report `((startTime . ,(elisp/ert/json--timestamp))))
          (test-reports ())
          (start-time (current-time)))
      (or tests (error "Selector %S doesn’t match any tests" selector))
      (elisp/ert/log--message "Running %d tests" (length tests))
      (dolist (test tests)
        (elisp/ert/log--message "Running test %s" (ert-test-name test))
        (let* ((name (ert-test-name test))
               (start-time (current-time))
               (result (ert-run-test test))
               (duration (time-subtract nil start-time))
               (expected (ert-test-result-expected-p test result))
               (status (ert-string-for-test-result result expected))
               (report `((name . ,(symbol-name name))
                         (elapsed . ,(elisp/ert/json--duration duration))
                         (status . ,(upcase status))
                         (expected . ,(if expected t :json-false)))))
          (elisp/ert/log--message "Test %s %s and took %d ms" name status
                                  (* (float-time duration) 1000))
          (or expected (cl-incf unexpected))
          (when (ert-test-result-with-condition-p result)
            (let ((message (elisp/ert/failure--message name result)))
              (message "%s" message)
              (push `(message . ,message) report)))
          (push report test-reports)))
      (push `(elapsed . ,(elisp/ert/json--duration
                          (time-subtract nil start-time)))
            report)
      (push `(tests . ,(nreverse test-reports)) report)
      (cl-callf nreverse report)
      (elisp/ert/log--message "Running %d tests finished, %d results unexpected"
                              (length tests) unexpected)
      (when report-file
        ;; Rather than trying to write a well-formed XML file in Emacs Lisp,
        ;; write the report as a JSON file and let an external binary deal with
        ;; the conversion to XML.
        (write-region (json-encode report) nil report-file))
      (when load-buffers
        (elisp/ert/write--coverage-report coverage-dir load-buffers))
      (kill-emacs (min unexpected 1)))))

(defun elisp/ert/pop--option (name)
  "Pop a command-line option named NAME from ‘command-line-args-left’.
If the head of ‘command-line-args-left’ starts with “NAME=”,
remove it and return the value.  Otherwise, return nil."
  (cl-check-type name string)
  (let ((arg (car command-line-args-left))
        (prefix (concat name "=")))
    (when (and arg (string-prefix-p prefix arg))
      (pop command-line-args-left)
      (substring-no-properties arg (length prefix)))))

(defun elisp/ert/failure--message (name result)
  "Return a failure message for the RESULT of a failing test.
NAME is the name of the test."
  (cl-check-type name symbol)
  (cl-check-type result ert-test-result-with-condition)
  (with-temp-buffer
    (let ((backtrace (ert-test-result-with-condition-backtrace result)))
      (cond ((fboundp 'backtrace-to-string)  ; Emacs 27
             (insert (backtrace-to-string backtrace)))
            ((fboundp 'debugger-insert-backtrace)  ; Emacs 26
             (debugger-insert-backtrace backtrace nil))
            (t (error "Unsupported Emacs version"))))
    (goto-char (point-min))
    (while (not (eobp))
      (message "    %s"
               (buffer-substring-no-properties
                (point) (min (line-end-position) (+ 120 (point)))))
      (forward-line))
    (goto-char (point-min))
    (insert (format-message "  Test %s backtrace:\n" name))
    (goto-char (point-max))
    (dolist (info (ert-test-result-with-condition-infos result))
      (insert "  " (car info) (cdr info) ?\n))
    (insert (format-message "  Test %s condition:\n" name))
    (insert "    ")
    (pp (ert-test-result-with-condition-condition result)
        (current-buffer))
    (insert ?\n)
    (buffer-substring-no-properties (point-min) (point-max))))

(defun elisp/ert/load--instrument (fullname file)
  "Load and instrument the Emacs Lisp file FULLNAME.
FILE is an abbreviated name as described in
‘load-source-file-function’, which see.  Return a live buffer
visiting the file."
  (cl-check-type fullname string)
  (cl-check-type file string)
  ;; Similar to testcover.el, we use Edebug to collect coverage
  ;; information.  The rest of this function is similar to
  ;; ‘load-with-code-conversion’, but we ignore some edge cases.
  (let ((buffer (generate-new-buffer (format "*%s*" file)))
        (reporter (make-progress-reporter
                   (format-message "Loading and instrumenting %s..." file)))
        (load-in-progress t)
        (load-file-name fullname)
        (set-auto-coding-for-load t)
        (inhibit-file-name-operation nil)
        (edebug-all-defs t))
    (with-current-buffer buffer
      (insert-file-contents fullname :visit)
      ;; The file buffer needs to be current for Edebug
      ;; instrumentation to work.
      (eval-buffer buffer nil fullname nil :do-allow-print)
      ;; Yuck!  We have to mess with internal Edebug data here.
      ;; Byte-compile all functions to be a bit more realistic.
      (dolist (data edebug-form-data)
        (byte-compile (edebug--form-data-name data))))
    (do-after-load-evaluation fullname)
    (progress-reporter-done reporter)
    buffer))

(defun elisp/ert/write--coverage-report (coverage-dir buffers)
  "Write a coverage report to a file in COVERAGE-DIR.
BUFFERS is a list of buffers containing Emacs Lisp sources
instrumented using Edebug."
  (cl-check-type coverage-dir string)
  (cl-check-type buffers cons)
  (with-temp-buffer
    (let ((root (getenv "TEST_SRCDIR")))
      (dolist (buffer buffers)
        (elisp/ert/insert--coverage-report buffer root)
        (kill-buffer buffer)))
    (write-region nil nil (expand-file-name "emacs-lisp.dat" coverage-dir)
                  nil nil nil 'excl)))

(defun elisp/ert/insert--coverage-report (buffer root)
  "Insert a coverage report into the current buffer.
BUFFER must be a different buffer visiting an Emacs Lisp source
file that has been instrumented with Edebug.  ROOT is a directory
to be used as root."
  (cl-check-type buffer buffer-live)
  (cl-check-type root string)
  (let ((file-name (elisp/ert/sanitize--string
                    (file-relative-name (buffer-file-name buffer) root)))
        (functions ())
        (functions-hit 0)
        (lines (make-hash-table :test #'eql)))
    (with-current-buffer buffer
      (widen)
      ;; Yuck!  More messing around with Edebug internals.
      (dolist (data edebug-form-data)
        (let* ((name (edebug--form-data-name data))
               (frequencies (get name 'edebug-freq-count))
               ;; We don’t really know the number of function calls,
               ;; so assume it’s the same as the hit count of the
               ;; first breakpoint.
               (calls (or (cl-find 0 frequencies :test-not #'eq) 0))
               (stuff (get name 'edebug))
               (begin (car stuff))
               (offsets (caddr stuff)))
          (cl-incf functions-hit (min calls 1))
          (cl-assert (eq (marker-buffer begin) buffer))
          (cl-assert (eql (length frequencies) (length offsets)))
          (cl-loop for offset across offsets
                   ;; This can’t be ‘and’ due to
                   ;; https://debbugs.gnu.org/cgi/bugreport.cgi?bug=40727.
                   for freq across frequencies
                   for position = (+ begin offset)
                   for line = (line-number-at-pos position)
                   do (cl-callf max (gethash line lines 0) freq))
          (push (list (elisp/ert/sanitize--string (symbol-name name))
                      (line-number-at-pos begin) calls)
                functions))))
    (cl-callf nreverse functions)
    ;; The expected format is described to some extend in the
    ;; geninfo(1) man page.
    (insert (format "SF:%s\n" file-name))
    (dolist (func functions)
      (insert (format "FN:%d,%s\n" (cadr func) (car func))))
    (dolist (func functions)
      (insert (format "FNDA:%d,%s\n" (caddr func) (car func))))
    (insert (format "FNF:%d\n" (length functions)))
    (insert (format "FNH:%d\n" functions-hit))
    (let ((list ())
          (lines-hit 0))
      (maphash (lambda (line freq) (push (cons line freq) list)) lines)
      (cl-callf sort list #'car-less-than-car)
      (dolist (line list)
        (cl-incf lines-hit (min (cdr line) 1))
        (insert (format "DA:%d,%d\n" (car line) (cdr line))))
      (insert (format "LH:%d\nLF:%d\nend_of_record\n"
                      lines-hit (hash-table-count lines))))))

(defun elisp/ert/log--message (format &rest args)
  "Like ‘(message FORMAT ARGS…)’, but also print a timestamp."
  (cl-check-type format string)
  (message "[%s] %s"
           (format-time-string "%F %T.%3N")
           (apply #'format-message format args)))

(defun elisp/ert/sanitize--string (string)
  "Return a sanitized version of STRING for the coverage file."
  (cl-check-type string string)
  ;; The coverage file is line-based, so the string shouldn’t contain any
  ;; newlines.
  (replace-regexp-in-string (rx (not (any alnum blank punct))) "?" string))

;; The next two functions serialize time values in the format described at
;; https://developers.google.com/protocol-buffers/docs/proto3#json.

(defun elisp/ert/json--timestamp (&optional time)
  "Format TIME or the current time for JSON."
  (format-time-string "%FT%T.%NZ" time t))

(defun elisp/ert/json--duration (duration)
  "Format DURATION for JSON."
  (format-time-string "%s.%Ns" duration t))

(provide 'elisp/ert/runner)
;;; runner.el ends here
