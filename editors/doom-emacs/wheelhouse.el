;;; wheelhouse.el --- Wheelhouse: Gas Town Redux Multi-Agent Orchestrator -*- lexical-binding: t; -*-

;;; Commentary:
;; An implementation of Steve Yegge's Wheelhouse / Gas Town Redux paradigm
;; for Doom Emacs. Coordinates autonomous AI agent fleets (agy & claude)
;; across isolated Git worktrees with an Org-Mode task graph ("Beads")
;; and Magit-powered Refinery merge queues.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'json)
(require 'org)
(require 'projectile)
(require 'vterm)
(require 'magit)

(defgroup wheelhouse nil
  "Wheelhouse: Gas Town Redux AI agent orchestrator."
  :group 'tools
  :prefix "wheelhouse-")

(defcustom wheelhouse-default-backend 'agy
  "Default AI backend for worker agents. Either 'agy or 'claude."
  :type '(choice (const :tag "Antigravity CLI (agy)" agy)
                 (const :tag "Claude Code (claude)" claude))
  :group 'wheelhouse)

(defcustom wheelhouse-worktree-dir ".worktrees"
  "Directory (relative to project root) where agent worktrees are placed."
  :type 'string
  :group 'wheelhouse)

(defcustom wheelhouse-beads-file "beads.org"
  "Default beads file name located in project root."
  :type 'string
  :group 'wheelhouse)

(defcustom wheelhouse-agy-executable (or (executable-find "agy") (expand-file-name "~/.local/bin/agy"))
  "Path to the agy executable."
  :type 'string
  :group 'wheelhouse)

(defcustom wheelhouse-claude-executable (or (executable-find "claude") (expand-file-name "~/.local/bin/claude"))
  "Path to the claude executable."
  :type 'string
  :group 'wheelhouse)

(defcustom wheelhouse-copy-env-files '(".env" ".env.local" ".env.development" ".env.test")
  "List of environment files to copy from project root into new worktrees if they exist."
  :type '(repeat string)
  :group 'wheelhouse)

;; =============================================================================
;; Helper Utilities
;; =============================================================================

(defun wheelhouse--project-root ()
  "Return root directory of the current project."
  (or (projectile-project-root)
      (vc-root-dir)
      default-directory))

(defun wheelhouse--slugify (text)
  "Convert TEXT into a sanitized kebab-case slug.
TEXT may be nil, in which case the empty slug is returned."
  (let* ((lower (downcase (or text "")))
         (clean (replace-regexp-in-string "[^a-z0-9]+" "-" lower)))
    (replace-regexp-in-string "^-\\|-$" "" clean)))

(defun wheelhouse--extract-prompt-at-point ()
  "Extract the prompt body or source block from the current Org entry."
  (save-excursion
    (org-back-to-heading t)
    (let ((end (save-excursion (outline-next-heading) (point)))
          (prompt nil))
      ;; Check for #+begin_src markdown or #+begin_src prompt blocks first
      (if (re-search-forward "#\\+begin_src\\(?:[ ]+\\(?:markdown\\|prompt\\|text\\)\\)?[ \t]*\n\\(\\(?:.\\|\n\\)*?\\)#\\+end_src" end t)
          (setq prompt (match-string 1))
        ;; Otherwise use entry body text (ignoring drawers)
        (let ((body (buffer-substring-no-properties (point) end)))
          ;; Strip properties drawer and logbook
          (setq body (replace-regexp-in-string ":PROPERTIES:\\(?:.\\|\n\\)*?:END:\n?" "" body))
          (setq body (replace-regexp-in-string ":LOGBOOK:\\(?:.\\|\n\\)*?:END:\n?" "" body))
          (setq body (string-trim body))
          (when (not (string-empty-p body))
            (setq prompt body))))
      prompt)))

(defun wheelhouse--extract-bead-info ()
  "Extract Bead metadata from Org headline at point."
  (unless (derived-mode-p 'org-mode)
    (user-error "Current buffer is not in org-mode"))
  (when (org-before-first-heading-p)
    (user-error "Point is above the first headline; move onto a Bead headline first"))
  (let* ((headline (org-get-heading t t t t))
         (id (or (org-entry-get nil "ID")
                 (let ((slug (wheelhouse--slugify headline)))
                   (and (not (string-empty-p slug)) slug))
                 (user-error "Cannot derive a Bead ID here; give the headline an :ID: property")))
         (branch (or (org-entry-get nil "BRANCH")
                     (format "bead-%s" (wheelhouse--slugify id))))
         (backend-prop (org-entry-get nil "BACKEND"))
         (backend (if backend-prop (intern (downcase backend-prop)) wheelhouse-default-backend))
         (autopilot-prop (org-entry-get nil "AUTOPILOT"))
         (autopilot (and autopilot-prop (member (downcase autopilot-prop) '("t" "true" "yes" "1" "auto"))))
         (prompt (wheelhouse--extract-prompt-at-point)))
    (list :id id
          :headline headline
          :branch branch
          :backend backend
          :autopilot (not (null autopilot))
          :prompt prompt)))

(defun wheelhouse--sync-env-files (source-dir target-dir)
  "Copy environment configuration files from SOURCE-DIR into TARGET-DIR."
  (dolist (f wheelhouse-copy-env-files)
    (let ((src (expand-file-name f source-dir))
          (dest (expand-file-name f target-dir)))
      (when (and (file-exists-p src) (not (file-exists-p dest)))
        (copy-file src dest t t)
        (message "[Wheelhouse] Synced %s to %s" f target-dir)))))

;; =============================================================================
;; Worktree Lifecycle
;; =============================================================================

(defun wheelhouse-create-worktree (bead-id branch)
  "Create an isolated git worktree for BEAD-ID on BRANCH.
Returns the absolute path to the created worktree."
  (let* ((proj-root (wheelhouse--project-root))
         (wt-parent (expand-file-name wheelhouse-worktree-dir proj-root))
         (wt-dir (expand-file-name bead-id wt-parent)))
    (unless (file-directory-p wt-parent)
      (make-directory wt-parent t))
    (if (file-directory-p wt-dir)
        (message "[Wheelhouse] Worktree directory %s already exists." wt-dir)
      (let* ((default-directory proj-root)
             (branch-exists (zerop (call-process "git" nil nil nil "rev-parse" "--verify" branch)))
             (git-args (if branch-exists
                           (list "worktree" "add" wt-dir branch)
                         (list "worktree" "add" "-b" branch wt-dir "HEAD"))))
        (message "[Wheelhouse] Creating worktree for branch '%s'..." branch)
        (apply #'process-file "git" nil nil nil git-args)
        (wheelhouse--sync-env-files proj-root wt-dir)))
    wt-dir))

;; =============================================================================
;; Worker Agent Spawner (VTerm)
;; =============================================================================

(defun wheelhouse--buffer-name (backend bead-id)
  "Generate buffer name for worker running BACKEND on BEAD-ID."
  (format "*wheelhouse:%s:%s*" (symbol-name backend) bead-id))

(defun wheelhouse-spawn-worker (bead-id backend &optional initial-prompt autopilot)
  "Spawn an interactive worker agent in vterm inside the worktree for BEAD-ID.
BACKEND is 'agy or 'claude.
INITIAL-PROMPT is passed to the agent if non-nil.
AUTOPILOT enables auto-confirmation flags if t."
  (let* ((proj-root (wheelhouse--project-root))
         (wt-dir (expand-file-name (format "%s/%s" wheelhouse-worktree-dir bead-id) proj-root))
         (buf-name (wheelhouse--buffer-name backend bead-id)))
    (unless (file-directory-p wt-dir)
      (user-error "Worktree %s does not exist. Run wheelhouse-create-worktree first" wt-dir))
    
    (let ((buf (get-buffer buf-name)))
      (if (and buf (buffer-live-p buf))
          (progn
            (pop-to-buffer buf)
            (message "[Wheelhouse] Switched to existing worker buffer %s" buf-name))
        ;; Create new vterm buffer in worktree directory
        (let ((default-directory wt-dir))
          (setq buf (vterm buf-name))
          (with-current-buffer buf
            ;; Assemble CLI command
            (let* ((exe (if (eq backend 'claude)
                            wheelhouse-claude-executable
                          wheelhouse-agy-executable))
                   (auto-flag (when autopilot "--dangerously-skip-permissions"))
                   (cmd (cond
                         ((eq backend 'claude)
                          (if initial-prompt
                              (format "%s %s %s"
                                      (shell-quote-argument exe)
                                      (if auto-flag auto-flag "")
                                      (shell-quote-argument initial-prompt))
                            (format "%s %s" (shell-quote-argument exe) (if auto-flag auto-flag ""))))
                         ((eq backend 'agy)
                          (if initial-prompt
                              (format "%s %s -i %s"
                                      (shell-quote-argument exe)
                                      (if auto-flag auto-flag "")
                                      (shell-quote-argument initial-prompt))
                            (format "%s %s" (shell-quote-argument exe) (if auto-flag auto-flag "")))))))
              (vterm-send-string (concat cmd "\n"))))
          (pop-to-buffer buf)
          (message "[Wheelhouse] %s worker launched in %s for %s" backend wt-dir bead-id))))))

;; =============================================================================
;; Interactive Dispatch Commands
;; =============================================================================

;;;###autoload
(defun wheelhouse-dispatch-bead (&optional backend)
  "Dispatch current Org headline Bead to an isolated worktree & worker agent.
If BACKEND is not specified, prompts the user (defaulting to `wheelhouse-default-backend`)."
  (interactive)
  (let* ((info (wheelhouse--extract-bead-info))
         (bead-id (plist-get info :id))
         (branch (plist-get info :branch))
         (chosen-backend (or backend
                             (let ((choice (completing-read
                                            (format "Select AI Backend for [%s] (default: %s): "
                                                    bead-id wheelhouse-default-backend)
                                            '("agy" "claude") nil t nil nil
                                            (symbol-name wheelhouse-default-backend))))
                               (intern choice))))
         (autopilot (plist-get info :autopilot))
         (prompt (plist-get info :prompt)))
    
    ;; 1. Update Org Bead Metadata
    (org-entry-put nil "ID" bead-id)
    (org-entry-put nil "BRANCH" branch)
    (org-entry-put nil "BACKEND" (symbol-name chosen-backend))
    (org-entry-put nil "WORKTREE" (format "%s/%s" wheelhouse-worktree-dir bead-id))
    (org-entry-put nil "DISPATCHED_AT" (format-time-string "[%Y-%m-%d %a %H:%M]"))
    (org-todo "DISPATCHED")
    (save-buffer)
    
    ;; 2. Create Git Worktree
    (wheelhouse-create-worktree bead-id branch)
    
    ;; 3. Spawn Worker Agent in VTerm
    (wheelhouse-spawn-worker bead-id chosen-backend prompt autopilot)))

;;;###autoload
(defun wheelhouse-dispatch-agy ()
  "Dispatch current Org Bead headline directly with Antigravity CLI (agy)."
  (interactive)
  (wheelhouse-dispatch-bead 'agy))

;;;###autoload
(defun wheelhouse-dispatch-claude ()
  "Dispatch current Org Bead headline directly with Claude Code (claude)."
  (interactive)
  (wheelhouse-dispatch-bead 'claude))

;; =============================================================================
;; Fleet Manager & Buffer Navigation
;; =============================================================================

(defun wheelhouse--list-active-workers ()
  "Return a list of all active wheelhouse worker buffers."
  (cl-remove-if-not
   (lambda (buf)
     (string-match-p "^\\*wheelhouse:\\(agy\\|claude\\):.+?\\*$" (buffer-name buf)))
   (buffer-list)))

(defun wheelhouse--tile-buffers (buffers)
  "Tile a list of BUFFERS across the current frame in a balanced grid."
  (delete-other-windows)
  (when buffers
    (let* ((n (length buffers))
           (cols (if (<= n 2) n 2))
           (first-win (selected-window)))
      (set-window-buffer first-win (car buffers))
      (if (= n 1)
          (select-window first-win)
        (let ((wins (list first-win)))
          ;; Split into columns
          (dotimes (_ (1- cols))
            (push (split-window-right) wins))
          (setq wins (nreverse wins))
          ;; Split rows if more than 2
          (when (> n cols)
            (let ((extra-wins '()))
              (dotimes (i (- n cols))
                (let ((target-win (nth (mod i cols) wins)))
                  (select-window target-win)
                  (push (split-window-below) extra-wins)))
              (setq wins (append wins (nreverse extra-wins)))))
          ;; Assign buffers to windows
          (cl-loop for win in wins
                   for buf in buffers
                   do (set-window-buffer win buf))
          (balance-windows)
          (select-window (car wins)))))))

;;;###autoload
(defun wheelhouse-multiagent-view ()
  "Open the Multiagent View dashboard showing all active AI workers in a split grid.
If Doom workspaces are active, opens or switches to the 'Wheelhouse' workspace."
  (interactive)
  (let ((workers (wheelhouse--list-active-workers)))
    ;; Switch to or create dedicated workspace if persp/workspaces module is active
    (when (and (bound-and-true-p persp-mode) (fboundp '+workspace-switch))
      (+workspace-switch "*wheelhouse*" t))
    
    (if (null workers)
        (progn
          (delete-other-windows)
          (wheelhouse-open-beads-file)
          (message "[Wheelhouse] No active workers running. Opened task graph (beads.org). Press SPC o w d to dispatch!"))
      (if (= (length workers) 1)
          (let ((worker-buf (car workers)))
            (delete-other-windows)
            (wheelhouse-open-beads-file)
            (let ((w-win (split-window-right)))
              (set-window-buffer w-win worker-buf)
              (select-window w-win))
            (balance-windows))
        (wheelhouse--tile-buffers workers))
      (message "[Wheelhouse] Displaying %d active worker agent(s)" (length workers)))))

;;;###autoload
(defun wheelhouse-fleet ()
  "Display active Wheelhouse worker fleet and jump to selected agent."
  (interactive)
  (let ((workers (wheelhouse--list-active-workers)))
    (if (null workers)
        (message "[Wheelhouse] No active worker agents running.")
      (let* ((names (mapcar #'buffer-name workers))
             (choice (completing-read "Select Worker Agent: " names nil t))
             (buf (get-buffer choice)))
        (when buf
          (pop-to-buffer buf))))))

;; =============================================================================
;; Refinery (Review, Merge, Pruning)
;; =============================================================================

;;;###autoload
(defun wheelhouse-refinery-magit (&optional bead)
  "Open Magit status inside the worktree of BEAD, the current Bead, or a prompt."
  (interactive)
  (let* ((proj-root (wheelhouse--project-root))
         (wt-parent (expand-file-name wheelhouse-worktree-dir proj-root))
         (bead-id (or bead
                      (if (and (derived-mode-p 'org-mode) (org-entry-get nil "ID"))
                      (org-entry-get nil "ID")
                        (if (file-directory-p wt-parent)
                            (completing-read "Review Worktree for Bead: "
                                             (wheelhouse--worktree-slugs proj-root))
                          (user-error "No worktrees found in %s" wt-parent)))))
         (wt-dir (expand-file-name (format "%s/%s" wheelhouse-worktree-dir bead-id) proj-root)))
    (if (file-directory-p wt-dir)
        (magit-status wt-dir)
      (user-error "Worktree directory does not exist: %s" wt-dir))))

;;;###autoload
(defun wheelhouse-refinery-merge (&optional bead)
  "Merge BEAD's worktree branch into the current branch and clean up.
BEAD defaults to the Bead at point in Org, or is read from the worktrees."
  (interactive)
  (let* ((proj-root (wheelhouse--project-root))
         (bead-id (or bead
                      (if (and (derived-mode-p 'org-mode) (org-entry-get nil "ID"))
                          (org-entry-get nil "ID")
                        (completing-read "Refinery Merge for Bead: "
                                         (wheelhouse--worktree-slugs proj-root)))))
         (branch (or (and (null bead)
                          (derived-mode-p 'org-mode)
                          (org-entry-get nil "BRANCH"))
                     (concat "bead-" bead-id)))
         (wt-dir (expand-file-name (format "%s/%s" wheelhouse-worktree-dir bead-id) proj-root)))
    
    (when (yes-or-no-p (format "Merge branch '%s' into current branch and prune worktree %s? " branch bead-id))
      ;; 1. Merge in main project root
      (let ((default-directory proj-root))
        (message "[Wheelhouse Refinery] Merging %s..." branch)
        (let ((res (call-process "git" nil nil nil "merge" "--no-ff" "-m" (format "Refinery: Merge %s" bead-id) branch)))
          (unless (zerop res)
            (user-error "Git merge failed. Check git status in project root"))))
      
      ;; 2. Kill worker buffers
      (dolist (backend '(agy claude))
        (let ((buf (get-buffer (wheelhouse--buffer-name backend bead-id))))
          (when (buffer-live-p buf)
            (kill-buffer buf))))
      
      ;; 3. Prune worktree
      (let ((default-directory proj-root))
        (call-process "git" nil nil nil "worktree" "remove" "--force" wt-dir)
        (message "[Wheelhouse Refinery] Worktree %s pruned." bead-id))
      
      ;; 4. Close the Gastown bead, if this worktree came from one
      (let ((bd-id (wheelhouse--recall-bead-id proj-root bead-id)))
        (when (and bd-id (wheelhouse--bd-program))
          (wheelhouse--run-logged (wheelhouse--bd-program)
                                  (list "close" bd-id "Refinery merge")
                                  proj-root)
          (delete-file (wheelhouse--bead-id-file proj-root bead-id))))

      ;; 5. Update Org state if in org buffer
      (when (derived-mode-p 'org-mode)
        (org-todo "DONE")
        (org-entry-put nil "REFINED_AT" (format-time-string "[%Y-%m-%d %a %H:%M]"))
        (save-buffer))
      
      (message "[Wheelhouse Refinery] Bead %s successfully merged and cleaned!" bead-id))))

;;;###autoload
(defun wheelhouse-kill-worker (&optional bead)
  "Prune BEAD's worktree and kill its worker buffer without merging."
  (interactive)
  (let* ((proj-root (wheelhouse--project-root))
         (bead-id (or bead
                      (if (and (derived-mode-p 'org-mode) (org-entry-get nil "ID"))
                          (org-entry-get nil "ID")
                        (completing-read "Kill / Prune Worktree for Bead: "
                                         (wheelhouse--worktree-slugs proj-root)))))
         (wt-dir (expand-file-name (format "%s/%s" wheelhouse-worktree-dir bead-id) proj-root)))
    
    (when (yes-or-no-p (format "Kill worker and delete worktree %s without merging? " bead-id))
      ;; Kill worker buffers
      (dolist (backend '(agy claude))
        (let ((buf (get-buffer (wheelhouse--buffer-name backend bead-id))))
          (when (buffer-live-p buf)
            (kill-buffer buf))))
      ;; Remove worktree
      (let ((default-directory proj-root))
        (call-process "git" nil nil nil "worktree" "remove" "--force" wt-dir))
      ;; Update Org state if in org-mode
      (when (derived-mode-p 'org-mode)
        (org-todo "CANCELLED")
        (save-buffer))
      (message "[Wheelhouse] Worker %s killed and worktree deleted." bead-id))))

;; =============================================================================
;; Bead Templates & Officer Tools
;; =============================================================================

;;;###autoload
(defun wheelhouse-insert-bead (title id)
  "Insert a structured Bead template at point in current Org buffer.
TITLE is the task headline, ID is the bead identifier (e.g., '101' or 'storage-fix')."
  (interactive "sBead Title: \nsBead ID (e.g. 101 or auth-jwt): ")
  (let* ((slug (wheelhouse--slugify (if (string-empty-p id) title id)))
         (branch (format "bead-%s" slug)))
    (insert (format "** TODO Bead-%s: %s\n" slug title))
    (insert "   :PROPERTIES:\n")
    (insert (format "   :ID:        bead-%s\n" slug))
    (insert (format "   :BRANCH:    %s\n" branch))
    (insert "   :BACKEND:   agy\n")
    (insert "   :AUTOPILOT: no\n")
    (insert "   :END:\n")
    (insert "   - [ ] Specification / Goal:\n")
    (insert "   - [ ] Verification Command:\n")
    (insert "   - Prompt:\n")
    (insert "     #+begin_src markdown\n")
    (insert (format "     Goal: %s\n" title))
    (insert "     Requirements:\n")
    (insert "     - \n")
    (insert "     Verification: Run unit tests and ensure clean exit.\n")
    (insert "     #+end_src\n\n")))

;;;###autoload
(defun wheelhouse-open-beads-file (&optional root)
  "Open the beads.org file of ROOT (defaults to the current project root)."
  (interactive)
  (let* ((proj-root (or root (wheelhouse--project-root)))
         (beads-path (expand-file-name wheelhouse-beads-file proj-root)))
    (if (file-exists-p beads-path)
        (find-file beads-path)
      (when (y-or-n-p (format "%s does not exist. Create it now? " beads-path))
        (find-file beads-path)
        (insert "#+TITLE: Project Task Graph (Wheelhouse: Gas Town Redux)\n")
        (insert "#+FILETAGS: :wheelhouse:\n")
        (insert "#+SEQ_TODO: TODO(t) READY(r) DISPATCHED(d) | DONE(f) CANCELLED(c)\n\n")
        (insert "* Roadmap & Architecture Notes\n\n")
        (insert "* Task Graph (Beads)\n\n")
        (save-buffer)))))

;; =============================================================================
;; Gastown Beads CLI (bd) Bridge
;; =============================================================================

(defcustom wheelhouse-bd-executable "bd"
  "Name of (or absolute path to) the Gastown beads CLI executable."
  :type 'string
  :group 'wheelhouse)

(defcustom wheelhouse-bd-search-paths '("~/.local/bin" "/usr/local/bin" "/opt/homebrew/bin")
  "Extra directories searched for the beads CLI when it is not on `exec-path'.
A GUI Emacs often has a shorter PATH than an interactive shell."
  :type '(repeat string)
  :group 'wheelhouse)

(defconst wheelhouse-bd-install-command
  "curl -fsSL https://raw.githubusercontent.com/gastownhall/beads/main/scripts/install.sh | bash"
  "Vendor-documented install command for the Gastown beads CLI.")

(defvar wheelhouse-bd-log-buffer "*wheelhouse-bd*"
  "Buffer collecting the output of every bd command Wheelhouse runs.")

(defun wheelhouse--bd-program ()
  "Return the beads CLI executable path, or nil when it is not installed."
  (or (executable-find wheelhouse-bd-executable)
      (cl-some (lambda (dir)
                 (let ((path (expand-file-name wheelhouse-bd-executable dir)))
                   (and (file-executable-p path) path)))
               wheelhouse-bd-search-paths)))

(defun wheelhouse--bd-require ()
  "Return the beads CLI path or signal a `user-error' explaining how to install it."
  (or (wheelhouse--bd-program)
      (user-error "Beads CLI (bd) is not on PATH. Install it once, system-wide: %s"
                  wheelhouse-bd-install-command)))

(defun wheelhouse--run-logged (program args dir)
  "Run PROGRAM with ARGS in DIR, appending everything to `wheelhouse-bd-log-buffer'.
Return the exit code."
  (let* ((default-directory (file-name-as-directory (expand-file-name dir)))
         (buf (get-buffer-create wheelhouse-bd-log-buffer))
         (code nil))
    (with-current-buffer buf
      (goto-char (point-max))
      (insert (format "\n$ cd %s && %s %s\n"
                      default-directory program (mapconcat #'identity args " ")))
      (setq code (apply #'process-file program nil t t args))
      (insert (format "[exit %s]\n" code)))
    code))

(defun wheelhouse--bd-call (dir &rest args)
  "Run bd with ARGS in DIR. Return a cons cell (EXIT-CODE . OUTPUT)."
  (let* ((bd (wheelhouse--bd-require))
         (default-directory (file-name-as-directory (expand-file-name dir))))
    (with-temp-buffer
      (let ((code (apply #'process-file bd nil t nil args)))
        (cons code (buffer-string))))))

(defun wheelhouse--bd-normalize (data)
  "Coerce parsed bd JSON DATA into a plain list of issue alists.
Accepts a bare array, an array parsed as a vector, a single issue object, or
an object wrapping the collection under a key such as `issues'."
  (let ((data (if (vectorp data) (append data nil) data)))
    (cond
     ((null data) nil)
     ;; A single JSON object: either one issue, or a wrapper around a collection.
     ((and (consp (car-safe data)) (symbolp (car-safe (car-safe data))))
      (let ((nested (cl-some (lambda (key) (alist-get key data))
                             '(issues beads ready results data))))
        (cond ((vectorp nested) (append nested nil))
              (nested nested)
              (t (list data)))))
     ((listp data) data)
     (t nil))))

(defun wheelhouse--bd-json (dir &rest args)
  "Run bd with ARGS in DIR and return its JSON output as a list of alists."
  (let* ((res (apply #'wheelhouse--bd-call dir args))
         (code (car res))
         (out (string-trim (cdr res))))
    (unless (zerop code)
      (user-error "bd %s failed: %s" (mapconcat #'identity args " ") out))
    (unless (string-empty-p out)
      (let ((json-object-type 'alist)
            (json-array-type 'list)
            (json-key-type 'symbol))
        (wheelhouse--bd-normalize
         (condition-case nil
             (json-read-from-string out)
           (error (user-error "Could not parse JSON from: bd %s"
                              (mapconcat #'identity args " ")))))))))

(defun wheelhouse--bd-field (issue &rest keys)
  "Return the first non-empty value among KEYS in ISSUE."
  (cl-some (lambda (key)
             (let ((val (alist-get key issue)))
               (and val (not (eq val :null))
                    (not (equal val ""))
                    val)))
           keys))

(defun wheelhouse--bd-id (issue)
  "Return the bead identifier of ISSUE as a string."
  (let ((id (wheelhouse--bd-field issue 'id 'ID 'issue_id 'issueId 'key)))
    (and id (format "%s" id))))

(defun wheelhouse--bd-title (issue)
  "Return the title of ISSUE as a string."
  (format "%s" (or (wheelhouse--bd-field issue 'title 'summary 'name 'text 'description) "")))

(defun wheelhouse--bd-status (issue)
  "Return the status of ISSUE as a string."
  (format "%s" (or (wheelhouse--bd-field issue 'status 'state) "open")))

(defun wheelhouse--bd-issues (&optional dir)
  "Return the open beads of DIR, preferring `bd list' and falling back to `bd ready'."
  (let ((root (or dir (wheelhouse--project-root))))
    (or (ignore-errors (wheelhouse--bd-json root "list" "--json"))
        (wheelhouse--bd-json root "ready" "--json"))))

(defun wheelhouse--bd-initialized-p (&optional dir)
  "Return non-nil when DIR has been initialised with `bd init'."
  (file-directory-p (expand-file-name ".beads" (or dir (wheelhouse--project-root)))))

;; Worktree slugs are derived from bead ids, so the mapping back to the original
;; id (which may contain dots, e.g. bd-a3f8.1) is remembered on disk.

(defun wheelhouse--bead-id-file (root slug)
  "Return the file recording the bd id behind worktree SLUG under ROOT."
  (expand-file-name (format "%s.bdid" slug)
                    (expand-file-name wheelhouse-worktree-dir root)))

(defun wheelhouse--remember-bead-id (root slug bd-id)
  "Record that worktree SLUG under ROOT was dispatched from bead BD-ID."
  (let ((file (wheelhouse--bead-id-file root slug)))
    (make-directory (file-name-directory file) t)
    (with-temp-file file (insert bd-id "\n"))))

(defun wheelhouse--recall-bead-id (root slug)
  "Return the bd id behind worktree SLUG under ROOT, or nil."
  (let ((file (wheelhouse--bead-id-file root slug)))
    (when (file-readable-p file)
      (let ((id (string-trim (with-temp-buffer
                               (insert-file-contents file)
                               (buffer-string)))))
        (unless (string-empty-p id) id)))))

(defun wheelhouse--worktree-slugs (&optional root)
  "Return the worktree directory names under ROOT."
  (let* ((root (or root (wheelhouse--project-root)))
         (parent (expand-file-name wheelhouse-worktree-dir root)))
    (when (file-directory-p parent)
      (cl-remove-if-not (lambda (name)
                          (file-directory-p (expand-file-name name parent)))
                        (directory-files parent nil "^[^.]")))))

(defun wheelhouse--read-backend (label)
  "Prompt for a backend to run LABEL with."
  (intern (completing-read
           (format "Select AI Backend for [%s] (default: %s): "
                   label wheelhouse-default-backend)
           '("agy" "claude") nil t nil nil
           (symbol-name wheelhouse-default-backend))))

(defun wheelhouse--bd-read-issue (&optional dir)
  "Prompt for one open bead in DIR and return its alist."
  (let* ((root (or dir (wheelhouse--project-root)))
         (issues (wheelhouse--bd-issues root)))
    (unless issues
      (user-error "bd reports no open beads in %s" root))
    (let* ((rows (mapcar (lambda (issue)
                           (cons (format "%-14s %s"
                                         (or (wheelhouse--bd-id issue) "?")
                                         (wheelhouse--bd-title issue))
                                 issue))
                         issues))
           (choice (completing-read "Bead: " rows nil t)))
      (cdr (assoc choice rows)))))

(defun wheelhouse--bd-worker-prompt (id title)
  "Return the opening prompt handed to an agent working bead ID titled TITLE."
  (format (concat "Work Gastown bead %s: %s. "
                  "Run `bd show %s` for the full spec and `bd update %s --claim` to claim it. "
                  "Record findings with `bd remember`. "
                  "When the work is verified, run `bd close %s`. "
                  "You are in an isolated git worktree; commit on this branch only.")
          id title id id id))

(defun wheelhouse--ensure-gitignore (root)
  "Ensure ROOT's .gitignore excludes the Wheelhouse worktree directory."
  (let* ((file (expand-file-name ".gitignore" root))
         (entry (concat wheelhouse-worktree-dir "/"))
         (current (if (file-readable-p file)
                      (with-temp-buffer (insert-file-contents file) (buffer-string))
                    "")))
    (unless (string-match-p (concat "^" (regexp-quote entry) "$") current)
      (with-temp-file file
        (insert current)
        (unless (or (string-empty-p current) (string-suffix-p "\n" current))
          (insert "\n"))
        (insert entry "\n"))
      (message "[Wheelhouse] Added %s to .gitignore" entry))))

;;;###autoload
(defun wheelhouse-init-project (&optional dir)
  "Initialise Wheelhouse and Gastown beads in DIR.
Creates the git repository if needed, runs `bd init' (which installs the
Claude Code and Codex integration), ignores the worktree directory and opens
the cockpit. The beads CLI itself must already be installed system-wide."
  (interactive (list (read-directory-name "Initialise Wheelhouse in: "
                                          (wheelhouse--project-root))))
  (let* ((root (file-name-as-directory (expand-file-name (or dir (wheelhouse--project-root))))))
    (unless (file-directory-p root)
      (if (y-or-n-p (format "%s does not exist. Create it? " root))
          (make-directory root t)
        (user-error "Aborted")))
    ;; 1. Git repository (worktrees need one)
    (unless (file-exists-p (expand-file-name ".git" root))
      (if (y-or-n-p (format "%s is not a git repository. Run git init? " root))
          (wheelhouse--run-logged "git" '("init") root)
        (user-error "Wheelhouse needs a git repository for worktrees")))
    ;; 2. Beads CLI: installed once, system-wide, outside Emacs.
    (unless (wheelhouse--bd-program)
      (user-error "Beads CLI (bd) is not on PATH. Install it once, system-wide: %s"
                  wheelhouse-bd-install-command))
    ;; 3. bd init, which also installs the Claude Code and Codex integration.
    (if (wheelhouse--bd-initialized-p root)
        (message "[Wheelhouse] .beads already present; skipping bd init.")
      (wheelhouse--run-logged (wheelhouse--bd-program) '("init") root))
    ;; 4. Housekeeping
    (wheelhouse--ensure-gitignore root)
    (when (y-or-n-p "Also create a beads.org notes file? ")
      (wheelhouse-open-beads-file root))
    (message "[Wheelhouse] %s initialised. SPC o w SPC opens the cockpit." root)
    (wheelhouse-cockpit)))

;;;###autoload
(defun wheelhouse-bd-dispatch (issue &optional backend autopilot)
  "Dispatch Gastown bead ISSUE into its own worktree and agent.
ISSUE is an alist from bd, or a bead id string. With a prefix argument the
agent is launched in autopilot (permission prompts skipped)."
  (interactive (list (wheelhouse--bd-read-issue) nil current-prefix-arg))
  (let* ((root (wheelhouse--project-root))
         (id (if (stringp issue) issue (wheelhouse--bd-id issue)))
         (title (if (stringp issue) "" (wheelhouse--bd-title issue)))
         (slug (wheelhouse--slugify id))
         (branch (format "bead-%s" slug))
         (backend (or backend (wheelhouse--read-backend id))))
    (when (string-empty-p (or slug ""))
      (user-error "Bead has no usable id"))
    (wheelhouse-create-worktree slug branch)
    (wheelhouse--remember-bead-id root slug id)
    ;; Claim the bead so other agents skip it. Best effort: an older bd may
    ;; not support --claim, and that must not abort the dispatch.
    (ignore-errors (wheelhouse--run-logged (wheelhouse--bd-program)
                                           (list "update" id "--claim") root))
    (wheelhouse-spawn-worker slug backend
                             (wheelhouse--bd-worker-prompt id title)
                             (and autopilot t))
    (message "[Wheelhouse] Bead %s dispatched to %s in %s/%s"
             id backend wheelhouse-worktree-dir slug)))

;;;###autoload
(defun wheelhouse-bd-dispatch-agy (issue &optional autopilot)
  "Dispatch Gastown bead ISSUE with the Antigravity CLI."
  (interactive (list (wheelhouse--bd-read-issue) current-prefix-arg))
  (wheelhouse-bd-dispatch issue 'agy autopilot))

;;;###autoload
(defun wheelhouse-bd-dispatch-claude (issue &optional autopilot)
  "Dispatch Gastown bead ISSUE with Claude Code."
  (interactive (list (wheelhouse--bd-read-issue) current-prefix-arg))
  (wheelhouse-bd-dispatch issue 'claude autopilot))

(defun wheelhouse--bd-output-buffer (name args)
  "Run bd with ARGS and show the output in a buffer called NAME."
  (let* ((root (wheelhouse--project-root))
         (res (apply #'wheelhouse--bd-call root args))
         (buf (get-buffer-create name)))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (cdr res))
        (goto-char (point-min)))
      (special-mode))
    (pop-to-buffer buf)
    buf))

;;;###autoload
(defun wheelhouse-bd-show (issue)
  "Show the full bd record for ISSUE."
  (interactive (list (wheelhouse--bd-read-issue)))
  (let ((id (if (stringp issue) issue (wheelhouse--bd-id issue))))
    (wheelhouse--bd-output-buffer (format "*bd: %s*" id) (list "show" id))))

;;;###autoload
(defun wheelhouse-bd-create (title priority type)
  "Create a new bead titled TITLE with PRIORITY and TYPE."
  (interactive
   (list (read-string "Bead title: ")
         (completing-read "Priority (0 highest): " '("0" "1" "2" "3") nil nil "2")
         (completing-read "Type: " '("task" "bug" "feature" "chore" "epic") nil nil "task")))
  (when (string-empty-p (string-trim title))
    (user-error "A bead needs a title"))
  (wheelhouse--run-logged (wheelhouse--bd-require)
                          (list "create" title "-p" priority "-t" type)
                          (wheelhouse--project-root))
  (message "[Wheelhouse] Created bead: %s" title)
  (when (derived-mode-p 'wheelhouse-cockpit-mode)
    (wheelhouse-cockpit-refresh)))

;;;###autoload
(defun wheelhouse-bd-close (issue note)
  "Close bead ISSUE with an optional NOTE."
  (interactive (list (wheelhouse--bd-read-issue)
                     (read-string "Closing note (optional): ")))
  (let* ((id (if (stringp issue) issue (wheelhouse--bd-id issue)))
         (args (if (string-empty-p (string-trim note))
                   (list "close" id)
                 (list "close" id note))))
    (wheelhouse--run-logged (wheelhouse--bd-require) args (wheelhouse--project-root))
    (message "[Wheelhouse] Closed bead %s" id)
    (when (derived-mode-p 'wheelhouse-cockpit-mode)
      (wheelhouse-cockpit-refresh))))

;;;###autoload
(defun wheelhouse-bd-prime ()
  "Show `bd prime': the agent workflow context and stored project memories."
  (interactive)
  (wheelhouse--bd-output-buffer "*bd prime*" (list "prime")))

;; =============================================================================
;; Cockpit
;; =============================================================================

(defvar wheelhouse-cockpit-buffer-name "*Wheelhouse Cockpit*"
  "Name of the Wheelhouse cockpit buffer.")

(defvar wheelhouse-cockpit-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") #'wheelhouse-cockpit-show)
    (define-key map (kbd "g")   #'wheelhouse-cockpit-refresh)
    (define-key map (kbd "d")   #'wheelhouse-cockpit-dispatch)
    (define-key map (kbd "a")   #'wheelhouse-cockpit-dispatch-agy)
    (define-key map (kbd "c")   #'wheelhouse-cockpit-dispatch-claude)
    (define-key map (kbd "w")   #'wheelhouse-cockpit-jump-to-worker)
    (define-key map (kbd "m")   #'wheelhouse-cockpit-magit)
    (define-key map (kbd "r")   #'wheelhouse-cockpit-merge)
    (define-key map (kbd "K")   #'wheelhouse-cockpit-kill)
    (define-key map (kbd "x")   #'wheelhouse-cockpit-close-bead)
    (define-key map (kbd "n")   #'wheelhouse-bd-create)
    (define-key map (kbd "v")   #'wheelhouse-multiagent-view)
    (define-key map (kbd "q")   #'quit-window)
    map)
  "Keymap for `wheelhouse-cockpit-mode'.")

(with-eval-after-load 'evil
  (when (fboundp 'evil-define-key*)
    (evil-define-key* 'normal wheelhouse-cockpit-mode-map
      (kbd "RET") #'wheelhouse-cockpit-show
      (kbd "gr")  #'wheelhouse-cockpit-refresh
      "d" #'wheelhouse-cockpit-dispatch
      "a" #'wheelhouse-cockpit-dispatch-agy
      "c" #'wheelhouse-cockpit-dispatch-claude
      "w" #'wheelhouse-cockpit-jump-to-worker
      "m" #'wheelhouse-cockpit-magit
      "r" #'wheelhouse-cockpit-merge
      "K" #'wheelhouse-cockpit-kill
      "x" #'wheelhouse-cockpit-close-bead
      "n" #'wheelhouse-bd-create
      "v" #'wheelhouse-multiagent-view
      "q" #'quit-window)))

(define-derived-mode wheelhouse-cockpit-mode tabulated-list-mode "Wheelhouse"
  "Cockpit listing every Gastown bead, worktree and running agent."
  (setq tabulated-list-format
        [("State" 8 t) ("Bead" 16 t) ("Title" 52 t) ("Agent" 7 t) ("Worktree" 26 t)])
  (setq tabulated-list-padding 1)
  (setq tabulated-list-sort-key (cons "State" nil))
  (setq header-line-format
        " RET spec · d/a/c dispatch · w worker · m magit · r refine · K kill · x close · n new · gr refresh · q quit")
  (tabulated-list-init-header))

(defun wheelhouse--cockpit-state-label (status)
  "Return a short cockpit label for the bd STATUS string."
  (let ((s (downcase (or status "open"))))
    (cond ((string-match-p "in_progress\\|in-progress\\|claim" s) "CLAIMED")
          ((string-match-p "block" s) "BLOCKED")
          ((string-match-p "clos\\|done" s) "CLOSED")
          ((string-match-p "orphan" s) "ORPHAN")
          (t (upcase (truncate-string-to-width s 8))))))

(defun wheelhouse--cockpit-worker (slug)
  "Return (BACKEND-NAME . BUFFER) for a live worker on SLUG, or nil."
  (cl-loop for backend in '(agy claude)
           for buf = (get-buffer (wheelhouse--buffer-name backend slug))
           when (buffer-live-p buf)
           return (cons (symbol-name backend) buf)))

(defun wheelhouse--cockpit-row (root id slug title status)
  "Build one cockpit row for bead ID (worktree SLUG) under ROOT."
  (let* ((wt (expand-file-name slug (expand-file-name wheelhouse-worktree-dir root)))
         (has-wt (file-directory-p wt))
         (worker (wheelhouse--cockpit-worker slug))
         (state (cond (worker "RUN")
                      (has-wt "WT")
                      (t (wheelhouse--cockpit-state-label status)))))
    (list (list :id id :slug slug :title title)
          (vector state
                  (or id slug)
                  title
                  (or (car worker) "-")
                  (if has-wt (format "%s/%s" wheelhouse-worktree-dir slug) "-")))))

(defun wheelhouse--cockpit-entries ()
  "Return the tabulated-list entries for the cockpit."
  (let* ((root (wheelhouse--project-root))
         (issues (condition-case err (wheelhouse--bd-issues root)
                   (error (message "[Wheelhouse] bd unavailable: %s"
                                   (error-message-string err))
                          nil)))
         (seen '())
         (rows '()))
    (dolist (issue issues)
      (let* ((id (or (wheelhouse--bd-id issue) ""))
             (slug (wheelhouse--slugify id)))
        (push slug seen)
        (push (wheelhouse--cockpit-row root id slug
                                       (wheelhouse--bd-title issue)
                                       (wheelhouse--bd-status issue))
              rows)))
    ;; Worktrees with no matching bead (dispatched from Org, or bd not running).
    (dolist (slug (wheelhouse--worktree-slugs root))
      (unless (member slug seen)
        (push (wheelhouse--cockpit-row root
                                       (or (wheelhouse--recall-bead-id root slug) slug)
                                       slug "(worktree, no bead record)" "orphan")
              rows)))
    (nreverse rows)))

(defun wheelhouse-cockpit-refresh ()
  "Reload the cockpit from bd, the worktrees and the live agent buffers."
  (interactive)
  (with-current-buffer (get-buffer-create wheelhouse-cockpit-buffer-name)
    (let ((line (line-number-at-pos)))
      (setq tabulated-list-entries (wheelhouse--cockpit-entries))
      (tabulated-list-print t)
      (goto-char (point-min))
      (forward-line (1- line)))))

(defun wheelhouse--cockpit-current ()
  "Return the plist of the cockpit row at point."
  (or (tabulated-list-get-id)
      (user-error "No bead on this line")))

;;;###autoload
(defun wheelhouse-cockpit ()
  "Open the Wheelhouse cockpit: every bead, worktree and agent in one place."
  (interactive)
  (let ((buf (get-buffer-create wheelhouse-cockpit-buffer-name)))
    (with-current-buffer buf
      (unless (derived-mode-p 'wheelhouse-cockpit-mode)
        (wheelhouse-cockpit-mode))
      (setq tabulated-list-entries (wheelhouse--cockpit-entries))
      (tabulated-list-print t))
    (pop-to-buffer buf)))

(defun wheelhouse-cockpit-show ()
  "Show the bd record for the bead at point."
  (interactive)
  (wheelhouse-bd-show (plist-get (wheelhouse--cockpit-current) :id)))

(defun wheelhouse-cockpit-dispatch (&optional backend)
  "Dispatch the bead at point, prompting for BACKEND when it is nil."
  (interactive)
  (let* ((row (wheelhouse--cockpit-current))
         (id (plist-get row :id)))
    (wheelhouse-bd-dispatch id (or backend (wheelhouse--read-backend id))
                            current-prefix-arg)
    (wheelhouse-cockpit-refresh)))

(defun wheelhouse-cockpit-dispatch-agy ()
  "Dispatch the bead at point with the Antigravity CLI."
  (interactive)
  (wheelhouse-cockpit-dispatch 'agy))

(defun wheelhouse-cockpit-dispatch-claude ()
  "Dispatch the bead at point with Claude Code."
  (interactive)
  (wheelhouse-cockpit-dispatch 'claude))

(defun wheelhouse-cockpit-jump-to-worker ()
  "Jump to the running agent buffer of the bead at point."
  (interactive)
  (let* ((slug (plist-get (wheelhouse--cockpit-current) :slug))
         (worker (wheelhouse--cockpit-worker slug)))
    (unless worker
      (user-error "No agent running for %s" slug))
    (pop-to-buffer (cdr worker))))

(defun wheelhouse-cockpit-magit ()
  "Open Magit in the worktree of the bead at point."
  (interactive)
  (wheelhouse-refinery-magit (plist-get (wheelhouse--cockpit-current) :slug)))

(defun wheelhouse-cockpit-merge ()
  "Run the Refinery merge for the bead at point."
  (interactive)
  (wheelhouse-refinery-merge (plist-get (wheelhouse--cockpit-current) :slug))
  (wheelhouse-cockpit-refresh))

(defun wheelhouse-cockpit-kill ()
  "Kill the agent and delete the worktree of the bead at point, without merging."
  (interactive)
  (wheelhouse-kill-worker (plist-get (wheelhouse--cockpit-current) :slug))
  (wheelhouse-cockpit-refresh))

(defun wheelhouse-cockpit-close-bead ()
  "Close the bead at point in bd."
  (interactive)
  (let ((id (plist-get (wheelhouse--cockpit-current) :id)))
    (wheelhouse-bd-close id (read-string (format "Closing note for %s (optional): " id)))
    (wheelhouse-cockpit-refresh)))

(provide 'wheelhouse)
;;; wheelhouse.el ends here
