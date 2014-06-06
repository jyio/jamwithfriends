#!/usr/bin/env python

import re
import json
import math
import time
import hashlib
import sqlite3
import weakref

from collections import Counter, deque

try:
	import cPickle as pickle
except ImportError:
	import pickle

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

def median(data):
	data = sorted(data)
	n = len(data)
	if n % 2:
		return data[(n + 1) / 2 - 1]
	else:
		return (data[n / 2 - 1] + data[n / 2]) / 2.

class DataStore(object):
	def __init__(self, database=':memory:'):
		self.db = db = sqlite3.connect(database)
		db.row_factory = sqlite3.Row
		with db:
			db.execute('CREATE TABLE IF NOT EXISTS queuestate (time REAL, dst TEXT, track TEXT, state BLOB)')
			db.execute('CREATE INDEX IF NOT EXISTS idx_queuestate ON queuestate (dst, time)')
			db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_queuestate_unique ON queuestate (dst)')
			db.execute('CREATE TABLE IF NOT EXISTS play (time REAL, dst TEXT, track TEXT)')
			db.execute('CREATE INDEX IF NOT EXISTS idx_play ON play (dst, track, time)')
			db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_play_unique ON play (dst, track)')
			db.execute('CREATE TABLE IF NOT EXISTS chat (time REAL, dst TEXT, src TEXT, snick TEXT, playing TEXT, body TEXT)')
			db.execute('CREATE INDEX IF NOT EXISTS idx_chat ON chat (dst, time)')
	def store_queuestate(self, dst, now, track, state):
		with self.db as db:
			db.execute('INSERT OR REPLACE INTO queuestate (time, dst, track, state) values (?, ?, ?, ?)', (
				now,
				dst,
				track,
				sqlite3.Binary(pickle.dumps(state, pickle.HIGHEST_PROTOCOL))
			))
	def recall_queuestate(self, dst):
		r = self.db.cursor().execute('SELECT state FROM queuestate WHERE dst=? AND ?-time < 900 ORDER BY time DESC', (dst, time.time())).fetchone()
		if r is not None:
			return pickle.loads(str(r['state']))
	def store_play(self, dst, track):
		with self.db as db:
			db.execute('INSERT OR REPLACE INTO play (time, dst, track) values (?, ?, ?)', (
				time.time(),
				dst,
				track
			))
	def recall_play(self, dst, limit=None):
		if limit is None:
			res = self.db.execute('SELECT * FROM play WHERE dst=? AND ?-time < 604800 ORDER BY time DESC', (dst, time.time()))
		else:
			res = self.db.execute('SELECT * FROM play WHERE dst=? AND ?-time < 604800 ORDER BY time DESC LIMIT ?', (dst, time.time(), limit))
		return (r['track'] for r in res)
	def store_chat(self, payload):
		with self.db as db:
			db.execute('INSERT INTO chat (time, dst, src, snick, playing, body) values (?, ?, ?, ?, ?, ?)', (
				payload['time'],
				payload['dst'],
				payload['src'],
				payload['snick'],
				payload['playing'],
				payload['body']
			))
	def recall_chat(self, dst, limit=None):
		if limit is None:
			res = self.db.execute('SELECT * FROM chat WHERE dst=? AND ?-time < 86400 ORDER BY time DESC', (dst, time.time()))
		else:
			res = self.db.execute('SELECT * FROM chat WHERE dst=? AND ?-time < 86400 ORDER BY time DESC LIMIT ?', (dst, time.time(), limit))
		return (dict(r) for r in res)
	def recall_channel(self, limit=None):
		if limit is None:
			res = self.db.execute('SELECT DISTINCT dst FROM play WHERE ?-time < 604800 ORDER BY time DESC', (time.time(),))
		else:
			res = self.db.execute('SELECT DISTINCT dst FROM play WHERE ?-time < 604800 ORDER BY time DESC LIMIT ?', (time.time(), limit))
		return (r['dst'] for r in res)

class Playloop(object):
	def __init__(self, datastore, name):
		self.datastore = datastore
		self.name = name
		self.req = {}
		self.count = Counter()
		self.done = set()
		self.queue = ()
		self.threshold = 0
		self.current = None
	def __iter__(self):
		return self
	def store(self):
		state = {
			'current':	self.current,
			'done':		self.done
		}
		self.datastore.store_queuestate(self.name, self.current['time'] if self.current is not None else time.time(), self.current['vidkey'] if self.current is not None else None, state)
	def recall(self):
		state = self.datastore.recall_queuestate(self.name)
		if state is not None:
			self.done = set(state['done'])
			if state['current'] is not None:
				self.current = dict(state['current'])
			else:
				self.current = None
	def next(self):
		for vidkey, freq in self.queue:
			if freq < self.threshold:
				continue
			self.done.add(vidkey)
			data = fetchdata(vidkey)
			if data is not None:
				self.rehash()
				self.current = {
					'vidkey':	data['vidkey'],
					'url':		data['url'],
					'title':	data['title'],
					'format':	data['format'],
					'requester':	list(self.getkey(vidkey)),
					'time':		time.time(),
				}
				return self.current
		return None
	def reset(self):
		self.current = None
	def rehash(self):
		next = []
		later = []
		never = []
		for i in self.count.most_common():
			if i[1] >= self.threshold:
				if i[0] in self.done:
					later.append(i)
				else:
					next.append(i)
			else:
				never.append(i)
		if len(next) < 1:
			self.done.clear()
		self.queue = tuple(next + later + never)
	def request(self, key, value=None):
		if value is not None:
			value = set(value)
		if key in self.req:
			if self.req[key] != value:
				self.count.subtract(self.req[key])
			else:
				return False
		elif value is None:
			return False
		if value is not None:
			self.count.update(value)
			self.req[key] = value
		else:
			del self.req[key]
		self.count += Counter()
		self.threshold = median(i[1] for i in self.count.most_common()) if len(self.count) > 0 else 0
		self.rehash()
		return True
	def getkey(self, value):
		return (k for k, v in self.req.iteritems() if value in v)

class Channel(object):
	def __init__(self, datastore, namespace, name):
		self.datastore = datastore
		self.namespace = namespace
		self.name = name
		self.sock = weakref.WeakSet()
		self.participant = {}
		self.nickname = {}
		self.set_stopped = {}
		self.quorum = 1
		self.playloop = Playloop(self.datastore, self.name)
		self.playloop.recall()
	def request(self, sock=None, req=None):
		current = self.playloop.current
		if sock is not None and sock.session['userhash'] in self.participant:
			if self.playloop.request(sock.session['userhash'], req):
				self.emit('queue', {'queue': list(self.playloop.queue), 'threshold': self.playloop.threshold})
		if current is None:
			current = self.playloop.next()
			if current is not None:
				self.set_stopped.clear()
				self.playloop.store()
				self.emit('play', current)
			self.emit('queue', {'queue': list(self.playloop.queue), 'threshold': self.playloop.threshold})
	def stop(self, sock=None, vidkey=None, reason=None):
		current = self.playloop.current
		if sock is not None and current is not None and current['vidkey'] == vidkey and sock.session['userhash'] in self.participant:
			self.set_stopped[sock.session['userhash']] = reason
		if len(self.set_stopped) >= self.quorum:
			if self.playloop.current is not None:
				for i in self.set_stopped.itervalues():
					if i == 'end':
						self.datastore.store_play(self.name, current['vidkey'])
						self.emit('played', current['vidkey'])
						break
			self.playloop.reset()
			self.request()
	def rehash_quorum(self):
		try:
			self.quorum = int(max(1, math.ceil(math.log(len(self.participant)))))
		except ValueError:
			self.quorum = 1
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
		self.emit_one(sock, 'queue', {'queue': list(self.playloop.queue), 'threshold': self.playloop.threshold})
		if self.playloop.current is not None:
			self.emit_one(sock, 'play', self.playloop.current)
		self.emit_one(sock, 'history', {
			'play':	list(self.datastore.recall_play(self.name, 16)),
			'chat':	list(self.datastore.recall_chat(self.name, 16))
		})
		return sock
	def part(self, sock):
		try:
			self.sock.remove(sock)
			sock.session['channel'] = None
			userhash = sock.session['userhash']
			try:
				del self.set_stopped[userhash]
			except KeyError:
				pass
			try:
				self.participant[userhash].remove(sock)
				if len(self.participant[userhash]) < 1:
					del self.participant[userhash]
					self.rehash_quorum()
					del self.nickname[userhash]
					self.emit('part', {'id': userhash})
					if self.playloop.request(sock.session['userhash'], None):
						self.emit('queue', {'queue': list(self.playloop.queue), 'threshold': self.playloop.threshold})
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
			msg = {'time': time.time(), 'dst': self.name, 'src': userhash, 'snick': self.nickname[userhash], 'playing': None if self.playloop.current is None else self.playloop.current['vidkey'], 'body': body}
			self.emit('chat', msg)
			self.datastore.store_chat(msg)
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

class SocketManager(BaseNamespace):
	datastore = DataStore('./data.sqlite')
	channel = weakref.WeakValueDictionary()
	def initialize(self):
		self.session['channel'] = None
	def channel_join(self, name):
		channel = None
		if name not in self.channel:
			channel = self.channel[name] = Channel(self.datastore, self.ns_name, name)
		self.channel[name].join(self.socket)
	def channel_part(self):
		try:
			self.session['channel'].part(self.socket)
		except (KeyError, AttributeError):
			pass
	def recv_disconnect(self):
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
			channel.stop(self.socket, msg['vidkey'], msg['reason'])
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

	@app.get('/socket.io/socket.io.js')
	def cb():
		return static_file('socket.io/socket.io.js', root='./www')

	@app.route('/a/recentchannels')
	def cb():
		return {
			'channels':	list(SocketManager.datastore.recall_channel(8))
		}

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
