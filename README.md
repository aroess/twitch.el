# twitch.el

## Intro
This is a simple elisp script for [Emacs](https://www.gnu.org/software/emacs/) which allows you to:

- check if your favorite [Twitch](https://twitch.tv) streamers are online (with notifications)
- open streams with [mpv](https://github.com/mpv-player/mpv), [vlc](https://github.com/videolan/vlc) or your preferred video player
- select streams in the preferred quality via the minibuffer
- select streams from an org-mode buffer with clickable links
- open twitch chat via erc (builtin emacs irc client)

![image](https://github.com/aroess/twitch.el/blob/main/twitch-org-buffer.png?raw=true)

## How does it work?
This script uses [youtube-dl](https://github.com/ytdl-org/youtube-dl) (or [yt-dlp](https://github.com/yt-dlp/yt-dlp)) to query the Twitch API. I used this
approach because Twitch changes their API every 17 seconds and makes
it more akward to use every time. So now when it changes again it's
the problem of the youtube-dl maintainers and not mine. 

**Pros**:
- it uses youtube-dl so when Twitch changes their API and breaks everything it's not on me to fix it.

**Cons**:
- it uses youtube-dl so it's very, very slow and gets even slower when the list of streamers grows.

## Installation
Save `twitch.el` somewhere in your `.emacs.d` folder and put this in your init.el:

```elisp
(load-file "~/.emacs.d/path_to/twitch.el")`
```
## Customization
You can customize twitch.el via `M-x customize-group RET twitch RET`

![image](https://github.com/aroess/twitch.el/blob/main/twitch-customize-group.png?raw=true)

or by setting the following variables in your `init.el`

```elisp
(setq twitch-streamer-list '("streamer_id_a" "streamer_id_b" "streamer_id_c"))
(setq twitch-extractor "yt-dlp")
(setq twitch-video-player "vlc")
(setq twitch-oauth-token "oauth:YOUR_TOKEN")
```

## Usage
- `M-x twitch-get-stream-status` checks which streamers in your list are online. 
- `M-x twitch-select-stream` select and open streams from the minibuffer.
- `M-x twitch-buffer-create` shows an org-mode buffer with streamers currently online. Click on the links to open streams directly.
- `M-x twitch-chat` opens the twitch chat in erc

If you are using [hydra](https://github.com/abo-abo/hydra) you can create a neat menu like so:

```elisp
(defhydra hydra-twitch (:columns 1)
  "Select"
  ("r" twitch-get-stream-status "refresh streamer list" :exit t)
  ("b" twitch-buffer-create "show streamer buffer" :exit t)
  ("t" twitch-select-stream "open stream" :exit t)
  ("c" twitch-chat "open chat" :exit t)
  ("q" nil "quit"))

```

## Limitations
- `twitch-get-stream-status` cannot query the viewer count of streams. It worked some time ago but now it doesn't work and [nobody cares](https://github.com/yt-dlp/yt-dlp/issues/1880).
- `twitch-get-stream-status` cannot query the game category of streams. It worked before twitch changed their API and... you get the point.
- `twitch-chat` only opens an irc buffer and connects to the twitch irc-gateway but doesn't automatically join any channels.

## UI improvements
Emacs by default pops up a new buffer if the script calls `async-shell-command` to open a stream. You can avoid this by putting this in your `init.el`

```elisp
;; auto-hide async shell buffers
(add-to-list 'display-buffer-alist
	     (cons "\\*Async Shell Command\\*.*"
		   (cons #'display-buffer-no-window nil)))
```

If you click a link in an org-mode buffer which calls some elisp code you get a warning (which is good). If you want to disable this warning put this in your `init.el`

`(setq org-confirm-elisp-link-function nil)`
