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

(setq twitch-streamer-online nil)
(setq twitch-online-before nil)

;; helper functions
(defun twitch-get-values (key lst)
  "Returns a list of the values from all entries for the given
  key."
  (mapcar (lambda (x) (cdr (assoc key x))) lst))

(defun twitch-get-index (val lst)
  "Returns the index of the entry for a given value."
  (seq-position
   (mapcar (lambda (x) (cdr (rassoc val x))) lst)
   val))

(defun twitch-uptime (start)
  "Calculate time delta between two timestamps: start and now"
  (let* ((now (time-convert nil 'integer))
         (h (/ (- now start) 3600))
         (m (% (/ (- now start) 60) 60)))
    (format "Uptime %dh%02dm" h m)))

(defun twitch-get-quality (streamer)
  "Returns all quality identifiers (e.g. audio_only, 720p, etc) for
streamer."
  (let ((format-list-full
	 (elt twitch-streamer-online
	      (twitch-get-index streamer twitch-streamer-online))))
    (twitch-get-values 'format_id (cdr (assoc 'formats format-list-full)))))

(defun twitch-get-url (streamer quality)
  "Returns stream url."
  (let ((entry (cdr (assoc
	    'formats
	    (elt twitch-streamer-online
		 (twitch-get-index streamer twitch-streamer-online))))))
      (cdr (assoc 'url (elt entry (twitch-get-index quality entry))))))

(defun twitch-sort-viewers (lst)
  "Returns sorted list by display name. Destroys original!"
  (sort lst (lambda (a b) (string<
			   (cdr (assoc 'display_id a))
			   (cdr (assoc 'display_id b))))))

;; call youtube-dl -j for each streamer in list
(defun twitch-get-stream-status ()
  "Check which streamers in twitch-streamer-list are online at
   the moment."
  (interactive)
  (set-process-sentinel
   ; call youtube-dl
   (make-process
    :name "twitch-get-stream-info"
    :buffer "*twitch-stream-info*"
    :stderr (get-buffer-create "*twitch-stream-info-error*")
    :command (apply 'list twitch-extractor "-j" "-i"
		    (mapcar (lambda (x)
			      (concat "https://twitch.tv/" x))
			    twitch-streamer-list)))
   ; sentinel 
   (lambda (proc msg)
     ; setup lists
     (setq twitch-online-before
           (copy-alist twitch-streamer-online))
     (setq twitch-streamer-online nil)
     ; read and parse json-string line by line
     (with-current-buffer "*twitch-stream-info*"
       (goto-char (point-min))
       (while (not (eobp))
	 (progn
	   (twitch-parse-json-line)
	   (next-line)
	   (move-beginning-of-line 1))))
     ; sort, kill temp buffers, notify
     (setq twitch-streamer-online
	   (twitch-sort-viewers twitch-streamer-online))
     (kill-buffer "*twitch-stream-info*")
     (kill-buffer "*twitch-stream-info-error*")
     (message "Refresh finished: [%s] streamers online"
	      (length twitch-streamer-online))
     (twitch-notify))))

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

;; notify
(require 'notifications)
(defun twitch-notify ()
  "Send a desktop notification for every new streamer since last
  update."
  (let ((now twitch-streamer-online) (before twitch-online-before))
    (dolist (x (twitch-get-values 'display_id now))
      (when (not (member x (twitch-get-values 'display_id before)))
        (let ((entry (elt now (twitch-get-index x now))))
          (notifications-notify
           :title (format "%s"
			  (cdr (assoc 'display_id entry)))
           :body (cdr (assoc 'description entry))
           :app-icon "~/.emacs.d/script/twitch.png" 
           :timeout 30000))))))

;; create twitch buffer
(defvar twitch-buffer-name "*twitch*")
(defun twitch-buffer-create ()
  "Create an org-mode buffer with clickable links."
  (interactive)
  (when (get-buffer twitch-buffer-name)
      (kill-buffer twitch-buffer-name))
  (set-window-buffer (selected-window) (get-buffer-create twitch-buffer-name))
  (with-current-buffer twitch-buffer-name
    (org-mode)
    (princ
     "* Twitch Streamer Online Status\n"
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
    (beginning-of-buffer)))

(defun twitch-generate-elisp-links (streamer formats)
  (mapconcat (lambda (f)
	       (format "[[elisp:(twitch-open-stream \"%s\" \"%s\")][%s]] " streamer f f))
	     formats " "))

;; select stream and play 
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
  (async-shell-command 
   (format "%s %s "
	   twitch-video-player
           (twitch-get-url streamer quality))))

;; twitch chat
(defun twitch-chat ()
  "Connect to twitch chat"
  (interactive)
  (erc :server "irc.chat.twitch.tv"
       :port "6667"
       :password twitch-oauth-token))

