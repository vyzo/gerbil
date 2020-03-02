;;; gerbil.el --- Gerbil mode -*- lexical-binding: t; -*-
;;
;; Copyright (c) 2007-2019 Dimitris Vyzovitis & Contributors
;;
;; Author: Dimitris Vyzovitis <vyzo@hackzen.org>
;; URL: https://github.com/vyzo/gerbil
;; Version: 1.0
;; Keywords: gerbil major-mode
;;
;; This file is not part of GNU Emacs.
;;
;; This program is free software: you can redistribute it and/or modify it
;; under the terms of the GNU Lesser General Public License as published by
;; the Free Software Foundation, either version 2.1 of the License, or (at
;; your option) any later version; and the Apache License, Version 2.0 (the
;; "License"), as published by the Apache Sofware Fundation (ASF).
;;
;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU Lesser
;; General Public License for more details.
;;
;; You should have received a copy of the GNU Lesser General Public License
;; and the Apache License along with this program. If not, see
;; <https://www.gnu.org/licenses/> and
;; <https://www.apache.org/licenses/LICENSE-2.0>.
;;
;; Unless required by applicable law or agreed to in writing, software
;; distributed under the License is distributed on an "AS IS" BASIS,
;; WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
;; See the License for the specific language governing permissions and
;; limitations under the License.

;;; Commentary:
;;
;; This package provides a Gerbil major mode for Emacs. It extends
;; scheme-mode with font-lock, indentation, runs gxi on an inferior scheme
;; shell, and defines the following keybindings:
;;
;; * Compile the current buffer: `C-c C-f'
;;
;; * Import the current buffer: `C-c C-i'
;;
;; * Reload the current buffer: `C-c C-r'
;;
;; * Build the current project: `C-c C-b'
;;
;; * Send and evaluate the selected region to gxi: `C-c C-e'
;;
;; * Send the selected region to gxi: `C-c C-c'
;;
;; * Restart Scheme: `C-x 9' (also works in gxi)

;;; Code:

(require 'scheme)
(require 'cmuscheme)

(defgroup gerbil-mode nil
  "Editing Gerbil code"
  :prefix "gerbil-mode-"
  :group 'scheme)

;; Redefine the function scheme-send-region from `cmuscheme' so
;; that we can keep track of all text sent to Gambit's stdin.
;; By Christopher Eames (Chream) <chream-gmx.com> 2018.

(defun scheme-send-region (start end)
  "Send the current region to the inferior Scheme process."
  (interactive "r")
  (scheme-send-string (buffer-substring start end)))

(defun scheme-send-string (str)
  "Send a string to the inferior Scheme process."
  (gerbil-send-string str))

(defun gerbil-message (string)
  (message (concat "Gerbil-info : SENT=" string " ...")))

(defun gerbil-send-string (string)
  (let ((string (concat string "\n")))
    (comint-check-source string)
    (comint-send-string (scheme-proc) string)
    (gerbil-message (seq-subseq string 0 (string-match "\n" string)))))

;; -------

;; fare's erlang style restart
(defun restart-scheme ()
  (interactive)
  (let ((process (scheme-get-process)))
    (when process
      (ignore-errors
        (switch-to-buffer "*scheme*")
        (comint-clear-buffer))
      (ignore-errors (kill-process process))
      (sleep-for 1))) ;; <-- poor man's substitute for waitpid(), with a race condition
  ;; TODO: elisp doesn't have a synchronous waitpid, so instead we should implement an asynchronous one,
  ;; using callbacks: use (set-process-sentinel PROCESS SENTINEL) to watch for the death of the process;
  ;; and while we're at it, also set a timer and use kill -9 < https://youtu.be/Fow7iUaKrq4 >
  ;; if the process failed to die after one second or two.
  (switch-to-buffer "*scheme*")
  (run-scheme scheme-program-name)
  (ignore-errors (comint-clear-buffer))
  (message "Happy Happy Joy Joy")
  nil)

;; this is bound to C-x 9 below

;; -------

(defun gerbil-import-file (fname)
  (let ((string (concat "(import \"" fname "\")\n")))
    (comint-check-source fname)
    (comint-send-string
     (scheme-proc)
     string)
    (gerbil-message string)))

(defun gerbil-reload-file (fname)
  (let ((string (concat "(reload \"" fname "\")\n")))
    (comint-check-source fname)
    (comint-send-string
     (scheme-proc)
     string)
    (gerbil-message string)))

(defun gerbil-import-current-buffer ()
  (interactive)
  (gerbil-import-file buffer-file-name))

(defun gerbil-reload-current-buffer ()
  (interactive)
  (gerbil-reload-file buffer-file-name))

(defvar gerbil-compile-optimize t)
(defvar gerbil-build-directory nil)
(defvar gerbil-compiler-name "gxc")

(defun gerbil-compile-current-buffer ()
  (interactive)
  (let* ((fname buffer-file-name)
         (buf (get-buffer-create "*gerbil-compile*"))
         (cmd-text (concat "> gxc " (if gerbil-compile-optimize "-O " "") fname "\n")))
    (with-current-buffer buf
      (goto-char (point-max))
      (insert cmd-text))
    (message cmd-text)
    (setq gerbil-build-directory nil)
    (let ((proc
           (apply 'start-process gerbil-compiler-name buf
                  gerbil-compiler-name
                  (append (if gerbil-compile-optimize '("-O") '())
                          (list fname)))))
      (set-process-sentinel proc 'gerbil-compile-sentinel)
      (display-buffer buf))))

(defun gerbil-build ()
  (interactive)
  (let* ((dir (file-name-directory buffer-file-name))
         (build (gerbil-find-build-script dir))
         (build-dir (file-name-directory build))
         (build-script (file-name-nondirectory build))
         (buf (get-buffer-create "*gerbil-compile*")))
    (with-current-buffer buf
      (goto-char (point-max))
      (insert "> build " build "\n"))
    (setq gerbil-build-directory build-dir)
    (let ((proc (start-process "build" buf "sh" "-c"
                               (concat "cd " build-dir " && ./" build-script))))
      (set-process-sentinel proc 'gerbil-compile-sentinel)
      (display-buffer buf))))

(defun gerbil-find-build-script (dir)
  (let ((files (directory-files dir nil "^build.ss$")))
    (cond
     (files
      (concat dir (car files)))
     ((equal dir "/")
      (error "Cannot locate build script"))
     (t
      (let ((dir (file-name-directory (directory-file-name dir))))
        (gerbil-find-build-script dir))))))

(defvar gerbil-compile-mark-rx
  "^> \\(gxc\\|build\\)")
(defvar gerbil-error-locat-rx
  "\\(\\\"\\(\\\\\\\\\\|\\\\\"\\|[^\\\"\n]\\)+\\\"\\)@\\([0-9]+\\)\\.\\([0-9]+\\)[^0-9]")

(defun gerbil-compile-sentinel (proc evt)
  (let ((buf (process-buffer proc)))
    (when buf
      (cond
       ((equal evt "finished\n")
        (kill-buffer buf))
       ((or (string-prefix-p "exited" evt)
            (string-prefix-p "failed" evt))
        (with-current-buffer buf
          (goto-char (point-max))
          (when (re-search-backward gerbil-compile-mark-rx nil t)
            (let ((limit (point)))
              (goto-char (point-max))
              (when (re-search-backward gerbil-error-locat-rx limit t)
                (let* ((loc (gerbil-extract-locat (buffer-substring (point) (point-max))))
                       (fname (if gerbil-build-directory
                                  (concat gerbil-build-directory (car loc))
                                (car loc))))
                  (find-file fname)
                  (goto-char (point-min))
                  (forward-line (1- (cadr loc)))
                  (forward-char (- (caddr loc) 1))
                  (mark-sexp)))))))
       (t
        (with-current-buffer buf
          (goto-char (point-max))
          (insert "\nProcess " evt)))))))

(defun gerbil-extract-locat (str)
  (and (string-match gerbil-error-locat-rx str)
       (let* ((name (substring str
                               (match-beginning 1)
                               (match-end 1)))
              (line (substring str
                               (match-beginning 3)
                               (match-end 3)))
              (col (substring str
                              (match-beginning 4)
                              (match-end 4))))
         (list (read name) (read line) (read col)))))

(defun gerbil-put (syms prop v)
  (dolist (x syms)
    (put x prop v)))

(defun gerbil-put-indent (syms v)
  (gerbil-put syms 'scheme-indent-function v))

(defun gerbil-fontlock-add (x)
  (font-lock-add-keywords nil (list x) t))

(defun gerbil-init-keywords ()
  (interactive)
  (gerbil-put '(import export declare include
                or and
                case-lambda
                call/cc call/values
                begin-syntax
                begin-foreign
                cond-expand
                for-each map foldl foldr
                unwind-protect
                )
              'scheme-indent-function 0)

  (gerbil-put '(if when unless
                set!
                begin-annotation begin0
                datum->syntax syntax/loc
                core-match core-wrap
                with-syntax with-syntax*
                ast-rules
                with-ast with-ast*
                apply
                let-values letrec-values letrec*-values
                module
                syntax-parameterize
                rec alet alet*
                let-syntax letrec-syntax
                parameterize parameterize*
                error raise-syntax-error raise-type-error
                catch guard
                match match*
                with with*
                let/cc let/esc
                lambda%
                identifier-rules
                letrec*
                while
                let-hash
                for for* for/collect
                begin-ffi
                )
              'scheme-indent-function 1)
  (gerbil-put '(syntax-case ast-case core-syntax-case core-ast-case
                do-while
                for/fold
                 )
              'scheme-indent-function 2)
  (gerbil-put '(def defvalues def/c def*/c extern
                defalias defsyntax defrule defrules defrules*
                defstruct defclass defgeneric defmethod
                definline definline*
                define-values define-syntaxes
                )
              'scheme-indent-function 'defun)
  )

(defun gerbil-init-fontlock ()
  (interactive)
  (gerbil-fontlock-add
   (cons
    (concat
     "(" (regexp-opt '("import" "export" "declare" "include"
                       "module" "extern" "cond-expand" "require" "provide"
                       "if" "apply" "eval" "set!"
                       "when" "unless" "not"
                       "case-lambda"
                       "core-syntax-case" "core-ast-case"
                       "syntax-case" "ast-case" "ast-rules"
                       "identifier-rules"
                       "core-match"
                       "with-syntax" "with-syntax*"
                       "with-ast" "with-ast*"
                       "call/cc" "call/values"
                       "begin-syntax" "begin-annotation" "begin0"
                       "let-values" "letrec-values" "letrec*-values"
                       "letrec*" "rec"
                       "quote" "quasiquote" "unquote" "unquote-splicing"
                       "parameterize" "syntax-parameterize"
                       "quote-syntax"
                       "syntax" "quasisyntax" "unsyntax" "unsyntax-splicing"
                       "syntax/loc"
                       "define-values" "define-alias"
                       "alet" "alet*"
                       "error" "raise"
                       "let/cc" "let/esc"
                       "unwind-protect"
                       "begin-foreign" "begin-ffi"
                       "cut"
                       "with" "with*"
                       "match" "match*"
                       "sync" "wait"
                       "foldl" "foldr" "andmap" "ormap"
                       "type-of"
                       "spawn" "spawn*" "spawn/name" "spawn/group"
                       ;; sugar
                       "try" "finally" "catch"
                       "while" "until" "using"
                       "hash" "hash-eq" "hash-eqv" "let-hash"
                       ;; coroutines
                       "continue" "yield" "coroutine"
                       ;; iterators
                       "for" "for*" "for/collect" "for/fold"
                       ;; actor messaging
                       "<-" "<<" "->"
                       )
                     t)
     "\\>")
    1))
  (gerbil-fontlock-add
   '("\\(XXX\\|TODO\\)"
     (1 font-lock-warning-face)))
  (gerbil-fontlock-add
   '("\\_<\\(values\\)\\_>"
     (1 font-lock-keyword-face)))
  (gerbil-fontlock-add
   '("\\_<\\(\\sw+:\\)\\_>"
     (1 font-lock-builtin-face)))

  (gerbil-fontlock-add
   '("\\<\\(<>\\|<\\.\\.\\.>\\>\\)"
     (1 font-lock-builtin-face)))

  (gerbil-fontlock-add
   '("\\_<\\([.][.][.]\\)"
     (1 font-lock-builtin-face)))
  (gerbil-fontlock-add
   '("\\_<\\(=>\\)"
     (1 font-lock-builtin-face)))
  (gerbil-fontlock-add
   '("\\(#?[`',]\\)"
     (1 font-lock-keyword-face)))
  (gerbil-fontlock-add
   '("\\(#?,@\\)"
     (1 font-lock-keyword-face)))

  (gerbil-fontlock-add
   '("\\(%#\\w+\\)"
     (1 font-lock-builtin-face)))
  (gerbil-fontlock-add
   '("\\_<\\(:\\sw+\\)\\_>"
     (1 font-lock-variable-name-face)))
  (gerbil-fontlock-add
   '("(\\(@\\)"
     (1 font-lock-variable-name-face)))
  (gerbil-fontlock-add
   '("(\\(def\\)\\s-+(?\\(\\sw+\\)"
     (1 font-lock-keyword-face)
     (2 font-lock-function-name-face)))
  (gerbil-fontlock-add
   '("(\\(def\\)\\s-+\\(\\sw+\\)"
     (1 font-lock-keyword-face)
     (2 font-lock-function-name-face)))
  (gerbil-fontlock-add
   '("(\\(def[*]\\)\\s-+(*\\(\\sw+\\)"
     (1 font-lock-keyword-face)
     (2 font-lock-function-name-face)))
  (gerbil-fontlock-add
   '("(\\(defvalues\\)\\s-+(\\([^()]*\\))"
     (1 font-lock-keyword-face)
     (2 font-lock-function-name-face)))
  (gerbil-fontlock-add
   '("(\\(definline[*]?\\)\\s-+(?\\(\\sw+\\)"
     (1 font-lock-keyword-face)
     (2 font-lock-function-name-face)))
  (gerbil-fontlock-add
   '("(\\(def/c\\)\\s-+(\\(\\sw+\\)"
     (1 font-lock-keyword-face)
     (2 font-lock-function-name-face)))
  (gerbil-fontlock-add
   '("(\\(def[*]/c\\)\\s-+\\(\\sw+\\)"
     (1 font-lock-keyword-face)
     (2 font-lock-function-name-face)))
  (gerbil-fontlock-add
   '("(\\(defsyntax\\)\\s-+(?\\(\\sw+\\)"
     (1 font-lock-keyword-face)
     (2 font-lock-variable-name-face)))
  (gerbil-fontlock-add
   '("(\\(defsyntax-\\sw+\\)\\s-+(?\\(\\sw+\\)"
     (1 font-lock-keyword-face)
     (2 font-lock-variable-name-face)))
  (gerbil-fontlock-add
   '("(\\(defrule\\)\\s-+(\\(\\sw+\\)"
     (1 font-lock-keyword-face)
     (2 font-lock-variable-name-face)))
  (gerbil-fontlock-add
   '("(\\(defrules\\|defalias\\|module\\)\\s-+\\(\\sw+\\)"
     (1 font-lock-keyword-face)
     (2 font-lock-variable-name-face)))
  (gerbil-fontlock-add
   '("(\\(defun\\|deflabel\\)\\s-+\\(\\sw+\\)"
     (1 font-lock-keyword-face)
     (2 font-lock-function-name-face)))
  (gerbil-fontlock-add
   '("(\\(defasm\\|deftemplate\\)\\s-+\\(\\sw+\\)"
     (1 font-lock-keyword-face)
     (2 font-lock-variable-name-face)))
  (gerbil-fontlock-add
   '("(\\(deftype\\)\\s-+(?\\(\\sw+\\)"
     (1 font-lock-keyword-face)
     (2 font-lock-type-face)))
  (gerbil-fontlock-add
   '("(\\(def\\sw+-rules\\)\\s-+(?\\(\\sw+\\)"
     (1 font-lock-keyword-face)
     (2 font-lock-variable-name-face)))
  (gerbil-fontlock-add
   '("(\\(defstruct\\|defclass\\|class\\|struct\\|interface\\|union\\)\\s-+(?\\(\\sw+\\)"
     (1 font-lock-keyword-face)
     (2 font-lock-type-face)))
  (gerbil-fontlock-add
   '("(\\(defstruct-type\\|defclass-type\\)\\s-+\\(\\sw+\\)"
     (1 font-lock-keyword-face)
     (2 font-lock-type-face)))
  (gerbil-fontlock-add
   '("(\\(defgeneric\\|defmethod[*]?\\)\\s-+[{(]?\\(\\sw+\\)"
     (1 font-lock-keyword-face)
     (2 font-lock-function-name-face)))
  (gerbil-fontlock-add
   '("(\\(defproto\\)\\s-+\\(\\sw+\\)"
     (1 font-lock-keyword-face)
     (2 font-lock-type-face)))
  (gerbil-fontlock-add
   '("(\\(defregister\\|defvar\\|defconst\\)\\s-+\\(\\sw+\\)"
     (1 font-lock-keyword-face)
     (2 font-lock-variable-name-face)))

  (gerbil-fontlock-add
   '("\\_<\\([?!&]+\\)"
     (1 font-lock-builtin-face)))
  (gerbil-fontlock-add
   '("\\<\\(#[tf]\\|#!\\w+\\)"
     (1 font-lock-builtin-face)))
  (gerbil-fontlock-add
   '("\\([_#]+\\)"
     (1 font-lock-builtin-face)))

  (gerbil-fontlock-add
   '("\\([{}]\\|\\[\\|\\]\\)"
     (1 font-lock-variable-name-face)))
  )

(defun gerbil-pretty-lambdas ()
  (interactive)
  (gerbil-fontlock-add
   `("\\(lambda\\)"
     (0 (progn
          (compose-region (match-beginning 1) (match-end 1)
                          ,(make-char 'greek-iso8859-7 107))
          nil)))))

(defun gerbil-init ()
  (interactive)
  (gerbil-init-keywords)
  (gerbil-init-fontlock)
  (when window-system
    (gerbil-pretty-lambdas)))

(define-key scheme-mode-map (kbd "C-x 9") 'restart-scheme)
(define-key inferior-scheme-mode-map (kbd "C-x 9") 'restart-scheme)

(defvar gerbil-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map scheme-mode-map)
    (define-key map (kbd "C-c C-f") 'gerbil-compile-current-buffer)
    (define-key map (kbd "C-c C-i") 'gerbil-import-current-buffer)
    (define-key map (kbd "C-c C-r") 'gerbil-reload-current-buffer)
    (define-key map (kbd "C-c C-b") 'gerbil-build)
    (define-key map (kbd "C-c C-e") 'scheme-send-definition)
    (define-key map (kbd "C-c C-c") 'scheme-send-region)
    map))

(defvar gerbil-program-name "gxi")
(defvar gerbil-mode-hook nil)

;;;###autoload
(define-derived-mode gerbil-mode scheme-mode
  "Gerbil" "Major mode for Gerbil."
  (kill-all-local-variables)
  (use-local-map gerbil-mode-map)
  (setq mode-name "Gerbil")
  (setq scheme-program-name gerbil-program-name)
  (setq comment-start ";;")
  (scheme-mode-variables)
  (gerbil-init)
  (run-hooks 'gerbil-mode-hook))

;;;###autoload
(progn
  (add-to-list 'auto-mode-alist '("\\.ss\\'" . gerbil-mode))
  (modify-coding-system-alist 'file "\\.ss\\'"  'utf-8))


(provide 'gerbil)

;;; gerbil.el ends here
