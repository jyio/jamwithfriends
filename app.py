#!/usr/bin/env python

import re
import json
import math
import time
import hashlib
import weakref

from collections import Counter, deque

import bottle
from bottle import Bottle, static_file

from socketio import socketio_manage
from socketio.namespace import BaseNamespace
from socketio.mixins import BroadcastMixin, RoomsMixin

import gevent.monkey
gevent.monkey.patch_socket()
gevent.monkey.patch_ssl()

import youtube_dl

ydl = youtube_dl.YoutubeDL({'outtmpl': '%(id)s%(ext)s'})
ydl.add_default_info_extractors()

exttype = {
	'mp3':	'audio/mp3',
	'm4a':	'video/mp4',
	'webm':	'video/webm'
}

class memottl(object):
	def __init__(self, ttl):
		self.cache = {}
		self.ttl = ttl
	def __call__(self, f):
		def wrapped_f(*args):
			now = time.time()
			try:
				value, last_update = self.cache[args]
				if self.ttl > 0 and now - last_update > self.ttl:
					raise AttributeError
				return value
			except (KeyError, AttributeError):
				value = f(*args)
				self.cache[args] = (value, now)
				return value
			except TypeError:
				return f(*args)
		return wrapped_f

def baseencode(number, alphabet='0123456789abcdefghijklmnopqrstuvwxyz'):
	if not isinstance(number, (int, long)):
	    raise TypeError('number must be an integer')
	result = ''
	sign = ''
	if number < 0:
	    sign = '-'
	    number = -number
	if 0 <= number < len(alphabet):
	    return sign + alphabet[number]
	while number != 0:
	    number, i = divmod(number, len(alphabet))
	    result = alphabet[i] + result
	return sign + result

def base32encode(number):
	return baseencode(number, '0123456789abcdefghjkmnpqrstvwxyz')

def hashhash(s, times=8):
	fn = hashlib.sha1
	salt = buffer(s)
	for i in xrange(times):
		s = fn(salt + s).digest()
	return 'sha1.' + str(times) + '.' + base32encode(int(s.encode('hex'), 16))

def filter_vidkey(vidkey):
	svc, subkey = vidkey.split(':', 1)
	if svc == 'youtube':
		return not not re.match(r'[^#\&\?]*$', subkey)
	elif svc == 'soundcloud':
		slashes = subkey.count('/')
		if slashes < 1:
			return not not re.match(r'[^#\&\?]*$', subkey)
		elif slashes < 2:
			return True

def denormalize(vidkey):
	svc, subkey = vidkey.split(':', 1)
	if svc == 'youtube':
		return 'http://www.youtube.com/watch?v=' + subkey
	if svc == 'soundcloud':
		if '/' in subkey:
			return 'http://soundcloud.com/' + subkey
		else:
			return 'http://snd.sc/' + subkey

@memottl(600)
def fetchdata(vidkey):
	svc, subkey = vidkey.split(':', 1)
	if svc == 'youtube':
		return fetchdata_youtube(vidkey)
	if svc == 'soundcloud':
		return fetchdata_soundcloud(vidkey)
def fetchdata_youtube(vidkey):
	try:
		result = ydl.extract_info(denormalize(vidkey), download=False)
	except youtube_dl.utils.DownloadError:
		return None
	if 'entries' in result:
		video = result['entries'][0]
	else:
		video = result
	formats = {}
	for fmt in video['formats']:
		if 'abr' in fmt:
			if fmt['ext'] not in formats:
				formats[fmt['ext']] = []
			formats[fmt['ext']].append((fmt['abr'], fmt['url']))
	for k in formats.keys():
		fmt = sorted(formats[k])[-1]
		formats[k] = {
			'ext':	k,
			'type':	exttype[k],
			'abr':	fmt[0],
			'url':	fmt[1]
		}
	return {
		'vidkey':	vidkey,
		'url':		denormalize(vidkey),
		'title':	video['title'],
		'format':	formats
	}
def fetchdata_soundcloud(vidkey):
	try:
		result = ydl.extract_info(denormalize(vidkey), download=False)
	except youtube_dl.utils.DownloadError:
		return None
	return {
		'vidkey':	vidkey,
		'url':		denormalize(vidkey),
		'title':	result['title'],
		'format':	{},
	}

class Playloop(object):
	def __init__(self):
		self.req = {}
		self.done = set()
		self.queue = ()
	def __iter__(self):
		return self
	def next(self):
		for vidkey, freq in self.queue:
			self.done.add(vidkey)
			data = fetchdata(vidkey)
			if data is not None:
				self.rehash()
				return vidkey
		return None
	def rehash(self):
		c = Counter()
		for v in self.req.itervalues():
			c.update(v)
		next = []
		later = []
		for i in c.most_common():
			if i[0] in self.done:
				later.append(i)
			else:
				next.append(i)
		if len(next) < 1:
			self.done.clear()
		self.queue = tuple(next + later)
	def request(self, key, value=None):
		if value is None or len(value) < 1:
			if key in self.req:
				del self.req[key]
				self.rehash()
				return True
			return False
		value = set(value)
		if key not in self.req or self.req[key] != value:
			self.req[key] = value
			self.rehash()
			return True
		return False
	def getkey(self, value):
		return (k for k, v in self.req.iteritems() if value in v)

class Channel(object):
	def __init__(self, namespace, name):
		self.namespace = namespace
		self.name = name
		self.sock = weakref.WeakSet()
		self.participant = {}
		self.nickname = {}
		self.set_stopped = set()
		self.quorum = 1
		self.playloop = Playloop()
		self.playing = None
		self.chathistory = deque(maxlen=16)
	def request(self, sock=None, req=None):
		if sock is not None and sock.session['userhash'] in self.participant:
			if self.playloop.request(sock.session['userhash'], req):
				self.emit('queue', {'queue': list(self.playloop.queue)})
		if self.playing is None:
			vidkey = self.playloop.next()
			if vidkey is not None:
				data = fetchdata(vidkey)
				if data is not None:
					self.set_stopped.clear()
					self.playing = {
						'vidkey':	data['vidkey'],
						'url':		data['url'],
						'title':	data['title'],
						'format':	data['format'],
						'requester':	list(self.playloop.getkey(vidkey)),
						'time':		time.time(),
					}
					self.emit('play', self.playing)
			self.emit('queue', {'queue': list(self.playloop.queue)})
	def stop(self, sock=None, vidkey=None):
		if sock is not None and self.playing is not None and self.playing['vidkey'] == vidkey and sock.session['userhash'] in self.participant:
			self.set_stopped.add(sock.session['userhash'])
		if len(self.set_stopped) >= self.quorum:
			print 'STOPPED', len(self.set_stopped)
			self.playing = None
			self.request()
	def rehash_quorum(self):
		try:
			self.quorum = int(max(1, math.ceil(math.log(len(self.participant)))))
		except ValueError:
			self.quorum = 1
		print 'quorum', self.quorum
	def join(self, sock):
		if 'channel' in sock.session and sock.session['channel'] is not None:
			sock.session['channel'].part(sock)
		userhash = sock.session['userhash']
		self.sock.add(sock)
		if userhash not in self.participant:
			self.participant[userhash] = weakref.WeakSet()
			self.emit('join', {'id': userhash})
		else:
			self.emit_one(sock, 'join', {'id': userhash})
		self.participant[userhash].add(sock)
		self.rehash_quorum()
		usernick = sock.session['usernick']
		if userhash not in self.nickname or usernick != self.nickname[userhash]:
			self.nickname[userhash] = usernick
			self.emit('nick', {'id': userhash, 'nick': usernick})
		else:
			self.emit_one(sock, 'nick', {'id': userhash, 'nick': usernick})
		sock.session['channel'] = self
		self.emit_one(sock, 'nicks', self.nickname)
		self.emit('queue', {'queue': list(self.playloop.queue)})
		if self.playing is not None:
			self.emit_one(sock, 'play', self.playing)
		self.emit_one(sock, 'chathistory', {'history': list(self.chathistory)})
		return sock
	def part(self, sock):
		try:
			self.sock.remove(sock)
			sock.session['channel'] = None
			userhash = sock.session['userhash']
			try:
				self.set_stopped.remove(userhash)
			except KeyError:
				pass
			try:
				self.participant[userhash].remove(sock)
				if len(self.participant[userhash]) < 1:
					del self.participant[userhash]
					self.rehash_quorum()
					del self.nickname[userhash]
					self.emit('part', {'id': userhash})
					if self.playloop.request(sock, None):
						self.emit('queue', {'queue': list(self.playloop.queue)})
					self.stop()
			except KeyError:
				pass
			return sock
		except KeyError:
			return None
	def nick(self, sock):
		userhash = sock.session['userhash']
		usernick = sock.session['usernick']
		if userhash in self.participant and usernick != self.nickname[userhash]:
			self.nickname[userhash] = usernick
			self.emit('nick', {'id': userhash, 'nick': usernick})
	def chat(self, sock, body):
		if sock is not None and sock.session['userhash'] in self.participant:
			userhash = sock.session['userhash']
			msg = {'time': time.time(), 'src': userhash, 'snick': self.nickname[userhash], 'playing': None if self.playing is None else self.playing['vidkey'], 'body': body}
			self.chathistory.appendleft(msg)
			self.emit('chat', msg)
	def emit(self, event, args):
		pkt = {
			'type':		'event',
			'name':		event,
			'args':		args,
			'endpoint':	self.namespace
		}
		for sock in self.sock:
			sock.send_packet(pkt)
	def emit_one(self, sock, event, args):
		sock.send_packet({
			'type':		'event',
			'name':		event,
			'args':		args,
			'endpoint':	self.namespace
		})

class SocketManager(BaseNamespace, BroadcastMixin, RoomsMixin):
	channel = weakref.WeakValueDictionary()
	def initialize(self):
		self.session['channel'] = None
	def channel_join(self, name):
		channel = None
		if name not in self.channel:
			channel = self.channel[name] = Channel(self.ns_name, name)
			print self, channel
		self.channel[name].join(self.socket)
	def channel_part(self):
		try:
			self.session['channel'].part(self.socket)
		except (KeyError, AttributeError):
			pass
	def recv_connect(self):
		print 'connect', self.socket.sessid
	def recv_disconnect(self):
		print 'disconnect', self.socket.sessid
		self.channel_part()
	def on_user(self, msg):
		if 'userhash' not in self.session:
			self.session['userhash'] = hashhash(msg['cid'])
			self.session['usernick'] = msg['nick']
			self.emit('user', {'id': self.session['userhash']})
	def on_nick(self, msg):
		if 'userhash' in self.session:
			self.session['usernick'] = msg['nick']
			try:
				channel = self.session['channel']
				if channel is None:
					return
			except KeyError:
				return
			channel.nick(self.socket)
	def on_join(self, msg):
		if 'userhash' in self.session:
			self.channel_join(msg)
	def on_tdelta(self, msg):
		self.emit('tdelta', time.time() - msg)
	def on_request(self, msg):
		if 'userhash' in self.session:
			try:
				channel = self.session['channel']
				if channel is None:
					return
			except KeyError:
				return
			req = set(vidkey for vidkey in msg if isinstance(vidkey, basestring) and filter_vidkey(vidkey))
			channel.request(self.socket, req)
	def on_stop(self, msg):
		if 'userhash' in self.session:
			try:
				channel = self.session['channel']
				if channel is None:
					return
			except KeyError:
				return
			channel.stop(self.socket, msg['vidkey'])
	def on_chat(self, msg):
		if 'userhash' in self.session:
			try:
				channel = self.session['channel']
				if channel is None:
					return
			except KeyError:
				return
			channel.chat(self.socket, msg['body'])

def appfactory():
	app = Bottle()
	app.debug = True

	@app.route('/c/<channel>')
	@app.route('/')
	def cb(channel=None):
		return static_file('index.htm', root='./www')

	@app.route('/now')
	def cb():
		return {
			'now':	time.time()
		}

	@app.get('/socket.io/socket.io.js')
	def cb():
		return static_file('socket.io/socket.io.js', root='./www')

	@app.get('/socket.io')
	@app.get('/socket.io/')
	@app.get('/socket.io/<path:path>')
	def cb(path=None):
		socketio_manage(bottle.request.environ, {'/channel': SocketManager}, bottle.request)

	@app.route('/<path:path>')
	def cb(path):
		return static_file(path, root='./www')

	return app

if __name__ == "__main__":
	bottle.run(
		app=appfactory(),
		host='',
		port=8100,
		server='geventSocketIO',
		debug=True,
		reloader=True,
	)
