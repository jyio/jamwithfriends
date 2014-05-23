jam with friends
================

Use [jam with friends] to synchronize online music with friends!

- Request tracks from YouTube and SoundCloud
- Search YouTube directly using the interface
- Vote to skip tracks

How to use

- run `./app.py`
- navigate to [localhost:8100]

How this works

- Clients pull audio directly from content providers
- Clients pull only audio content, without video
- The most-requested content plays first
- The playlist repeats when all content has been consumed

Server requirements

- Python 2.7
	- gevent
	- gevent-socketio
	- bottle
	- youtube-dl

Client requirements

- HTML5 audio
	- YouTube
		- AAC preferred
		- WebM occasionally available
	- SoundCloud
		- MP3 required

Tested with

- Google Chrome
- Mozilla Firefox on Windows Vista+ (AAC support)

Might work with

- Apple Safari
- Microsoft Internet Explorer 9+
- Mozilla Firefox on other systems supporting AAC

[jam with friends]: http://jam.now.im/
[localhost:8100]: http://localhost:8100/