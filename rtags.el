;; (defun rtags-setup-hooks () (interactive)
;;   (remove-hook 'after-save-hook 'rtags-sync-all-open-files)
;;   (remove-hook 'find-file-hooks 'rtags-sync-all-open-files)
  ;; (add-hook 'after-save-hook 'rtags-sync-all-open-files)
  ;; (add-hook 'find-file-hooks 'rtags-sync-all-open-files)
  ;; )

(defgroup rtags nil
  "Minor mode for rtags."
  :group 'tools
  :prefix "rtags-")

(defcustom rtags-enable t
  "Whether or rtags is enabled"
  :type 'boolean
  :group 'rtags)

(defcustom rtags-edit-hook nil
  "Run before rtags tries to modify a buffer (from rtags-rename)
return t if rtags is allowed to modify this file"
  :group 'rtags
  :type 'hook)

(defun rtags-append-to-list (list element)
  ;; (add-to-list list element t))
  (let ((len (list-length (eval list))))
    (add-to-list list element t)
    (not (= len (list-length (eval list))))))

(defun rtags-log (log)
  (save-excursion
    (set-buffer (get-buffer-create "*RTags Log*"))
    (goto-char (point-max))
    (setq buffer-read-only nil)
    (insert "**********************************\n" log "\n")
    (setq buffer-read-only t)
    )
  )
(defun rtags-rc-internal (&rest args)
  (let ((arguments args)
        (buffer-chain rtags-last-buffer))
    (rtags-append-to-list 'arguments "-D")
    (while buffer-chain
      (if (and (local-variable-p 'rtags-source-buffer buffer-chain)
               (rtags-append-to-list 'arguments (concat "-d" (buffer-local-value 'rtags-source-buffer buffer-chain))))
          (setq buffer-chain (get-file-buffer (buffer-local-value 'rtags-source-buffer buffer-chain)))
        (setq buffer-chain nil)))
    (rtags-log (concat (executable-find "rc") " " (combine-and-quote-strings arguments)))
    (apply #'call-process (executable-find "rc") nil (list t nil) nil arguments)
    (rtags-log (buffer-string))
    (goto-char (point-min))))

(defvar rtags-symbol-history nil)
(defvar rtags-file-history nil)
(defvar last-rtags-update-process nil)
(defun rtags-update ()
  (interactive)
  (if (executable-find "rb")
      (progn
        (if (and last-rtags-update-process (eq (process-status last-rtags-update-process) 'run))
            (kill-process last-rtags-update-process))
        (setq last-rtags-update-process (start-process "rtags-update" nil "rb" "-u"))))
  nil)

(defun rtags-goto-location(location)
  (let (line column)
    (string-match "\\(.*\\):\\([0-9]+\\):\\([0-9]+\\)" location)
;    (message (concat "rtags-goto-location " location (if (match-beginning 1) "yes" "no")))
    (if (match-beginning 1)
        (progn
          (setq line (string-to-int (match-string 2 location)))
          (setq column (string-to-int (match-string 3 location)))
          (find-file (match-string 1 location))
          (message (concat "current " (buffer-file-name (current-buffer))
                           " last " (buffer-file-name rtags-last-buffer)))
          (unless (eq (current-buffer) rtags-last-buffer)
            (progn
              (message "setting shit")
              (setq rtags-source-buffer (buffer-file-name rtags-last-buffer))
              (make-local-variable 'rtags-source-buffer)
              (if (local-variable-p 'rtags-source-buffer)
                  (message "yes")
                (message "no"))
              (message (concat "this is the value " rtags-source-buffer))
              ))
          (goto-char (point-min))
          (forward-line (- line 1))
          (forward-char (- column 1))
          t)
      nil)
    )
  )

(defun rtags-symbol-pos (&optional pos)
  (let ((line (int-to-string (line-number-at-pos pos)))
        (column nil))
    (setq rtags-last-buffer (current-buffer))
    (save-excursion
      (if pos
          (goto-char pos))
      (if (looking-at "[0-9A-Za-z_~#]")
          (progn
            (while (and (> (point) 1) (looking-at "[0-9A-Za-z_~#]"))
              (backward-char))
            (if (not (looking-at "[0-9A-Za-z_~#]"))
                (forward-char))
            (setq column (int-to-string (- (point) (point-at-bol) -1))))))
    (concat (buffer-file-name rtags-last-buffer) ":" line ":" column ":")))


(defun rtags-find-symbol-at-point(&optional pos)
  (interactive)
  (let ((line (int-to-string (line-number-at-pos pos)))
        (column nil))
    (setq rtags-last-buffer (current-buffer))
    (save-excursion
      (if pos
          (goto-char pos))
      (if (looking-at "[0-9A-Za-z_~#]")
          (progn
            (while (and (> (point) 1) (looking-at "[0-9A-Za-z_~#]"))
              (backward-char))
            (if (not (looking-at "[0-9A-Za-z_~#]"))
                (forward-char))
            (setq column (int-to-string (- (point) (point-at-bol) -1))))))
    (with-temp-buffer
      (rtags-rc-internal "--follow-symbol" (concat (buffer-file-name rtags-last-buffer) ":" line ":" column ":"))
      (rtags-goto-location (buffer-string))
      )
    )
  )

(defun rtags-find-references-at-point()
  (interactive)
  (rtags-find-references-at-point-internal "-r")
  )

(defun rtags-find-references ()
  (interactive)
  (unless (rtags-find-references-at-point)
    (rtags-find-references-prompt))
  )

(defun rtags-rename-symbol ()
  (interactive)
  (let (col line len file replacewith prev (modifications 0) (filesopened 0))
    (save-excursion
      (if (looking-at "[0-9A-Za-z_~#]")
          (progn
            (while (and (> (point) 1) (looking-at "[0-9A-Za-z_~#]"))
              (backward-char))
            (if (not (looking-at "[0-9A-Za-z_~#]"))
                (forward-char))
            (setq col (- (point) (point-at-bol) -1))
            (setq line (line-number-at-pos (point)))
            (setq file (buffer-file-name (current-buffer)))
            (let ((tmp (point)))
              (while (looking-at "[0-9A-Za-z_~#]")
                (forward-char))
              (setq prev (buffer-substring tmp (point)))
              (setq len (- (point) tmp)))
            (setq replacewith (read-from-minibuffer (format "Replace '%s' with: " prev)))
            (unless (equal replacewith "")
              (with-temp-buffer
                (rtags-rc-internal "--no-context" "--all-references" (format "%s:%d:%d:" file line col))
                (while (looking-at "^\\(.*\\):\\([0-9]+\\):\\([0-9]+\\):$")
                  (message (buffer-substring (point-at-bol) (point-at-eol)))
                  (message (format "%s %s %s" (match-string 1)
                                   (match-string 2)
                                   (match-string 3)))
                  (let ((fn (match-string 1))
                        (l (string-to-number (match-string 2)))
                        (c (string-to-number (match-string 3)))
                        (buf nil))
                    (setq buf (find-buffer-visiting fn))
                    (unless buf
                      (progn
                        (incf filesopened)
                        (setq buf (find-file-noselect fn))))
                    (if buf
                        (save-excursion
                          (set-buffer buf)
                          (if (run-hook-with-args-until-failure rtags-edit-hook)
                              (progn
                                (incf modifications)
                                (goto-line l)
                                (forward-char (- c 1))
                                ;; (message (format "file %s line %d col %d len %d replacewith %s pos %d" fn l c len replacewith (point)))
                                (kill-forward-chars len)
                                (insert replacewith)
                                ))
                          )))
                  (next-line))
                )))
        (message (format "Opened %d new files and made %d modifications" filesopened modifications))))))

; (get-file-buffer FILENAME)

(defun rtags-complete (string predicate code)
  (let ((completions))
    (with-temp-buffer
      (rtags-rc-internal "-S" "-n" "-l" string)
      (setq 'completions (split-string (buffer-string) "\n" t)))))
      ;; (all-completion string completions))))
      ;; (cond ((eq code nil)
      ;;        (try-completion string completions predicate))
      ;;       ((eq code t)
      ;;        (all-completions string completions predicate))
      ;;       ((eq code 'lambda)
      ;;        (if (intern-soft string completions) t nil))))))

(defun rtags-find-references-at-point-internal(mode)
  (let ((bufname (buffer-file-name))
        (line (int-to-string (line-number-at-pos)))
        (column nil))
    (save-excursion
      (if (looking-at "[0-9A-Za-z_~#]")
          (progn
            (while (and (> (point) 1) (looking-at "[0-9A-Za-z_~#]"))
              (backward-char))
            (if (not (looking-at "[0-9A-Za-z_~#]"))
                (forward-char))
            (setq column (int-to-string (- (point) (point-at-bol) -1))))))
    (if (get-buffer "*RTags-Complete*")
        (kill-buffer "*RTags-Complete*"))
    (setq rtags-last-buffer (current-buffer))
    (switch-to-buffer (generate-new-buffer "*RTags-Complete*"))
    (rtags-rc-internal mode (concat bufname ":" line ":" column ":"))

    (cond ((= (point-min) (point-max)) (rtags-remove-completions-buffer))
          ((= (count-lines (point-min) (point-max)) 1) (rtags-goto-location (buffer-string)))
          (t (progn (goto-char (point-min)) (compilation-mode))))
    (not (= (point-min) (point-max)))
    ))

(defun rtags-find-symbol-internal (p switch)
  (let (tagname prompt input completions)
    (setq tagname (gtags-current-token))
    (setq rtags-last-buffer (current-buffer))
    (if tagname
        (setq prompt (concat p ": (default " tagname ") "))
      (setq prompt (concat p ": ")))
    (with-temp-buffer
      (rtags-rc-internal "-l" "")
      (setq completions (split-string (buffer-string) "\n" t)))
      ;; (setq completions (split-string "test1" "test1()")))
    (setq input (completing-read prompt completions nil nil nil rtags-symbol-history))
    (if (not (equal "" input))
        (setq tagname input))
    (if (get-buffer "*RTags-Complete*")
        (kill-buffer "*RTags-Complete*"))
    (switch-to-buffer (generate-new-buffer "*RTags-Complete*"))
    (rtags-rc-internal switch tagname)
    ;; (call-process (executable-find "rc") nil (list t nil) nil switch tagname)
    (cond ((= (point-min) (point-max)) (rtags-remove-completions-buffer))
          ((= (count-lines (point-min) (point-max)) 1) (rtags-goto-location (buffer-string)))
          (t (progn (goto-char (point-min)) (compilation-mode))))
    (not (= (point-min) (point-max)))
    ))

(defun rtags-find-symbol-prompt ()
  (interactive)
  (rtags-find-symbol-internal "Find symbol" "-s"))

(defun rtags-find-symbol ()
  (interactive)
  (cond ((rtags-find-symbol-at-point) t)
        ((and (string-equal "#include " (buffer-substring (point-at-bol) (+ (point-at-bol) 9)))
              (rtags-find-symbol-at-point (+ (point-at-bol) 1))) t)
        (t (rtags-find-symbol-prompt))
        )
  )

(defun rtags-find-references-prompt ()
  (interactive)
  (rtags-find-symbol-internal "Find references" "-r"))

(defun rtags-complete-files (string predicate code)
  (let ((complete-list (make-vector 63 0)))
    (with-temp-buffer
      ;; (call-process (executable-find "rb") nil (list t nil) nil "-P" string)
      (rtags-rc-internal "-n" "-P" string)
      ;; (call-process (executable-find "rc") nil t nil "-n" "-P" string)
      (goto-char (point-min))
      (let ((match (if (equal "" string) "\./\\(.*\\)" (concat ".*\\(" string ".*\\)"))))
        (while (not (eobp))
          (looking-at match)
          (intern (match-string 1) complete-list)
          (forward-line))))
    (cond ((eq code nil)
           (try-completion string complete-list predicate))
          ((eq code t)
           (all-completions string complete-list predicate))
          ((eq code 'lambda)
           (if (intern-soft string complete-list) t nil)))))

(defun rtags-goto-file()
  (interactive)
  (goto-char (point-min))
  (let ((line (buffer-substring (point-at-bol) (point-at-eol))))
    (message line)
    (if (file-exists-p line)
        (progn
          (kill-buffer (current-buffer))
          (find-file line))
      )
    )
  )

(defvar rtags-last-buffer nil)
(defun rtags-remove-completions-buffer ()
  (interactive)
  (kill-buffer (current-buffer))
  (switch-to-buffer rtags-last-buffer))

(defun rtags-find-files ()
   (interactive)
   (let ((tagname (gtags-current-token))
         (input (completing-read "Find files: " 'rtags-complete-files nil nil nil rtags-file-history)))
     (setq rtags-last-buffer (current-buffer))
     (unless (equal "" input)
       (progn
         (switch-to-buffer (generate-new-buffer "*Completions*"))
         (rtags-rc-internal "-P" input)
         ;; (call-process (executable-find "rc") nil t nil "-P" input)
         (if (= (point-min) (point-max))
             (rtags-remove-completions-buffer)
           (progn
             (if (= (count-lines (point-min) (point-max)) 1)
                 (rtags-goto-file)
               (progn
                 (setq buffer-read-only t)
                 (goto-char (point-min))
                 (local-set-key (kbd "q") 'rtags-remove-completions-buffer)
                 (local-set-key (kbd "RET") 'rtags-goto-file))
               )
             )
           )
         )
       )
     )
   )

(provide 'rtags)
