R = React.DOM

$.cookie.json = true

el = document.createElement 'a'
el.href = window.location.href
pathname = el.pathname.split '/'
channel = 'bluejam'
if pathname.length == 3
	if pathname[0] == '' and pathname[1] == 'c'
		channel = pathname[2].toLowerCase()

sock = null

sock = io.connect('/channel')

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
					className: 'glyphicon glyphicon-' + if requested then 'heart' else 'heart-empty'
			' '
			R.span {className: 'label label-danger', style: {fontWeight: 'bold'}, onClick: (evt) => @props.skip()},
				R.i
					className: 'glyphicon glyphicon-remove'
			" #{@state.minutes}:#{lpad(@state.seconds, 2)} - "
			R.a {href: denormalize @props.vidkey, target: '_blank'},
				R.span {style: {color: '#fff'}}, @state.title

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
			node.addEventListener 'canplay', ->
				@removeEventListener 'canplay', arguments.callee
				@addEventListener 'ended', ->
					sock.emit 'stop',
						vidkey:	self.props.vidkey
						reason:	'end'
				@currentTime = time.synctime() - self.props.time
				@play()
			node.addEventListener 'volumechange', -> self.props.setvolume @volume, @muted
			errback = (evt) ->
				if node.currentSrc == ''
					sock.emit 'stop',
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
		sock.on 'play', (msg) =>
			fetchdata msg.vidkey
				.done (data) =>
					@setState
						vidkey:	null
					_.defer =>
						@setState
							vidkey:	data.vidkey
							title:	data.title
							format:	if 'format' of data then data.format else msg.format
							time:	msg.time
	render: ->
		document.title = "#{channel} - jam with friends"
		R.div null, if @state.vidkey then [
			PlayerHead
				vidkey:	@state.vidkey
				skip:	@skip
				request:		@props.request
				addFavorite:	@props.addFavorite
				removeFavorite:	@props.removeFavorite
			PlayerAudio
				vidkey:	@state.vidkey
				format:	@state.format
				time:	@state.time
				getvolume:	@getvolume
				setvolume:	@setvolume
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
			sock.emit 'stop',
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
		R.tr {style: {margin: '0.5em auto'}},
			R.td {style: {width: '1em'}},
				R.span {className: ('label label-' + if requested then 'success' else 'default'), style: {fontWeight: 'bold'}, onClick: (evt) => (if requested then @props.removeFavorite else @props.addFavorite) @props.vidkey},
					R.i {className: 'glyphicon glyphicon-' + if requested then 'heart' else 'heart-empty'}
					if 'frequency' of @props then " #{@props.frequency}" else ' '
			R.td {style: {width: '1em', textAlign: 'right'}},
				R.span null, "#{@state.minutes}:#{lpad(@state.seconds, 2)}"
			R.td null,
				R.a {href: denormalize @props.vidkey, target: '_blank'},
					@state.title

Playlist = React.createClass
	getInitialState: ->
		query:	''
		resultset: []
		queue:	[]
	componentDidMount: ->
		sock.on 'queue', (msg) =>
			@setState
				queue:	msg.queue
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
			R.table {className: 'table', style: {fontSize: '1em'}},
				R.tbody null,
					for item in @state.queue
						PlaylistItem
							key:		item[0]
							request:	@props.request
							vidkey: 	item[0]
							frequency:	item[1]
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
				@state.title
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
		sock.on 'chathistory', (msg) =>
			@setState
				history:	msg.history
		sock.on 'chat', (msg) =>
			@state.history.unshift msg
			while @state.history.length > 32
				@state.history.pop()
			@setState
				history:	@state.history
	render: ->
		R.div null,
			R.div {className: 'row'},
				R.div {className: 'col-md-6'},
					R.h1 {style: {marginTop: '0'}}, 'Messages'
				R.div {className: 'col-md-6'},
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
			R.div {className: 'input-group'},
				R.i
					className:	'input-group-addon glyphicon glyphicon-envelope'
				R.input
					type:		'text'
					className:	'form-control'
					onKeyUp:	(evt) =>
						if evt.keyCode == 27	# esc
							evt.target.value = ''
						else if evt.keyCode == 13	# enter
							val = trim evt.target.value
							if val.length > 0
								@sendChat val
								evt.target.value = ''
					placeholder:	'Send a message'
			R.div null,
				for msg in @state.history
					MessagelistItem
						time:	msg.time
						src:	msg.src
						snick:	msg.snick
						playing:	msg.playing
						body:	msg.body
	sendNick: (msg) ->
		sock.emit 'nick',
			nick: msg
	sendChat: (msg) ->
		sock.emit 'chat',
			body: msg

App = React.createClass
	getInitialState: ->
		r =
			id:		''
			cid:		randomid()
			nick:		'User'
			connected:	false
			favorite:	[]
			nickname:	{}
		jam = $.cookie 'jam.' + @props.channel
		if jam and jam.v >= 1
			r.favorite = jam.f
			if jam.cid
				r.cid = jam.cid
			if jam.nick
				r.nick = jam.nick
		r
	persist: ->
		$.cookie 'jam.' + @props.channel, {v: 1, cid: @state.cid, nick: @state.nick, f: @state.favorite}, {expires: 14}
	sendRequest: ->
		sock.emit 'tdelta', time.time()
		sock.emit 'request', @state.favorite
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
	componentDidMount: ->
		@persist()
		@sendRequest()
		sock.on 'connect', =>
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
	render: ->
		request = {}
		request[i] = true for i in @state.favorite
		count = 0
		for k of @state.nickname
			count++
		R.div null,
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
							for c in ['bluejam', 'thh', 'epiccyndaquil', 'mop', 'pwnna', 'crispy']
								R.li {className: if channel == c then 'active' else ''}, R.a {href: '/c/' + c}, c
			R.div {className: 'container'},
				R.div {className: 'row'},
					R.div {className: 'col-md-8'},
						R.div {className: 'row', style: {marginBottom: '1.2em'}},
							R.div {className: 'col-md-6'},
								R.h1 {style: {margin: '0'}},
									R.a {href: "/c/#{channel}", style: {color: '#fff'}}, "#{channel}"
									if @state.connected then " | #{count}" else ''
								R.h3 {style: {margin: '0'}},
									R.a {href: "/c/#{channel}", style: {color: '#fff'}}, "#{window.location.host}/c/#{channel}"
							R.div {className: 'col-md-6', style: {marginTop: '0.5em'}},
								Player
									request:		request
									addFavorite:	@addFavorite
									removeFavorite:	@removeFavorite
						R.div {className: 'row'},
							R.div {className: 'col-md-12'},
								Playlist
									request:		request
									addFavorite:	@addFavorite
									removeFavorite:	@removeFavorite
						R.div {className: 'row'},
							R.div {className: 'col-md-12'},
								Preset
									addFavorite:	@addFavorite
					R.div {className: 'col-md-4'},
						Messagelist
							nick:		@state.nick

React.renderComponent App({channel: channel}), document.getElementById 'app'
