(require 'ert)
(require 'edebug)
(require 'helpful)
(require 'python)

(defun test-foo ()
  "Docstring here."
  nil)

(defun test-foo-advised ()
  "Docstring here too."
  nil)

(autoload 'some-unused-function "somelib.el")

(defadvice test-foo-advised (before test-advice1 activate)
  "Placeholder advice 1."
  nil)

(defadvice test-foo-advised (after test-advice2 activate)
  "Placeholder advice 2."
  nil)

(ert-deftest helpful--docstring ()
  "Basic docstring fetching."
  (should
   (equal
    (helpful--docstring #'test-foo t)
    "Docstring here.")))

(ert-deftest helpful--docstring-symbol ()
  "Correctly handle quotes around symbols."
  ;; We should replace quoted symbols with links, so the punctuation
  ;; should not be in the output.
  (let* ((formatted-docstring (helpful--format-docstring "`message'")))
    (should
     (equal formatted-docstring "message")))
  ;; We should handle stray backquotes.
  (let* ((formatted-docstring (helpful--format-docstring "`foo `message'")))
    (should
     (equal formatted-docstring "`foo message"))))

(ert-deftest helpful--docstring-unescape ()
  "Discard \\=\\= in docstrings."
  (let* ((docstring (helpful--docstring #'apply t))
         (formatted-docstring (helpful--format-docstring docstring)))
    (should
     (not (s-contains-p "\\=" formatted-docstring)))))

(ert-deftest helpful--docstring-keymap ()
  "Handle keymap references in docstrings."
  (let* ((formatted-docstring
          (helpful--format-docstring
           "\\<minibuffer-local-map>\\[next-history-element]")))
    ;; This test will fail in a local Emacs instance that has modified
    ;; minibuffer keybindings.
    (should
     (string-equal formatted-docstring "M-n"))))

(ert-deftest helpful--docstring-advice ()
  "Get the docstring on advised functions."
  (should
   (equal
    (helpful--docstring #'test-foo-advised t)
    "Docstring here too.")))

(defun test-foo-no-docstring ()
  nil)

(ert-deftest helpful--no-docstring ()
  "We should not crash on a function without a docstring."
  (should (null (helpful--docstring #'test-foo-no-docstring t))))

(ert-deftest helpful--interactively-defined-fn ()
  "We should not crash on a function without source code."
  (eval '(defun test-foo-defined-interactively () 42))
  (with-temp-buffer
    (helpful-function #'test-foo-defined-interactively)
    (should (equal (buffer-name) "*helpful function: test-foo-defined-interactively*"))))

(ert-deftest helpful--edebug-fn ()
  "We should not crash on a function with edebug enabled."
  (let ((edebug-all-forms t)
        (edebug-all-defs t))
    (with-temp-buffer
      (insert "(defun test-foo-edebug () 44)")
      (goto-char (point-min))
      (shut-up
        (eval (eval-sexp-add-defvars (edebug-read-top-level-form)) t))))
  (helpful-function #'test-foo-edebug))

(defun test-foo-return-arg (s)
  "blah blah."
  s)

(ert-deftest helpful--edebug-p ()
  "Ensure that we don't crash on a function whose body ends with
symbol (not a form)."
  (should
   (not (helpful--edebug-p #'test-foo-return-arg))))

(defun test-foo-usage-docstring ()
  "\n\n(fn &rest ARGS)"
  nil)

(ert-deftest helpful--usage-docstring ()
  "If a function docstring only has usage, do not return it."
  (should (null (helpful--docstring #'test-foo-usage-docstring t))))

(defun test-foo-no-properties ()
  nil)

(ert-deftest helpful--primitive-p ()
  ;; Defined in C.
  (should (helpful--primitive-p 'message t))
  ;; Defined in C, but an alias.
  (should (helpful--primitive-p 'not t))
  ;; Defined in elisp.
  (should (not (helpful--primitive-p 'when t))))

(ert-deftest helpful-callable ()
  ;; We should not crash when looking at macros.
  (helpful-callable 'when)
  ;; Special forms should work too.
  (helpful-callable 'if)
  ;; Smoke test for special forms when we have the Emacs C source
  ;; loaded.
  (let* ((emacs-src-path (f-join default-directory "emacs-25.3" "src")))
    (if (f-exists-p emacs-src-path)
        (let ((find-function-C-source-directory emacs-src-path))
          (helpful-callable 'if))
      (message "No Emacs source code found at %S, skipping test. Run ./download_emacs_src.sh."
               emacs-src-path))))

(ert-deftest helpful--no-symbol-properties ()
  "Helpful should handle functions without any symbol properties."
  ;; Interactively evaluating this file will set edebug properties on
  ;; test-foo, so remove all properties.
  (setplist #'test-foo-no-properties nil)

  ;; This shouldn't throw any errors.
  (helpful-function #'test-foo-no-properties))

(ert-deftest helpful--split-first-line ()
  ;; Don't modify a single line string.
  (should
   (equal (helpful--split-first-line "foo") "foo"))
  ;; Don't modify a two-line string if we don't end with .
  (should
   (equal (helpful--split-first-line "foo\nbar") "foo\nbar"))
  ;; If the second line is already empty, do nothing.
  (should
   (equal (helpful--split-first-line "foo.\n\nbar") "foo.\n\nbar"))
  ;; But if we have a single sentence and no empy line, insert one.
  (should
   (equal (helpful--split-first-line "foo.\nbar") "foo.\n\nbar")))

(ert-deftest helpful--format-reference ()
  (should
   (equal
    (helpful--format-reference '(def foo) 10 1 123 "/foo/bar.el")
    "(def foo ...) 1 reference"))
  (should
   (equal
    (helpful--format-reference '(advice-add 'bar) 10 1 123 "/foo/bar.el")
    "(advice-add 'bar ...) 1 reference")))

(ert-deftest helpful--format-docstring ()
  "Ensure we handle `foo' formatting correctly."
  ;; If it's bound, we should link it.
  (let* ((formatted (helpful--format-docstring "foo `message'."))
         (m-position (s-index-of "m" formatted)))
    (should (get-text-property m-position 'button formatted)))
  ;; If it's not bound, we should not.
  (let* ((formatted (helpful--format-docstring "foo `messagexxx'."))
         (m-position (s-index-of "m" formatted)))
    (should (not (get-text-property m-position 'button formatted)))
    ;; But we should always remove the backticks.
    (should (equal formatted "foo messagexxx.")))
  ;; Don't require the text between the quotes to be a valid symbol, e.g.
  ;; support `C-M-\' (found in `vhdl-mode').
  (let* ((formatted (helpful--format-docstring "foo `C-M-\\'")))
    (should (equal formatted "foo C-M-\\"))))

(ert-deftest helpful--format-docstring-escapes ()
  "Ensure we handle escaped quotes correctly."
  (let* ((formatted (helpful--format-docstring "foo \\=`message\\='."))
         (m-position (s-index-of "m" formatted)))
    (should (equal formatted "foo `message'."))
    (should (not (get-text-property m-position 'button formatted)))))

(ert-deftest helpful--format-docstring-command-keys ()
  "Ensure we propertize references to command key sequences."
  ;; This test will fail in your current Emacs instance if you've
  ;; overridden the `set-mark-command' keybinding.
  (-let [formatted (helpful--format-docstring "\\[set-mark-command]")]
    (should
     (string-equal formatted "C-SPC"))
    (should
     (get-text-property 0 'button formatted)))
  ;; If we have quotes around a key sequence, we should not propertize
  ;; it as the button styling will no longer be visible.
  (-let [formatted (helpful--format-docstring "`\\[set-mark-command]'")]
    (should
     (string-equal formatted "C-SPC"))
    (should
     (eq
      (get-text-property 0 'face formatted)
      'button)))
  ;; Propertize mode maps.
  (-let [formatted (helpful--format-docstring "`\\{python-mode-map}'")]
    (should
     (s-contains-p "run-python" formatted))))

(ert-deftest helpful--format-docstring--info ()
  "Ensure we propertize references to the info manual."
  ;; This is the typical format.
  (let* ((formatted (helpful--format-docstring "Info node `(elisp)foo'"))
         (paren-position (s-index-of "(" formatted)))
    (should
     (string-equal formatted "Info node (elisp)foo"))
    (should
     (get-text-property paren-position 'button formatted)))
  ;; Some functions, such as `signal', use 'anchor'.
  (let* ((formatted (helpful--format-docstring "Info anchor `(elisp)foo'"))
         (paren-position (s-index-of "(" formatted)))
    (should
     (string-equal formatted "Info anchor (elisp)foo"))
    (should
     (get-text-property paren-position 'button formatted)))
  ;; Ensure we handle wrapped lines too, e.g. in `org-odt-pixels-per-inch'.
  (let* ((formatted (helpful--format-docstring "Info node `(elisp)foo \nbar'"))
         (paren-position (s-index-of "(" formatted)))
    (should
     (string-equal formatted "Info node (elisp)foo \nbar"))
    (should
     (get-text-property paren-position 'button formatted))))

(ert-deftest helpful--format-docstring--url ()
  "Ensure we propertize URLs with backticks."
  (let* ((formatted (helpful--format-docstring "URL `http://example.com'"))
         (url-position (s-index-of "h" formatted)))
    (should
     (string-equal formatted "URL http://example.com"))
    (should
     (get-text-property url-position 'button formatted))))

(ert-deftest helpful--format-docstring--bare-url ()
  "Ensure we propertize URLs without backticks."
  (let* ((formatted (helpful--format-docstring "http://example.com\nbar"))
         (url-position (s-index-of "h" formatted)))
    (should
     (string-equal formatted "http://example.com\nbar"))
    (should
     (get-text-property url-position 'button formatted))
    (should
     (equal
      (get-text-property url-position 'url formatted)
      "http://example.com")))
  ;; Don't consider trailing punctuation to be part of the URL.
  (let* ((formatted (helpful--format-docstring "See http://example.com."))
         (url-position (s-index-of "h" formatted)))
    (should
     (string-equal formatted "See http://example.com."))
    (should
     (equal
      (get-text-property url-position 'url formatted)
      "http://example.com"))))

(ert-deftest helpful--definition-c-vars ()
  "Handle definitions of variables in C source code."
  (let* ((emacs-src-path (f-join default-directory "emacs-25.3" "src")))
    (if (f-exists-p emacs-src-path)
        (let ((find-function-C-source-directory emacs-src-path))
          (helpful--definition 'default-directory nil))
      (message "No Emacs source code found at %S, skipping test. Run ./download_emacs_src.sh"
               emacs-src-path))))

(setq helpful-var-without-defvar 'foo)

(ert-deftest helpful--definition-no-defvar ()
  "Ensure we don't crash on calling `helpful--definition' on
variables defined without `defvar'."
  (helpful--definition 'helpful-var-without-defvar nil))

(ert-deftest helpful--definition-buffer-opened ()
  "Ensure we mark buffers as opened for variables."
  (require 'python)
  ;; This test will fail if you already have python.el.gz open in your
  ;; Emacs instance.
  (-let [(buf pos opened) (helpful--definition 'python-indent-offset nil)]
    (should (bufferp buf))
    (should opened)))

(ert-deftest helpful--definition-edebug-fn ()
  "Ensure we use the position information set by edebug, if present."
  ;; Test with both edebug enabled and disabled. The edebug property
  ;; on the symbol varies based on this.
  (dolist (edebug-on (list nil t))
    (let ((edebug-all-forms edebug-on)
          (edebug-all-defs edebug-on))
      (with-temp-buffer
        (insert "(defun test-foo-edebug-defn () 44)")
        (goto-char (point-min))
        (shut-up
          (eval (eval-sexp-add-defvars (edebug-read-top-level-form)) t))

        (-let [(buf pos opened) (helpful--definition 'test-foo-edebug-defn t)]
          (should buf))))))

(ert-deftest helpful-variable ()
  "Smoke test for `helpful-variable'."
  (helpful-variable 'tab-width))

(ert-deftest helpful--signature ()
  "Ensure that autoloaded functions are handled gracefully"
  (should
   (equal (helpful--signature 'some-unused-function)
          "(some-unused-function [Arg list not available until function definition is loaded.])")))

(ert-deftest helpful--signature--advertised ()
  "Ensure that we respect functions that declare `advertised-calling-convention'."
  (should
   (equal (helpful--signature 'start-process-shell-command)
          "(start-process-shell-command NAME BUFFER COMMAND)")))

(ert-deftest helpful-function--single-buffer ()
  "Ensure that calling `helpful-buffer' does not leave any extra
buffers lying around."
  (let ((initial-buffers (buffer-list))
        expected-buffers results-buffer)
    (helpful-function #'enable-theme)
    (setq results-buffer (get-buffer "*helpful command: enable-theme*"))
    (setq expected-buffers
          (cons results-buffer
                initial-buffers))
    (should
     (null
      (-difference (buffer-list) expected-buffers)))))

(ert-deftest helpful--kind-name ()
  (should
   (equal
    (helpful--kind-name 'message nil)
    "variable"))
  (should
   (equal
    (helpful--kind-name 'message t)
    "function"))
  (should
   (equal
    (helpful--kind-name 'save-excursion t)
    "special form")))

(ert-deftest helpful--pretty-print ()
  ;; Strings should be formatted with double-quotes.
  (should (equal "\"foo\"" (helpful--pretty-print "foo")))
  ;; Don't crash on large plists using keywords.
  (helpful--pretty-print
   '(:foo foooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo :bar bar)))

(ert-deftest helpful-update-after-killing-buf ()
  "If we originally looked at a variable in a specific buffer,
and that buffer has been killed, handle it gracefully."
  ;; Don't crash if the underlying buffer has been killed.
  (let (helpful-buf)
    (with-temp-buffer
      (helpful-variable 'tab-width)
      (setq helpful-buf (current-buffer)))
    (with-current-buffer helpful-buf
      (helpful-update))))

(ert-deftest helpful--canonical-symbol ()
  (should
   (eq (helpful--canonical-symbol 'not t)
       'null))
  (should
   (eq (helpful--canonical-symbol 'emacs-bzr-version nil)
       'emacs-repository-version)))

(ert-deftest helpful--aliases ()
  (should
   (equal (helpful--aliases 'null t)
          (list 'not)))
  (should
   (equal (helpful--aliases 'emacs-repository-version nil)
          (list 'emacs-bzr-version))))

(defun helpful-fn-in-elc ())

(ert-deftest helpful--elc-only ()
  "Ensure we handle functions where we have the .elc but no .el
file."
  ;; Pretend that we've loaded `helpful-fn-in-elc' from /tmp/foo.elc.
  (let ((load-history (cons '("/tmp/foo.elc" (defun . helpful-fn-in-elc))
                            load-history)))
    ;; This should not error.
    (helpful-function 'helpful-fn-in-elc)))

(ert-deftest helpful--unnamed-func ()
  "Ensure we handle unnamed functions too.

This is important for `helpful-key', where a user may have
associated a lambda with a keybinding."
  (let* ((fun (lambda (x) x))
         (buf (helpful--buffer fun t)))
    ;; There's no name, so just show lambda in the buffer name.
    (should
     (equal (buffer-name buf) "*helpful lambda*"))
    ;; Don't crash when we show the buffer.
    (with-current-buffer buf
      (helpful-update))))

(ert-deftest helpful--keymap-keys--sparse ()
  (let* ((parent-keymap (make-sparse-keymap))
         (keymap (make-sparse-keymap)))
    (set-keymap-parent keymap parent-keymap)
    (define-key parent-keymap (kbd "a") #'forward-char)
    (define-key keymap (kbd "C-c C-M-a") #'backward-char)
    (define-key keymap [remap quoted-insert] #'forward-line)
    (should
     (equal
      (helpful--keymap-keys keymap)
      '(([17] forward-line)
        ([3 27 1] backward-char)
        ([97] forward-char))))))

(defvar helpful--dummy-keymap
  (let ((keymap (make-sparse-keymap)))
    (define-key keymap (kbd "a") #'forward-char)
    keymap))

;; `fset' is necessary for keymaps as prefixes. This is a quirky Emacs
;; API: https://emacs.stackexchange.com/q/28576/304
(fset 'helpful--dummy-keymap helpful--dummy-keymap)

(ert-deftest helpful--keymap-keys--prefix ()
  "Test we flatten keymaps with prefix keys."
  (let* ((keymap (make-sparse-keymap)))
    (define-key keymap (kbd "C-c") 'helpful--dummy-keymap)
    (should
     (equal
      (helpful--keymap-keys keymap)
      '(([3 97] forward-char))))))

(ert-deftest helpful--keymap-keys ()
  (let* ((parent-keymap (make-keymap))
         (keymap (make-keymap)))
    (set-keymap-parent keymap parent-keymap)
    (define-key parent-keymap (kbd "a") #'forward-char)
    (define-key keymap (kbd "C-c C-M-a") #'backward-char)
    (define-key keymap [remap quoted-insert] #'forward-line)
    (should
     (equal
      ;; This order differs from a sparse keymap. We should fix that
      ;; if it makes any difference.
      (helpful--keymap-keys keymap)
      '(([3 27 1] backward-char)
        ([17] forward-line)
        ([97] forward-char))))))

(ert-deftest helpful--source ()
  (let* ((source (helpful--source #'helpful--source t)))
    (should
     (s-starts-with-p "(defun " source))))

(ert-deftest helpful--source--interactively-defined-fn ()
  "We should return the raw sexp for functions where we can't
find the source code."
  (eval '(defun test-foo-defined-interactively () 42))
  (should
   (not
    (null
     (helpful--source #'test-foo-defined-interactively t)))))

(ert-deftest helpful--outer-sexp ()
  ;; If point is in the middle of a form, we should return its position.
  (with-temp-buffer
    (insert "(foo bar baz)")
    (goto-char (point-min))
    (search-forward "b")

    (-let [(pos subforms)
           (helpful--outer-sexp (current-buffer) (point))]
      (should
       (equal pos (point-min)))
      (should
       (equal subforms '(foo bar)))))
  ;; If point is at the beginning of a form, we should still return its position.
  (with-temp-buffer
    (insert "(foo) (bar)")
    (goto-char (point-min))
    (search-forward "b")
    (backward-char 2)

    (-let [(pos subforms)
           (save-excursion
             (helpful--outer-sexp (current-buffer) (point)))]
      (should
       (equal pos (point)))
      (should
       (equal subforms '(bar))))))

(ert-deftest helpful--summary--aliases ()
  ;; exclude the sym itself
  "Ensure we mention that a symbol is an alias."
  (let* ((summary (helpful--summary '-select t)))
    ;; Strip properties to make assertion messages more readable.
    (set-text-properties 0 (1- (length summary)) nil summary)
    (should
     (equal
      summary
      "-select is a function alias for -filter, defined in dash.el."))))

(ert-deftest helpful--bound-p ()
  ;; Functions.
  (should (helpful--bound-p 'message))
  ;; Variables
  (should (helpful--bound-p 'tab-width))
  ;; Unbound.
  (should (not (helpful--bound-p 'this-variable-does-not-exist)))
  ;; For our purposes, we don't consider nil or t to be bound.
  (should (not (helpful--bound-p 'nil)))
  (should (not (helpful--bound-p 't))))
