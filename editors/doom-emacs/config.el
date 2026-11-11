;;; $DOOMDIR/config.el -*- lexical-binding: t; -*-

;; Place your private configuration here! Remember, you do not need to run 'doom
;; sync' after modifying this file!


;; Some functionality uses this to identify you, e.g. GPG configuration, email
;; clients, file templates and snippets. It is optional.
;; (setq user-full-name "John Doe"
;;       user-mail-address "john@doe.com")

;; Doom exposes five (optional) variables for controlling fonts in Doom:
;;
;; - `doom-font' -- the primary font to use
;; - `doom-variable-pitch-font' -- a non-monospace font (where applicable)
;; - `doom-big-font' -- used for `doom-big-font-mode'; use this for
;;   presentations or streaming.
;; - `doom-symbol-font' -- for symbols
;; - `doom-serif-font' -- for the `fixed-pitch-serif' face
;;
;; See 'C-h v doom-font' for documentation and more examples of what they
;; accept. For example:
;;
;;(setq doom-font (font-spec :family "Fira Code" :size 12 :weight 'semi-light)
;;      doom-variable-pitch-font (font-spec :family "Fira Sans" :size 13))
;;
;; If you or Emacs can't find your font, use 'M-x describe-font' to look them
;; up, `M-x eval-region' to execute elisp code, and 'M-x doom/reload-font' to
;; refresh your font settings. If Emacs still can't find your font, it likely
;; wasn't installed correctly. Font issues are rarely Doom issues!

;; There are two ways to load a theme. Both assume the theme is installed and
;; available. You can either set `doom-theme' or manually load a theme with the
;; `load-theme' function. This is the default:
(setq doom-theme 'doom-one)

;; This determines the style of line numbers in effect. If set to `nil', line
;; numbers are disabled. For relative line numbers, set this to `relative'.
(setq display-line-numbers-type t)

;; If you use `org' and don't want your org files in the default location below,
;; change `org-directory'. It must be set before org loads!
(setq org-directory "~/org/")


;; Whenever you reconfigure a package, make sure to wrap your config in an
;; `with-eval-after-load' block, otherwise Doom's defaults may override your
;; settings. E.g.
;;
;;   (with-eval-after-load 'PACKAGE
;;     (setq x y))
;;
;; The exceptions to this rule:
;;
;;   - Setting file/directory variables (like `org-directory')
;;   - Setting variables which explicitly tell you to set them before their
;;     package is loaded (see 'C-h v VARIABLE' to look them up).
;;   - Setting doom variables (which start with 'doom-' or '+').
;;
;; Here are some additional functions/macros that will help you configure Doom.
;;
;; - `load!' for loading external *.el files relative to this one
;; - `add-load-path!' for adding directories to the `load-path', relative to
;;   this file. Emacs searches the `load-path' when you load packages with
;;   `require' or `use-package'.
;; - `map!' for binding new keys
;;
;; To get information about any of these functions/macros, move the cursor over
;; the highlighted symbol at press 'K' (non-evil users must press 'C-c c k').
;; This will open documentation for it, including demos of how they are used.
;; Alternatively, use `C-h o' to look up a symbol (functions, variables, faces,
;; etc).
;;
;; You can also try 'gd' (or 'C-c c d') to jump to their definition and see how
;; they are implemented.

;; GUI Emacs doesn't inherit PATH from ~/.zshrc, so make sure ~/.local/bin
;; (where the sioyek symlink lives) is visible to Emacs and its subprocesses.
(let ((localbin (expand-file-name "~/.local/bin")))
  (add-to-list 'exec-path localbin)
  (setenv "PATH" (concat localbin ":" (getenv "PATH"))))

;; Use Sioyek as the LaTeX PDF viewer, with SyncTeX forward search
;; (SPC m v jumps to the current line in the PDF) and inverse search
;; (right-click in Sioyek jumps back to the .tex line in Emacs).
(after! tex
  (setq TeX-view-program-selection '((output-pdf "Sioyek"))
        ;; Inverse search calls `emacsclient', which needs the Emacs server.
        TeX-source-correlate-start-server t))

;; Frame background transparency (70% opacity)
(set-frame-parameter nil 'alpha-background 80)
(add-to-list 'default-frame-alist '(alpha-background . 80))

;; Dynamic PDF Night/Midnight Mode matching active Doom theme
(after! pdf-view
  (defun +pdf-view-match-theme-colors-h (&rest _)
    "Set `pdf-view-midnight-colors' to match current Doom theme colors."
    (setq pdf-view-midnight-colors
          (cons (or (doom-color 'fg) (face-foreground 'default) "#bbc2cf")
                (or (doom-color 'bg) (face-background 'default) "#282c34"))))

  (+pdf-view-match-theme-colors-h)
  (add-hook 'doom-load-theme-hook #'+pdf-view-match-theme-colors-h)
  (add-hook 'pdf-view-mode-hook #'+pdf-view-match-theme-colors-h))

;; =============================================================================
;; Ellama (100% Local small model)
;; =============================================================================
(use-package! ellama
  :init
  (setopt ellama-language "English")
  (setq llm-warn-on-nonfree nil) ; Silence proprietary license warning
  :config
  (require 'llm-openai)
  (require 'llm-ollama)
  (require 'ellama-transient)

  ;; llama-server on :8080 requires an API key (blocks other websites from using it).
  ;; The key is generated in ~/.config/local-llm/secrets/llama-server.key.
  (defun my/local-llm-api-key ()
    "Return the local llama-server API key, or nil if it isn't set up."
    (let ((file (expand-file-name "~/.config/local-llm/secrets/llama-server.key")))
      (when (file-readable-p file)
        (with-temp-buffer
          (insert-file-contents file)
          (string-trim (buffer-string))))))

  ;; Default: Local small model running on http://127.0.0.1:8080 (Strict temp=0.1)
  (setq ellama-provider
        (make-llm-openai-compatible
         :url "http://127.0.0.1:8080/v1"
         :key (my/local-llm-api-key)
         :chat-model "small-model"
         :default-chat-temperature 0.1))

  (setq ellama-coding-provider
        (make-llm-openai-compatible
         :url "http://127.0.0.1:8080/v1"
         :key (my/local-llm-api-key)
         :chat-model "small-model"
         :default-chat-temperature 0.1))

  ;; Local providers list
  (setq ellama-providers
        `(("Local model (llama-server)" . ,(make-llm-openai-compatible
                                               :url "http://127.0.0.1:8080/v1"
                                               :key (my/local-llm-api-key)
                                               :chat-model "small-model"
                                               :default-chat-temperature 0.1))
          ("Local model (Ollama)"       . ,(make-llm-ollama
                                               :chat-model "small-model"
                                               :default-chat-temperature 0.1)))))

;; Keybindings under Doom's leader key (SPC l)
(map! :leader
      (:prefix-map ("l" . "ai/ellama")
       :desc "Ellama Menu (Transient)"  "l" #'ellama
       :desc "New / Open Chat"          "c" #'ellama-chat
       :desc "Ask about selection/buf"  "a" #'ellama-ask-about
       :desc "Ask selection"            "s" #'ellama-ask-selection
       :desc "Code complete"            "k" #'ellama-code-complete
       :desc "Code review"              "r" #'ellama-code-review
       :desc "Code improve"             "i" #'ellama-code-improve
       :desc "Code edit"                "e" #'ellama-code-edit
       :desc "Code add"                 "d" #'ellama-code-add
       :desc "Generate commit message"  "g" #'ellama-generate-commit-message
       :desc "Summarize"                "S" #'ellama-summarize
       :desc "Translate"                "T" #'ellama-translate
       :desc "Make list"                "m" #'ellama-make-list
       :desc "Make table"               "t" #'ellama-make-table
       :desc "Select provider/model"    "p" #'ellama-provider-select
       :desc "Start local LLM server"   "1" (cmd! (start-process-shell-command "local-llm" nil "systemctl --user start local-llm")
                                                  (message "Local LLM server started!"))
       :desc "Stop local LLM (free VRAM)" "0" (cmd! (start-process-shell-command "local-llm" nil "systemctl --user stop local-llm")
                                                    (message "Local LLM server stopped (VRAM freed)."))))

;; =============================================================================
;; Custom ASCII Art Banner (Loaded from ~/.config/doom/banner.txt)
;; =============================================================================
(defun my-custom-ascii-banner-from-file ()
  "Return ASCII banner read from ~/.config/doom/banner.txt."
  (let ((banner-file (expand-file-name "banner.txt" doom-user-dir)))
    (if (file-exists-p banner-file)
        (propertize
         (with-temp-buffer
           (insert-file-contents banner-file)
           (buffer-string))
         'face '+dashboard-banner)
      "Banner file not found!")))

(setq +dashboard-ascii-banner-fn #'my-custom-ascii-banner-from-file)
(setq +doom-dashboard-ascii-banner-fn #'my-custom-ascii-banner-from-file)

;; =============================================================================
;; VTerm Settings
;; =============================================================================
(after! vterm
  (setq vterm-max-scrollback 100000))

;; =============================================================================
;; Wheelhouse: Gas Town Redux (agy & claude Fleet Orchestrator)
;; =============================================================================
(after! org
  (require 'org-edna)
  (org-edna-mode 1))

(load! "wheelhouse")

;; Keybindings under Doom's leader key: SPC o w (Wheelhouse) and SPC a w
(map! :leader
      (:prefix-map ("o w" . "wheelhouse")
       :desc "Cockpit (all beads/agents)" "SPC" #'wheelhouse-cockpit
       :desc "Init project (bd init)"     "n" #'wheelhouse-init-project
       :desc "Dispatch bead from bd"      "l" #'wheelhouse-bd-dispatch
       :desc "Show bead (bd show)"        "s" #'wheelhouse-bd-show
       :desc "New bead (bd create)"       "t" #'wheelhouse-bd-create
       :desc "Close bead (bd close)"      "x" #'wheelhouse-bd-close
       :desc "Agent context (bd prime)"   "p" #'wheelhouse-bd-prime
       :desc "Multiagent Grid View"       "v" #'wheelhouse-multiagent-view
       :desc "Worker Fleet Switcher"      "f" #'wheelhouse-fleet
       :desc "Open beads.org Task Graph"  "b" #'wheelhouse-open-beads-file
       :desc "Insert new Bead template"   "i" #'wheelhouse-insert-bead
       :desc "Dispatch Bead (Choose AI)"  "d" #'wheelhouse-dispatch-bead
       :desc "Dispatch with agy"          "a" #'wheelhouse-dispatch-agy
       :desc "Dispatch with claude"       "c" #'wheelhouse-dispatch-claude
       :desc "Inspect Worktree in Magit"  "m" #'wheelhouse-refinery-magit
       :desc "Refinery Merge & Clean"     "r" #'wheelhouse-refinery-merge
       :desc "Kill / Prune Worker"        "k" #'wheelhouse-kill-worker))

(map! :leader
      (:prefix-map ("a" . "ai")
       (:prefix-map ("w" . "wheelhouse")
        :desc "Cockpit (all beads/agents)" "SPC" #'wheelhouse-cockpit
        :desc "Init project (bd init)"     "n" #'wheelhouse-init-project
        :desc "Dispatch bead from bd"      "l" #'wheelhouse-bd-dispatch
        :desc "Show bead (bd show)"        "s" #'wheelhouse-bd-show
        :desc "New bead (bd create)"       "t" #'wheelhouse-bd-create
        :desc "Close bead (bd close)"      "x" #'wheelhouse-bd-close
        :desc "Agent context (bd prime)"   "p" #'wheelhouse-bd-prime
        :desc "Multiagent Grid View"       "v" #'wheelhouse-multiagent-view
        :desc "Worker Fleet Switcher"      "f" #'wheelhouse-fleet
        :desc "Open beads.org Task Graph"  "b" #'wheelhouse-open-beads-file
        :desc "Insert new Bead template"   "i" #'wheelhouse-insert-bead
        :desc "Dispatch Bead (Choose AI)"  "d" #'wheelhouse-dispatch-bead
        :desc "Dispatch with agy"          "a" #'wheelhouse-dispatch-agy
        :desc "Dispatch with claude"       "c" #'wheelhouse-dispatch-claude
        :desc "Inspect Worktree in Magit"  "m" #'wheelhouse-refinery-magit
        :desc "Refinery Merge & Clean"     "r" #'wheelhouse-refinery-merge
        :desc "Kill / Prune Worker"        "k" #'wheelhouse-kill-worker)))

;; =============================================================================
;; Dictation (whisper.el)
;; =============================================================================
;; Records the microphone with ffmpeg and transcribes locally with whisper.cpp;
;; nothing is sent anywhere. The first `whisper-run' clones and builds
;; whisper.cpp and downloads the model, which takes a few minutes.

(use-package! whisper
  :commands (whisper-run whisper-file whisper-select-language)
  :config
  (setq whisper-install-directory (expand-file-name "whisper" doom-cache-dir)
        whisper-model "base"
        whisper-language "en"
        whisper-translate nil
        whisper-use-threads nil
        whisper-recording-timeout 600
        whisper--ffmpeg-input-format "pulse"
        whisper--ffmpeg-input-device "alsa_input.pci-0000_07_00.6.analog-stereo"))

;; SPC o d toggles recording; the same key again stops it and inserts the text.
;; s-d does the same from insert state, where the leader key is unavailable.
(map! :leader :desc "Dictate (whisper)" "o d" #'whisper-run)
(map! :desc "Dictate (whisper)" "s-d" #'whisper-run)
