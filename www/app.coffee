R = React.DOM

$.cookie.json = true

el = document.createElement 'a'
el.href = window.location.href
pathname = el.pathname.split '/'
channel = 'bluejam'
if pathname.length == 3
	if pathname[0] == '' and pathname[1] == 'c'
		channel = pathname[2].toLowerCase()

exttype =
	mp3:	'audio/mpeg'
	m4a:	'video/mp4'
	webm:	'video/webm'

time =
	tdelta: 0.0
	tdeltalist: []
	time: -> (new Date).getTime() / 1000
	synctime: -> (new Date).getTime() / 1000 + time.tdelta
	remote: (t) -> t + time.tdelta
	local: (t) -> t - time.tdelta

memottl = (fn, ttl) ->
	memo = {}
	->
		key = Array.prototype.join.call arguments, '§'
		if key of memo
			return memo[key]
		if ttl
			setTimeout (-> delete memo[key]), ttl
		return memo[key] = fn.apply @, arguments

normalize = (url) ->
	for name, fn of arguments.callee.fn
		k = fn url
		if k
			return k
normalize.fn =
	youtube: (url) ->
		regex = /^.*(youtu\.be\/|v\/|u\/\w\/|embed\/|watch\?v=|\&v=)([^#\&\?]*).*/
		match = url.match regex
		if match and match[2].length == 11
			'youtube:' + match[2]
	soundcloud: (url) ->
		match = url.match /^.*soundcloud.com\/([^\/]+)\/([^\/]+)$/
		if match
			return 'soundcloud:' + match[1] + '/' + match[2]
		match = url.match /^.*snd\.sc\/([^\/]+)$/
		if match
			return 'soundcloud:' + match[1]
normalize = _.memoize normalize

denormalize = (vidkey) ->
	vidkey = vidkey.split ':'
	arguments.callee.fn[vidkey[0]] vidkey[1]
denormalize.fn =
	youtube: (subkey) -> 'http://www.youtube.com/watch?v=' + subkey
	soundcloud: (subkey) -> if subkey.indexOf('/') < 0 then 'http://snd.sc/' + subkey else 'http://soundcloud.com/' + subkey
denormalize = _.memoize denormalize

fetchdata = (vidkey) ->
	[svc, subkey] = vidkey.split ':'
	arguments.callee.fn[svc] vidkey, svc, subkey
fetchdata.fn =
	youtube: (vidkey, svc, subkey) ->
		$.getJSON 'http://gdata.youtube.com/feeds/api/videos/' + subkey + '?v=2&alt=json&callback=?'
			.then (data) =>
				vidkey:		vidkey
				url:		denormalize vidkey
				title:		data.entry.title.$t
				duration:	data.entry.media$group.yt$duration.seconds
	soundcloud: (vidkey, svc, subkey) ->
		$.getJSON 'http://api.sndcdn.com/resolve?url=' + encodeURIComponent(denormalize vidkey) + '&format=json&client_id=YOUR_CLIENT_ID&callback=?'
			.then (artifact) =>
				if 'errors' of artifact
					return null
				$.getJSON artifact.uri + '/streams?format=json&client_id=YOUR_CLIENT_ID&callback=?'
					.then (formats) =>
						streams = {}
						for fmt, url of formats
							fmt = fmt.split '_'
							if fmt[0] == 'http'
								if fmt[1] not of streams
									streams[fmt[1]] = []
								streams[fmt[1]].push
									ext:	fmt[1]
									type:	exttype[fmt[1]]
									abr:	+fmt[2]
									url:	url
						for ext of streams
							streams[ext].sort (a, b) -> b.abr - a.abr
							streams[ext] = streams[ext][0]
						return {
							vidkey:		vidkey
							url:		artifact.permalink_url
							title:		artifact.title
							duration:	artifact.duration / 1000
							format:		streams
						}
fetchdata = memottl fetchdata, 300000	# 5 minutes

trim = (s) -> s.replace /^\s+|\s+$/g, ''

lpad = (n, width, z) ->
	z = z or '0'
	n = n + ''
	if n.length >= width then n else new Array(width - n.length + 1).join(z) + n

randomid = ->
	self = arguments.callee
	Math.floor(Math.random() * 9.007199e15).toString(32).replace /[ilou]/, (a) -> self.crockford[a]
randomid.crockford =
	i:	'w'
	l:	'x'
	o:	'y'
	u:	'z'

isInViewport = (el) ->
	if el instanceof jQuery
		el = el[0]
	rect = el.getBoundingClientRect()
	(
		(rect.top >= 0) and
		(rect.left >= 0) and
		(rect.bottom <= (window.innerHeight or document.documentElement.clientHeight)) and
		(rect.right <= (window.innerWidth or document.documentElement.clientWidth))
	)

NickInput = React.createClass
	render: ->
		R.div {className: 'input-group'},
			R.i
				className:	'input-group-addon glyphicon glyphicon-user'
			R.input
				type:		'text'
				className:	'form-control'
				onKeyUp:	(evt) =>
					if evt.keyCode == 27	# esc
						evt.target.value = ''
					else if evt.keyCode == 13	# enter
						val = trim evt.target.value
						if val.length > 0
							@sendNick val
							evt.target.value = ''
				placeholder:	@props.nick
	sendNick: (msg) ->
		@props.sock.emit 'nick',
			nick: msg

Navbar = React.createClass
	render: ->
		R.div {className: 'navbar navbar-default navbar-fixed-top', role: 'navigation'},
			R.div {className: 'container'},
				R.div {className: 'navbar-header'},
					R.button {className: 'navbar-toggle', type: 'button', 'data-toggle': 'collapse', 'data-target': '.navbar-collapse'},
						R.span {className: 'sr-only'}, 'Toggle navigation'
						R.span {className: 'icon-bar'}
						R.span {className: 'icon-bar'}
						R.span {className: 'icon-bar'}
					R.a {className: 'navbar-brand', href: '#'}, 'jam with friends'
				R.div {className: 'collapse navbar-collapse'},
					R.ul {className: 'nav navbar-nav'},
						for c in @props.channels
							R.li {className: if channel == c then 'active' else ''}, R.a {href: '/c/' + c}, c
					R.div {className: 'nav navbar-nav pull-right', style: {width: '12em'}},
						NickInput
							nick:	@props.nick
							sock:	@props.sock

Titleblock = React.createClass
	render: ->
		R.div null,
			R.h1 {style: {margin: '0'}},
				R.a {href: "/c/#{channel}"}, "#{channel}"
				if @props.connected then " | #{@props.count}" else ''
			R.h3 {style: {margin: '0'}},
				R.a {href: "/c/#{channel}"}, "#{window.location.host}/c/#{channel}"

PlayerHead = React.createClass
	getInitialState: ->
		title:		@props.vidkey
		minutes:	0
		seconds:	0
	componentDidMount: ->
		if @props.vidkey
			fetchdata @props.vidkey
				.done (data) =>
					@setState
						title:		data.title
						minutes:	parseInt data.duration / 60
						seconds:	parseInt Math.round data.duration % 60
	render: ->
		requested = @props.vidkey of @props.request
		document.title = "#{@state.title} - #{channel} - jam with friends"
		R.div {style: {margin: '0.15em auto', textAlign: 'center', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis'}},
			R.span {className: ('label label-' + if requested then 'success' else 'default'), style: {fontWeight: 'bold'}, onClick: (evt) => (if requested then @props.removeFavorite else @props.addFavorite) @props.vidkey},
				R.i
					className: 'glyphicon glyphicon-heart'
			' '
			R.span {className: 'label label-danger', style: {fontWeight: 'bold'}, onClick: (evt) => @props.skip()},
				R.i
					className: 'glyphicon glyphicon-remove'
			" #{@state.minutes}:#{lpad(@state.seconds, 2)} - "
			R.a {href: denormalize @props.vidkey, target: '_blank'},
				@state.title

PlayerAudio = React.createClass
	getInitialState: ->
		muted:	false
		volume:	1
		lastfmt:	null
	componentDidMount: ->
		self = @
		node = @getDOMNode()
		if self.props.vidkey
			v = self.props.getvolume()
			node.muted = v.muted
			node.volume = v.volume
			node.addEventListener 'stalled', -> @load()
			node.addEventListener 'ended', ->
				self.props.sock.emit 'stop',
					vidkey:	self.props.vidkey
					reason:	'end'
			node.addEventListener 'canplay', ->
				seek = time.synctime() - self.props.time
				if Math.abs(@currentTime - seek) > 1
					@currentTime = seek
				@play()
			node.addEventListener 'volumechange', -> self.props.setvolume @volume, @muted
			errback = (evt) ->
				if node.currentSrc == ''
					self.props.sock.emit 'stop',
						vidkey:	self.props.vidkey
						reason:	'error'
				else if node.networkState == 3
					console.log 'NETWORK_NO_SOURCE'
			node.addEventListener 'error', _.debounce(errback, 100), true
		else
			node.pause()
			node.currentTime = 0
	render: ->
		source = []
		if @props.vidkey
			for fmt in ['m4a', 'mp3', 'webm']
				if fmt of @props.format
					source.push R.source {src: @props.format[fmt].url, type: @props.format[fmt].type}
		R.audio {controls: 'controls', style: {width: '100%'}}, source

Player = React.createClass
	getInitialState: ->
		vidkey:	null
		title:	null
		format:	null
		time:	null
		muted:	false
		volume:	1
	componentDidMount: ->
		@props.sock.on 'play', (msg) =>
			fetchdata msg.vidkey
				.done (data) =>
					@setState
						vidkey:	data.vidkey
						title:	data.title
						format:	if 'format' of data then data.format else msg.format
						time:	msg.time
	render: ->
		document.title = "#{channel} - jam with friends"
		R.div null, if @state.vidkey then [
			PlayerHead
				key:	@state.vidkey + ':head'
				vidkey:	@state.vidkey
				skip:	@skip
				request:		@props.request
				addFavorite:	@props.addFavorite
				removeFavorite:	@props.removeFavorite
			PlayerAudio
				key:	@state.vidkey + ':audio'
				vidkey:	@state.vidkey
				format:	@state.format
				time:	@state.time
				getvolume:	@getvolume
				setvolume:	@setvolume
				sock:	@props.sock
		] else []
	getvolume: ->
		volume:	@state.volume
		muted:	@state.muted
	setvolume: (volume, muted) ->
		@setState
			volume:	volume
			muted:	muted
	skip: ->
		vidkey = @state.vidkey
		if vidkey
			@setState
				vidkey:	null
			@props.sock.emit 'stop',
				vidkey:	vidkey
				reason:	'skip'

PlaylistItem = React.createClass
	getInitialState: ->
		title:		@props.vidkey
		minutes:	0
		seconds:	0
	componentDidMount: ->
		fetchdata @props.vidkey
			.done (data) =>
				try
					@setState
						title:		data.title
						minutes:	parseInt data.duration / 60
						seconds:	parseInt Math.round data.duration % 60
				catch ex
	render: ->
		requested = @props.vidkey of @props.request
		enqueued = if 'frequency' of @props and 'threshold' of @props then @props.frequency >= @props.threshold else false
		R.tr {style: {margin: '0.5em auto'}},
			R.td {style: {width: '1em'}},
				R.span {className: ('label label-' + if requested then 'success' else 'default'), style: {fontWeight: 'bold'}, onClick: (evt) => (if requested then @props.removeFavorite else @props.addFavorite) @props.vidkey},
					R.i {className: 'glyphicon glyphicon-' + if enqueued then 'heart' else 'heart-empty'}
					if 'frequency' of @props then " #{@props.frequency}" else ' '
			R.td {style: {width: '1em', textAlign: 'right'}},
				R.span null, "#{@state.minutes}:#{lpad(@state.seconds, 2)}"
			R.td null,
				R.a {href: denormalize @props.vidkey, target: '_blank'},
					@state.title

Playlist = React.createClass
	getInitialState: ->
		query:		''
		resultset:	[]
		queue:		[]
		threshold:	0
		history:	[]
	componentDidMount: ->
		@props.sock.on 'queue', (msg) =>
			@setState
				queue:		msg.queue
				threshold:	msg.threshold
		@props.sock.on 'history', (msg) =>
			@setState
				history:	msg.play
		@props.sock.on 'played', (msg) =>
			history = @state.history
			idx = history.indexOf msg
			if idx >= 0
				history.splice idx, 1
			history.unshift msg
			while history.length > 16
				history.pop()
			@setState
				history:	history
	render: ->
		R.div null,
			R.div {className: 'input-group'},
				R.i
					className:	'input-group-addon glyphicon glyphicon-search'
				R.input
					type:		'text'
					className:	'form-control'
					onChange:	(evt) => @search evt.target.value
					onKeyUp:	(evt) =>
						if evt.keyCode == 27	# esc
							@searchclear()
						else if evt.keyCode == 13 and @state.resultset.length > 0	# enter
							vidkey = @state.resultset[0]
							if vidkey of @props.request
								@props.removeFavorite vidkey
							else
								@props.addFavorite vidkey
					placeholder:	'Search or URL: YouTube | SoundCloud'
					value:		@state.query
				R.div {className: 'input-group-btn'},
					R.button {className: 'btn btn-default', onClick: @searchclear},
						R.i
							className:	'glyphicon glyphicon-remove-circle'
			R.table {className: 'table', style: {display: (if @state.resultset.length > 0 then 'block' else 'none'), fontSize: '1em'}},
				R.tbody null,
					for item in @state.resultset
						PlaylistItem
							key:		item
							request:	@props.request
							vidkey: 	item
							addFavorite:	@props.addFavorite
							removeFavorite:	@props.removeFavorite
			if @state.queue.length > 0
				R.table {className: 'table', style: {fontSize: '1em'}},
					R.tbody null,
						for item in @state.queue
							PlaylistItem
								key:		item[0]
								request:	@props.request
								vidkey: 	item[0]
								frequency:	item[1]
								threshold:	@state.threshold
								addFavorite:	@props.addFavorite
								removeFavorite:	@props.removeFavorite
			else
				R.h3 {style: {textAlign: 'center'}},
					R.div null,
						'There are no requests, so I\'m playing random tracks.'
					R.div null,
						'Search YouTube using the bar above. Click '
						R.span {className: 'label label-default', style: {fontWeight: 'bold'}},
							R.i {className: 'glyphicon glyphicon-heart-empty'}
						' to request.'
			R.div null,
				'Click '
				R.span {className: 'label label-default', style: {fontWeight: 'bold'}},
					R.i {className: 'glyphicon glyphicon-heart'}
				' to request | Key: '
				R.span {className: 'label label-success', style: {fontWeight: 'bold'}},
					R.i {className: 'glyphicon glyphicon-heart'}
					' requested'
				' '
				R.span {className: 'label label-default', style: {fontWeight: 'bold'}},
					R.i {className: 'glyphicon glyphicon-heart'}
					' queued'
				' '
				R.span {className: 'label label-default', style: {fontWeight: 'bold'}},
					R.i {className: 'glyphicon glyphicon-heart-empty'}
					' needs requests'
			R.h1 {style: {display: (if @state.history.length > 0 then 'block' else 'none')}}, 'History'
			R.table {className: 'table', style: {display: (if @state.history.length > 0 then 'block' else 'none'), fontSize: '1em'}},
				R.tbody null,
					for item in @state.history
						PlaylistItem
							key:		item
							request:	@props.request
							vidkey: 	item
							addFavorite:	@props.addFavorite
							removeFavorite:	@props.removeFavorite
	search: (query) ->
		@setState
			query:	query
		query = trim query
		if query
			@searchexec query
		else
			@setState
				resultset: []
	searchclear: ->
		@search ''
	searchexec: _.debounce (query) ->
		vidkey = normalize query
		if vidkey
			@setState
				resultset: [vidkey]
		else
			$.getJSON 'http://gdata.youtube.com/feeds/api/videos?q=' + encodeURIComponent(query) + '&max-results=5&v=2&alt=json&callback=?'
				.then (data) =>
					if query == @state.query
						@setState
							resultset: (normalize result.link[0].href for result in data.feed.entry)
	, 500

Preset = React.createClass
	render: ->
		R.div null,
			R.button {className: 'btn btn-default', onClick: (evt) => @addRick()},
				'+Rick'
			' '
			R.button {className: 'btn btn-default', onClick: (evt) => @addKHS()},
				'+KHS'
			' '
			R.button {className: 'btn btn-default', onClick: (evt) => @addEDM()},
				'+EDM'
	addRick: ->
		@props.addFavorite 'youtube:dQw4w9WgXcQ'
		@props.addFavorite 'youtube:5zFh5euYntU'
	addKHS: ->
		@props.addFavorite 'youtube:a2RA0vsZXf8'
		@props.addFavorite 'youtube:n-BXNXvTvV4'
		@props.addFavorite 'youtube:6y1aOg_UO_A'
	addEDM: ->
		@props.addFavorite 'youtube:RIXcWo1DBSE'
		@props.addFavorite 'youtube:vIM3tVCi0wg'
		@props.addFavorite 'youtube:j5U8lXoW2EM'

ChatInput = React.createClass
	getInitialState: ->
		body:	''
	render: ->
		R.div {className: 'chatinput input-group'},
			R.input
				type:		'text'
				className:	'form-control'
				onChange:	(evt) => @setState
					body:	evt.target.value
				onKeyUp:	(evt) =>
					if evt.keyCode == 27	# esc
						@setState
							body:	''
					else if evt.keyCode == 13	# enter
						@sendChat()
				value:		@state.body
				placeholder:	'Send a message'
			R.div {className: 'input-group-btn'},
				R.button {className: 'btn btn-default', onClick: @sendChat},
					R.i
						className:	'glyphicon glyphicon-envelope'
	sendChat: ->
		val = trim @state.body
		if val.length > 0
			@props.sock.emit 'chat',
				body: val
			@setState
				body: ''

MessagelistItem = React.createClass
	getInitialState: ->
		title:		@props.playing
	componentDidMount: ->
		if @props.playing
			fetchdata @props.playing
				.done (data) =>
					@setState
						title:		data.title
	render: ->
		namebar = []
		if @props.snick
			namebar.push R.strong null, @props.snick
			namebar.push ' '
		if @props.playing
			namebar.push R.span {className: 'label label-default'},
				R.i
					className:	'glyphicon glyphicon-headphones'
				' '
				R.a {href: denormalize @props.playing, target: '_blank'}, @state.title
		R.div {className: 'row', style: {borderBottom: '1px solid #777'}},
			R.div {className: 'col-sm-2'},
				R.img
					src:	'http://robohash.org/' + @props.src + '.png?size=48x48'
			R.div {className: 'col-sm-10', style: {margin: '0.5em auto'}},
				R.div {style: {whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis'}}, namebar
				@props.body

Messagelist = React.createClass
	getInitialState: ->
		history:	[]
	componentDidMount: ->
		@props.sock.on 'history', (msg) =>
			$chatinput = $(@getDOMNode()).find('.chatinput')
			tailchat = isInViewport $chatinput
			msg.chat.reverse()
			@setState
				history:	msg.chat
			if tailchat
				$chatinput[0].scrollIntoView()
		@props.sock.on 'chat', (msg) =>
			$chatinput = $(@getDOMNode()).find('.chatinput')
			tailchat = isInViewport $chatinput
			@state.history.push msg
			while @state.history.length > 32
				@state.history.shift()
			@setState
				history:	@state.history
			if tailchat
				$chatinput[0].scrollIntoView()
	render: ->
		R.div null,
			R.h1 {style: {marginTop: '0'}}, 'Messages'
			R.div null,
				for msg in @state.history
					MessagelistItem
						key:	msg.src + msg.time + msg.body
						time:	msg.time
						src:	msg.src
						snick:	msg.snick
						playing:	msg.playing
						body:	msg.body
			ChatInput
				sock:	@props.sock

App = React.createClass
	getInitialState: ->
		r =
			sock:	null
			id:		''
			cid:		randomid()
			nick:		'User'
			connected:	false
			favorite:	[]
			nickname:	{}
			channels:	[]
			lastpersist:	0
		jam = $.cookie 'jam.' + @props.channel
		if jam and jam.v >= 1
			r.favorite = jam.f
			if jam.t
				r.lastpersist = jam.t
			if jam.cid
				r.cid = jam.cid
			if jam.nick
				r.nick = jam.nick
		r
	persist: ->
		$.cookie 'jam.' + @props.channel, {v: 1, t: time.time(), cid: @state.cid, nick: @state.nick, f: @state.favorite}, {expires: 14}
	sendRequest: ->
		@state.sock.emit 'tdelta', time.time()
		@state.sock.emit 'request', @state.favorite
	addFavorite: (vidkey, propagate=true) ->
		idx = @state.favorite.indexOf vidkey
		if idx < 0
			@state.favorite.push vidkey
			@setState
				favorite:	@state.favorite
			if propagate
				@sendRequest()
			@persist()
	removeFavorite: (vidkey, propagate=true) ->
		idx = @state.favorite.indexOf vidkey
		if idx >= 0
			@state.favorite.splice idx, 1
			@setState
				favorite:	@state.favorite
			if propagate
				@sendRequest()
			@persist()
	setupSock: ->
		sock = io.connect('/channel')
		sock.on 'connect', =>
			@persist()
			@setState
				connected:	true
			sock.emit 'user',
				cid:	@state.cid
				nick:	@state.nick
			sock.emit 'join', channel
			@sendRequest()
		sock.on 'disconnect', =>
			@setState
				connected:	false
		sock.on 'user', (msg) =>
			@setState
				id:	msg.id
		sock.on 'tdelta', (msg) ->
			time.tdeltalist.push msg
			time.tdelta = (time.tdeltalist.reduce (a, b) -> a + b) / time.tdeltalist.length
		sock.on 'nicks', (msg) =>
			@setState
				nickname:	msg
		sock.on 'join', (msg) =>
			@state.nickname[msg.id] = 'User'
			@setState
				nickname:	@state.nickname
		sock.on 'part', (msg) =>
			delete @state.nickname[msg.id]
			@setState
				nickname:	@state.nickname
		sock.on 'nick', (msg) =>
			@state.nickname[msg.id] = msg.nick
			@setState
				nickname:	@state.nickname
			if msg.id == @state.id
				@setState
					nick:	msg.nick
				@persist()
		sock.on 'play', =>
			@persist()
		@setState
			sock:	sock
	componentDidMount: ->
		if time.time() - @state.lastpersist < 900
			@setupSock()
		$.getJSON '/a/recentchannels', (data) =>
			@setState
				channels:	data.channels
	render: ->
		request = {}
		request[i] = true for i in @state.favorite
		count = 0
		for k of @state.nickname
			count++
		R.div null,
			Navbar
				nick:	@state.nick
				channels:	@state.channels
				sock:	@state.sock
			if @state.sock
				R.div {className: 'container'},
					R.div {className: 'row'},
						R.div {id: 'left', className: 'col-md-8'},
							R.div {className: 'row', style: {marginBottom: '1.2em'}},
								R.div {className: 'col-md-6'},
									Titleblock
										connected:	@state.connected
										count:		count
								R.div {className: 'col-md-6', style: {marginTop: '0.5em'}},
									Player
										request:		request
										addFavorite:	@addFavorite
										removeFavorite:	@removeFavorite
										sock:			@state.sock
							R.div {className: 'row'},
								R.div {className: 'col-md-12'},
									Playlist
										request:		request
										addFavorite:	@addFavorite
										removeFavorite:	@removeFavorite
										sock:			@state.sock
							R.div {className: 'row'},
								R.div {className: 'col-md-12'},
									Preset
										addFavorite:	@addFavorite
						R.div {id: 'right', className: 'col-md-4'},
							Messagelist
								nick:		@state.nick
								sock:		@state.sock
			else
				R.div {className: 'container'},
					R.h2 {style: {textAlign: 'center'}},
						R.button {className: 'btn btn-success', onClick: @setupSock},
							R.span {style: {fontSize: '3em'}}, "#{window.location.host}/c/#{channel}"
							R.br null
							R.span {style: {fontSize: '2em', fontWeight: 'bold'}}, 'click to jam with friends'
					R.h2 {style: {textAlign: 'center'}}, 'what is this?'
					R.div {className: 'row'},
						R.div {className: 'col-lg-4 col-lg-offset-4 col-md-6 col-md-offset-4 col-sm-8 col-sm-offset-3'},
							R.div {style: {fontSize: '1.25em'}},
								R.div null,
									R.i {className: 'glyphicon glyphicon-refresh'}
									' Synchronize online music with friends!'
								R.div null,
									R.i {className: 'glyphicon glyphicon-music'}
									' Request from YouTube and SoundCloud'
								R.div null,
									R.i {className: 'glyphicon glyphicon-heart'}
									' Upvote your favorites'
					R.h2 {style: {textAlign: 'center'}}, 'works best with'
					R.div {style: {textAlign: 'center'}},
						R.a {title: 'Google Chrome', href: 'https://www.google.com/chrome/', target: '_blank'},
							R.img
								alt: 'Google Chrome'
								src: 'https://raw.githubusercontent.com/alrra/browser-logos/master/chrome/chrome_128x128.png'
						R.a {title: 'Mozilla Firefox', href: 'https://www.mozilla.org/firefox/', target: '_blank'},
							R.img
								alt: 'Mozilla Firefox'
								src: 'https://raw.githubusercontent.com/alrra/browser-logos/master/firefox/firefox_128x128.png'
						R.a {title: 'Apple Safari', href: 'https://www.apple.com/safari/', target: '_blank'},
							R.img
								alt: 'Apple Safari'
								src: 'https://raw.githubusercontent.com/alrra/browser-logos/master/safari/safari_128x128.png'
					R.div {style: {textAlign: 'center', fontStyle: 'italic'}}, 'codec support may vary'

React.renderComponent App({channel: channel}), document.getElementById 'app'
