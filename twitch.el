;;; twitch.el --- A simple twitch client for emacs

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this file.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; A simple twitch client which lets you check, select and open twitch streams

;;; Code:

(defgroup twitch nil
  "Emacs twitch client."
  :group 'applications)

(defcustom
  twitch-streamer-list
  nil
  "List of your favorite streamers."
  :type '(repeat (choice string
                         (cons string (repeat symbol))))
  :group 'twitch)

(defcustom
  twitch-extractor
  "youtube-dl"
  "Program to extract json data. Works with youtube-dl and yt-dlp."
  :type 'string
  :group 'twitch)

(defcustom
  twitch-video-player
  "mpv"
  "Program to play video stream. Works with mpv and vlc."
  :type 'string
  :group 'twitch)

(defcustom
  twitch-oauth-token
  "oauth:"
  "Your oauth token to join the Twitch irc-gateway."
  :type 'string
  :group 'twitch)

(defvar twitch-streamer-online nil)
(defvar twitch-online-before nil)
(defvar twitch-last-update nil)

(defun twitch-get-values (key lst)
  "Return a LST of the values from all entries for the given KEY."
  (mapcar (lambda (x) (cdr (assoc key x))) lst))

(defun twitch-get-index (val lst)
  "Return a list (LST) of the indices of all the entries for a given value (VAL)."
  (seq-position
   (mapcar (lambda (x) (cdr (rassoc val x))) lst)
   val))

(defun twitch-uptime (start)
  "Calculate time delta between two timestamps: START and now."
  (let* ((now (time-convert nil 'integer))
         (h (/ (- now start) 3600))
         (m (% (/ (- now start) 60) 60)))
    (format "Uptime %dh%02dm" h m)))

(defun twitch-get-quality (streamer)
  "Return all quality identifiers (e.g. 480p, 720p, etc) for STREAMER."
  (let ((format-list-full
	 (elt twitch-streamer-online
	      (twitch-get-index streamer twitch-streamer-online))))
    (twitch-get-values 'format_id (cdr (assoc 'formats format-list-full)))))

(defun twitch-get-url (streamer quality)
  "Return stream url for given STREAMER and QUALITY."
  (let ((entry (cdr (assoc
	    'formats
	    (elt twitch-streamer-online
		 (twitch-get-index streamer twitch-streamer-online))))))
      (cdr (assoc 'url (elt entry (twitch-get-index quality entry))))))

(defun twitch-sort-viewers (lst)
  "Return sorted LST by display name. Alters original!"
  (sort lst (lambda (a b) (string<
			   (cdr (assoc 'display_id a))
			   (cdr (assoc 'display_id b))))))

(defun twitch-get-stream-status ()
  "Check which streamers are online at the moment."
  (interactive)
  ;; process guard
  (if (get-process "twitch-get-stream-info")
      (message "Process already running. Please wait.")
    (set-process-sentinel
     ;; call twitch-extractor for each streamer in list
     (make-process
      :name "twitch-get-stream-info"
      :buffer "*twitch-stream-info*"
      :stderr (get-buffer-create "*twitch-stream-info-error*")
      :command (apply 'list twitch-extractor "-j" "-i"
		      (mapcar (lambda (x)
				(concat "https://twitch.tv/" x))
			      twitch-streamer-list)))
     ;; sentinel
     (lambda (proc msg)
       ;; setup lists
       (setq twitch-online-before
             (copy-alist twitch-streamer-online))
       (setq twitch-streamer-online nil)
       ;; read and parse json-string line by line
       (with-current-buffer "*twitch-stream-info*"
	 (goto-char (point-min))
	 (while (not (eobp))
	   (progn
	     (twitch-parse-json-line)
	     (forward-line)
	     (move-beginning-of-line 1))))
       (setq twitch-last-update (current-time-string))
       ;; sort, kill temp buffers, notify
       (setq twitch-streamer-online
	     (twitch-sort-viewers twitch-streamer-online))
       (kill-buffer "*twitch-stream-info*")
       (kill-buffer "*twitch-stream-info-error*")
       (message "Refresh finished: [%s] streamers online"
		(length twitch-streamer-online))
       (twitch-notify)))))

(require 'json)
(defun twitch-parse-json-line ()
  "Build new list holding all relevant information."
  (let ((res (json-read)))
    (setq
     twitch-streamer-online
     (cons
      (list
       (assoc 'display_id res)
       (assoc 'description res)
       (assoc 'timestamp res)
       (assoc 'formats res))
      twitch-streamer-online))))

(require 'notifications)
(defun twitch-notify ()
  "Send a desktop notification for every new streamer since last update."
  (let ((now twitch-streamer-online) (before twitch-online-before))
    (dolist (x (twitch-get-values 'display_id now))
      (when (not (member x (twitch-get-values 'display_id before)))
        (let ((entry (elt now (twitch-get-index x now))))
          (notifications-notify
           :title (format "%s"
			  (cdr (assoc 'display_id entry)))
           :body (cdr (assoc 'description entry))
           :timeout 30000))))))

;; create twitch buffer
(defvar twitch-buffer-name "*twitch*")
(defun twitch-buffer-create ()
  "Create an 'org-mode' buffer with clickable links."
  (interactive)
  (when (get-buffer twitch-buffer-name)
      (kill-buffer twitch-buffer-name))
  (set-window-buffer (selected-window) (get-buffer-create twitch-buffer-name))
  (with-current-buffer twitch-buffer-name
    (org-mode)
    (princ
     (format
      "* Twitch Streamer Online Status\n/last update %s/\n\n"
      twitch-last-update)
     (current-buffer))
    (mapc (lambda (x)
            (princ (format
                    "** %s\n%s\n%s\n%s \n\n"
                    (cdr (assoc 'display_id x))
                    (cdr (assoc 'description x))
                    (twitch-uptime (cdr (assoc 'timestamp x)))
		    (twitch-generate-elisp-links
		     (cdr (assoc 'display_id x))
		     (twitch-get-values
		      'format_id
		      (cdr (assoc 'formats x)))))
                   (current-buffer)))
          twitch-streamer-online)
    (goto-char (point-min))))

(defun twitch-generate-elisp-links (streamer formats)
  "Return 'org-mode'-links for STREAMER and FORMATS."
  (mapconcat (lambda (f)
	       (format "[[elisp:(twitch-open-stream \"%s\" \"%s\")][%s]] " streamer f f))
	     formats " "))

(defun twitch-select-stream ()
  "Interactive function to select a currently available stream."
  (interactive)
  (let* ((streamer-name
          (completing-read
           "Select stream: "
           (twitch-get-values 'display_id twitch-streamer-online)
	   nil t))
	 (quality
	  (completing-read
	   "quality: "
	   (reverse (twitch-get-quality streamer-name))
	   nil t)))
    (twitch-open-stream
      streamer-name quality)))

(defun twitch-open-stream (streamer quality)
  "Open stream with twitch-video-player for STREAMER in QUALITY."
  (let ((title
	 (cond
	  ((string= twitch-video-player "mpv")
	   (format "--force-media-title='%s (%s)'" streamer quality))
	  ((string= twitch-video-player "vlc")
	   (format "--meta-title '%s (%s)'" streamer quality))
	  (t ""))))
    (async-shell-command
     (format "%s %s %s "
	     twitch-video-player
	     title
             (twitch-get-url streamer quality)))))

(defun twitch-chat ()
  "Connect to twitch chat."
  (interactive)
  (erc :server "irc.chat.twitch.tv"
       :port "6667"
       :password twitch-oauth-token))

(provide 'twitch)
;;; twitch.el ends here
