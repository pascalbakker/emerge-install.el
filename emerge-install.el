;;; emerge-install.el --- Manage Gentoo USE flags via vtable -*- lexical-binding: t; -*-

;; Author: Pascal Bakker
;; Keywords: gentoo, package-management, vtable
;; URL: https://github.com/pascalbakker/emerge-install.el

;;; Commentary:
;; This package provides a visual interface using `vtable' to manage 
;; Gentoo USE flags.  It allows searching for packages via `eix', 
;; toggling flags via `equery', and applying changes to 
;; /etc/portage/package.use via sudo.

;;; Code:

(require 'vtable)
(require 'seq)

(defvar emerge-install-flags nil 
  "Current list of flags for the active package being configured.")

(defvar emerge-install-package-to-install nil 
  "The CPV (category/package-version) currently being configured.")

;; --- Internal Helpers ---

(defun emerge-install--sudo-command (command-to-run)
  "Run COMMAND-TO-RUN with sudo privileges.
Prompts for password and pipes it to sudo -S."
  (shell-command 
   (concat "echo " (shell-quote-argument (read-passwd "Password: ")) 
           " | sudo -S " command-to-run)))

(defun emerge-install--sudo-command-async (command-to-run)
  "Run COMMAND-TO-RUN asynchronously with sudo privileges.
Prompts for password and pipes it to sudo -S."
  (async-shell-command 
   (concat "echo " (shell-quote-argument (read-passwd "Password: ")) 
           " | sudo -S " command-to-run)))

;; --- Buffer UI Logic ---

(defun emerge-install--update-table ()
  "Toggle the USE flag status in the vtable and sync with the flags list.
Only operates if the cursor is on the `U` or `I` columns."
  (interactive)
  (let* ((col (vtable-current-column))
         (obj (vtable-current-object))
         (table (vtable-current-table)))
    (if (and obj (member col '(0 1)))
        (let ((new-val (if (string= (nth col obj) "-") "+" "-")))
          (setf (nth col obj) new-val)
          (vtable-update-object table obj)
          (forward-line))
      (user-error "Move cursor to the U or I column to toggle flags"))))

(defun emerge-install-next-col ()
  "Move point to the next column if in the first column."
  (interactive)
  (when (= (vtable-current-column) 0)
    (vtable-next-column)))

(defun emerge-install-prev-col ()
  "Move point to the previous column if in the second column."
  (interactive)
  (when (= (vtable-current-column) 1)
    (vtable-previous-column)))

;; --- File & String Handling ---

(defun emerge-install--get-target-file ()
  "Determine which file in /etc/portage/package.use/ to modify.
Returns a list (STATUS FILENAME) where STATUS is either `new-file or `update."
  (let* ((pkg emerge-install-package-to-install)
         (pkg-suffix (nth 1 (split-string pkg "/")))
         (grep-cmd (format "grep -rl \"^%s\" /etc/portage/package.use/" pkg))
         (found-files (split-string (shell-command-to-string grep-cmd) "\n" t)))
    (cond
     ((null found-files) 
      (list 'new-file pkg-suffix))
     ((member (concat "/etc/portage/package.use/" pkg-suffix) found-files)
      (list 'update pkg-suffix))
     (t 
      (list 'update (file-name-nondirectory (car found-files)))))))

(defun emerge-install--format-use-line ()
  "Format the package name and enabled flags into a single string for portage."
  (let ((flags (seq-filter (lambda (f) (string= (nth 1 f) "+")) 
                           emerge-install-flags)))
    (format "%s %s" 
            emerge-install-package-to-install
            (mapconcat (lambda (f) (nth 2 f)) flags " "))))

;; --- System Actions ---

(defun emerge-install-execute ()
  "Apply selected USE flag changes to disk and execute `emerge`.
Uses `sed` to update existing lines or `echo` to append new ones."
  (interactive)
  (unless emerge-install-package-to-install
    (user-error "No package selected for installation"))
  (let* ((file-info (emerge-install--get-target-file))
         (status (car file-info))
         (target-path (concat "/etc/portage/package.use/" (nth 1 file-info)))
         (use-line (emerge-install--format-use-line)))
    
    (if (eq status 'update)
        (emerge-install--sudo-command (format "sed -i 's|^%s.*|%s|' %s" 
                                              emerge-install-package-to-install 
                                              use-line 
                                              target-path))
      (emerge-install--sudo-command (format "sh -c 'echo %s >> %s'" 
                                            (shell-quote-argument use-line) 
                                            (shell-quote-argument target-path))))
    
    (emerge-install--sudo-command-async (format "emerge %s" emerge-install-package-to-install))))

;; --- Core Setup ---

(defvar emerge-install-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "l") 'emerge-install-next-col)
    (define-key map (kbd "h") 'emerge-install-prev-col)
    (define-key map (kbd "RET") 'emerge-install--update-table)
    (define-key map (kbd "C-c C-c") 'emerge-install-execute)
    map)
  "Keymap for `emerge-install-mode'.")

(define-minor-mode emerge-install-mode
  "Minor mode for interacting with emerge USE flags.
Provides keybindings for navigating and toggling flags in a vtable."
  :lighter " Emerge-Install"
  :keymap emerge-install-mode-map)

(defun emerge-install--parse-equery (output)
  "Split the raw equery OUTPUT into a list of flag objects."
  (mapcar (lambda (line) (split-string line "|" t))
          (split-string output "\n" t)))

;;;###autoload
(defun emerge-install-package (package)
  "Search for PACKAGE via eix and open a flag configuration buffer."
  (interactive "sSearch for package (eix): ")
  (let* ((eix-cmd (format "eix %s | sed -n 's/^\\*[ ]*\\([a-zA-Z0-9\\/-]*\\).*/\\1/p'" package))
         (options (split-string (shell-command-to-string eix-cmd) "\n" t)))
    (if (null options)
        (message "No package found for: %s" package)
      (let* ((selection (completing-read "Select package: " options))
             (equery-cmd (format "script -q -c \"equery --no-color u %s\" /dev/null | sed -n 's/^[[:space:]]*\\([+-]\\)[[:space:]]*\\([+-]\\)[[:space:]]*\\([^[:space:]:]*\\)[[:space:]]*:[[:space:]]*\\(.*\\)/\\1|\\2|\\3|\\4/p'" selection))
             (flag-data (emerge-install--parse-equery (shell-command-to-string equery-cmd))))
        
        (with-current-buffer (get-buffer-create "*Gentoo-Install*")
          (let ((inhibit-read-only t))
            (erase-buffer)
            (setq emerge-install-flags flag-data)
            (setq emerge-install-package-to-install selection)
            (make-vtable :columns '("U" "I" "Flag" "Description") :objects flag-data)
            (setq header-line-format "RET: Toggle | C-c C-c: Install | h/l: Nav Columns")
            (emerge-install-mode 1)
            (read-only-mode 1)
            (hl-line-mode 1)
            (display-buffer (current-buffer))))))))

(provide 'emerge-install)

;;; emerge-install.el ends here
