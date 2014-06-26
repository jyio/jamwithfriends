// Generated by CoffeeScript 1.7.1
var App, ChatInput, Listenerlist, Messagelist, MessagelistItem, Navbar, NickInput, Player, Playlist, PlaylistItem, Preset, R, Titleblock, channel, denormalize, exttype, fetchdata, isInViewport, isMobile, lpad, memottl, normalize, pathname, randomid, time, trim;

R = React.DOM;

$.cookie.json = true;

pathname = window.location.pathname.split('/');

channel = 'bluejam';

if (pathname.length === 3) {
  if (pathname[0] === '' && pathname[1] === 'c') {
    channel = pathname[2].toLowerCase();
  }
}

exttype = {
  mp3: 'audio/mpeg',
  m4a: 'video/mp4',
  webm: 'video/webm'
};

time = {
  tdelta: 0.0,
  tdeltalist: [],
  time: function() {
    return (new Date).getTime() / 1000;
  },
  synctime: function() {
    return (new Date).getTime() / 1000 + time.tdelta;
  },
  remote: function(t) {
    return t + time.tdelta;
  },
  local: function(t) {
    return t - time.tdelta;
  }
};

memottl = function(fn, ttl) {
  var memo;
  memo = {};
  return function() {
    var key;
    key = Array.prototype.join.call(arguments, '§');
    if (key in memo) {
      return memo[key];
    }
    if (ttl) {
      setTimeout((function() {
        return delete memo[key];
      }), ttl);
    }
    return memo[key] = fn.apply(this, arguments);
  };
};

normalize = function(url) {
  var fn, k, name, _ref;
  _ref = arguments.callee.fn;
  for (name in _ref) {
    fn = _ref[name];
    k = fn(url);
    if (k) {
      return k;
    }
  }
};

normalize.fn = {
  youtube: function(url) {
    var match, regex;
    regex = /^.*(youtu\.be\/|v\/|u\/\w\/|embed\/|watch\?v=|\&v=)([^#\&\?]*).*/;
    match = url.match(regex);
    if (match && match[2].length === 11) {
      return 'youtube:' + match[2];
    }
  },
  soundcloud: function(url) {
    var match;
    match = url.match(/^.*soundcloud.com\/([^\/]+)\/([^\/]+)$/);
    if (match) {
      return 'soundcloud:' + match[1] + '/' + match[2];
    }
    match = url.match(/^.*snd\.sc\/([^\/]+)$/);
    if (match) {
      return 'soundcloud:' + match[1];
    }
  }
};

normalize = _.memoize(normalize);

denormalize = function(vidkey) {
  vidkey = vidkey.split(':');
  return arguments.callee.fn[vidkey[0]](vidkey[1]);
};

denormalize.fn = {
  youtube: function(subkey) {
    return 'http://www.youtube.com/watch?v=' + subkey;
  },
  soundcloud: function(subkey) {
    if (subkey.indexOf('/') < 0) {
      return 'http://snd.sc/' + subkey;
    } else {
      return 'http://soundcloud.com/' + subkey;
    }
  }
};

denormalize = _.memoize(denormalize);

fetchdata = function(vidkey) {
  var subkey, svc, _ref;
  _ref = vidkey.split(':'), svc = _ref[0], subkey = _ref[1];
  return arguments.callee.fn[svc](vidkey, svc, subkey);
};

fetchdata.fn = {
  youtube: function(vidkey, svc, subkey) {
    return $.getJSON('http://gdata.youtube.com/feeds/api/videos/' + subkey + '?v=2&alt=json&callback=?').then((function(_this) {
      return function(data) {
        return {
          vidkey: vidkey,
          url: denormalize(vidkey),
          title: data.entry.title.$t,
          duration: data.entry.media$group.yt$duration.seconds
        };
      };
    })(this));
  },
  soundcloud: function(vidkey, svc, subkey) {
    return $.getJSON('http://api.sndcdn.com/resolve?url=' + encodeURIComponent(denormalize(vidkey)) + '&format=json&client_id=YOUR_CLIENT_ID&callback=?').then((function(_this) {
      return function(artifact) {
        if ('errors' in artifact) {
          return null;
        }
        return $.getJSON(artifact.uri + '/streams?format=json&client_id=YOUR_CLIENT_ID&callback=?').then(function(formats) {
          var ext, fmt, streams, url;
          streams = {};
          for (fmt in formats) {
            url = formats[fmt];
            fmt = fmt.split('_');
            if (fmt[0] === 'http') {
              if (!(fmt[1] in streams)) {
                streams[fmt[1]] = [];
              }
              streams[fmt[1]].push({
                ext: fmt[1],
                type: exttype[fmt[1]],
                abr: +fmt[2],
                url: url
              });
            }
          }
          for (ext in streams) {
            streams[ext].sort(function(a, b) {
              return b.abr - a.abr;
            });
            streams[ext] = streams[ext][0];
          }
          return {
            vidkey: vidkey,
            url: artifact.permalink_url,
            title: artifact.title,
            duration: artifact.duration / 1000,
            format: streams
          };
        });
      };
    })(this));
  }
};

fetchdata = memottl(fetchdata, 300000);

trim = function(s) {
  return s.replace(/^\s+|\s+$/g, '');
};

lpad = function(n, width, z) {
  z = z || '0';
  n = n + '';
  if (n.length >= width) {
    return n;
  } else {
    return new Array(width - n.length + 1).join(z) + n;
  }
};

randomid = function() {
  var self;
  self = arguments.callee;
  return Math.floor(Math.random() * 9.007199e15).toString(32).replace(/[ilou]/, function(a) {
    return self.crockford[a];
  });
};

randomid.crockford = {
  i: 'w',
  l: 'x',
  o: 'y',
  u: 'z'
};

isInViewport = function(el) {
  var rect;
  if (el instanceof jQuery) {
    el = el[0];
  }
  rect = el.getBoundingClientRect();
  return (rect.top >= 0) && (rect.left >= 0) && (rect.bottom <= (window.innerHeight || document.documentElement.clientHeight)) && (rect.right <= (window.innerWidth || document.documentElement.clientWidth));
};

isMobile = function() {
  var agent;
  agent = navigator.userAgent;
  if (/Android/i.test(agent)) {
    return 'android';
  } else if (/BlackBerry/i.test(agent)) {
    return 'blackberry';
  } else if (/iPhone|iPad|iPod/i.test(agent)) {
    return 'ios';
  } else if (/IEMobile/i.test(agent)) {
    return 'windows';
  } else {
    return null;
  }
};

NickInput = React.createClass({
  render: function() {
    return R.div({
      className: 'input-group'
    }, R.i({
      className: 'input-group-addon glyphicon glyphicon-user'
    }), R.input({
      type: 'text',
      className: 'form-control',
      onKeyUp: (function(_this) {
        return function(evt) {
          var val;
          if (evt.keyCode === 27) {
            return evt.target.value = '';
          } else if (evt.keyCode === 13) {
            val = trim(evt.target.value);
            if (val.length > 0) {
              _this.sendNick(val);
              return evt.target.value = '';
            }
          }
        };
      })(this),
      placeholder: this.props.nick
    }));
  },
  sendNick: function(msg) {
    return this.props.sock.emit('nick', {
      nick: msg
    });
  }
});

Navbar = React.createClass({
  render: function() {
    var c;
    return R.div({
      className: 'navbar navbar-default navbar-fixed-top',
      role: 'navigation'
    }, R.div({
      className: 'container'
    }, R.div({
      className: 'navbar-header'
    }, R.button({
      className: 'navbar-toggle',
      type: 'button',
      'data-toggle': 'collapse',
      'data-target': '.navbar-collapse'
    }, R.span({
      className: 'sr-only'
    }, 'Toggle navigation'), R.span({
      className: 'icon-bar'
    }), R.span({
      className: 'icon-bar'
    }), R.span({
      className: 'icon-bar'
    })), R.a({
      className: 'navbar-brand',
      href: '#'
    }, 'jam with friends')), R.div({
      className: 'collapse navbar-collapse'
    }, R.ul({
      className: 'nav navbar-nav'
    }, (function() {
      var _i, _len, _ref, _results;
      _ref = this.props.channels;
      _results = [];
      for (_i = 0, _len = _ref.length; _i < _len; _i++) {
        c = _ref[_i];
        _results.push(R.li({
          className: channel === c ? 'active' : ''
        }, R.a({
          href: '/c/' + c
        }, c)));
      }
      return _results;
    }).call(this)), R.div({
      className: 'nav navbar-nav pull-right',
      style: {
        width: '12em'
      }
    }, NickInput({
      nick: this.props.nick,
      sock: this.props.sock
    })))));
  }
});

Listenerlist = React.createClass({
  getInitialState: function() {
    return {
      requester: []
    };
  },
  componentDidMount: function() {
    return this.props.sock.on('play', (function(_this) {
      return function(msg) {
        return _this.setState({
          requester: msg.requester
        });
      };
    })(this));
  },
  render: function() {
    var src;
    if (this.state.requester.length > 0) {
      return R.div(null, (function() {
        var _i, _len, _ref, _results;
        _ref = this.state.requester;
        _results = [];
        for (_i = 0, _len = _ref.length; _i < _len; _i++) {
          src = _ref[_i];
          _results.push(R.img({
            key: src,
            src: 'http://robohash.org/' + src + '.png?size=32x32'
          }));
        }
        return _results;
      }).call(this));
    } else {
      return R.h3({
        style: {
          margin: '0'
        }
      }, R.a({
        href: "/c/" + channel
      }, "" + window.location.host + "/c/" + channel));
    }
  }
});

Titleblock = React.createClass({
  render: function() {
    return R.div(null, R.h1({
      style: {
        margin: '0'
      }
    }, R.a({
      href: "/c/" + channel
    }, "" + channel), this.props.connected ? " | " + this.props.count : ''), Listenerlist({
      sock: this.props.sock
    }));
  }
});

Player = React.createClass({
  getInitialState: function() {
    return {
      vidkey: null,
      title: null,
      format: null,
      tstart: null,
      tduration: 0,
      tremaining: 0,
      formatname: 'unsupported',
      muted: false,
      volume: 1
    };
  },
  componentDidMount: function() {
    var audio;
    audio = this.props.audio;
    setInterval((function(_this) {
      return function() {
        return _this.setState({
          tremaining: Math.max(0, _this.state.tduration - audio.currentTime)
        });
      };
    })(this), 1000);
    this.props.sock.on('play', (function(_this) {
      return function(msg) {
        return fetchdata(msg.vidkey).done(function(data) {
          var fmt, format, newstate, _i, _len, _ref;
          format = 'format' in data ? data.format : msg.format;
          newstate = {
            vidkey: data.vidkey,
            title: data.title,
            format: format,
            tstart: msg.time,
            tduration: data.duration,
            tremaining: data.duration
          };
          audio.pause();
          audio.type = '';
          audio.src = '';
          _ref = ['m4a', 'mp3', 'webm'];
          for (_i = 0, _len = _ref.length; _i < _len; _i++) {
            fmt = _ref[_i];
            if (fmt in format && audio.canPlayType(format[fmt].type)) {
              audio.type = format[fmt].type;
              audio.src = format[fmt].url;
              newstate.formatname = fmt;
              break;
            }
          }
          if (!audio.src) {
            newstate.formatname = 'unsupported';
            self.props.sock.emit('stop', {
              vidkey: _this.state.vidkey,
              reason: 'error'
            });
          }
          return _this.setState(newstate);
        });
      };
    })(this));
    audio.addEventListener('stalled', (function(_this) {
      return function() {
        return audio.load();
      };
    })(this));
    audio.addEventListener('ended', (function(_this) {
      return function() {
        return _this.props.sock.emit('stop', {
          vidkey: _this.state.vidkey,
          reason: 'end'
        });
      };
    })(this));
    audio.addEventListener('canplay', (function(_this) {
      return function() {
        return audio.play();
      };
    })(this));
    return audio.addEventListener('loadedmetadata', (function(_this) {
      return function() {
        var seek;
        seek = time.synctime() - _this.state.tstart;
        if (Math.abs(audio.currentTime - seek) > 1) {
          return audio.currentTime = seek;
        }
      };
    })(this));
  },
  render: function() {
    var requested, volume;
    if (this.state.vidkey) {
      volume = this.getvolume();
      requested = this.state.vidkey in this.props.request;
      document.title = "" + this.state.title + " - " + channel + " - jam with friends";
      return R.div({
        style: {
          margin: '0.15em auto',
          textAlign: 'center'
        }
      }, R.div(null, R.span({
        className: 'label label-' + (requested ? 'success' : 'default'),
        style: {
          fontWeight: 'bold'
        },
        onClick: (function(_this) {
          return function(evt) {
            return (requested ? _this.props.removeFavorite : _this.props.addFavorite)(_this.state.vidkey);
          };
        })(this)
      }, R.i({
        className: 'glyphicon glyphicon-heart'
      })), ' ', R.span({
        className: 'label label-' + (volume.muted ? 'default' : 'success'),
        style: {
          fontWeight: 'bold'
        },
        onClick: (function(_this) {
          return function(evt) {
            return _this.setvolume(1, !volume.muted);
          };
        })(this)
      }, R.i({
        className: 'glyphicon glyphicon-volume-' + (volume.muted ? 'off' : 'up')
      })), ' ', R.span({
        className: 'label label-danger',
        style: {
          fontWeight: 'bold'
        },
        onClick: (function(_this) {
          return function(evt) {
            return _this.skip();
          };
        })(this)
      }, R.i({
        className: 'glyphicon glyphicon-remove'
      })), ' ', R.span({
        className: 'label label-default',
        style: {
          fontWeight: 'bold'
        }
      }, this.state.formatname.toUpperCase()), ' ', R.span({
        className: 'label label-default',
        style: {
          fontWeight: 'bold'
        }
      }, "" + (parseInt(this.state.tremaining / 60)) + ":" + (lpad(parseInt(Math.round(this.state.tremaining % 60)), 2)))), R.div({
        style: {
          whiteSpace: 'nowrap',
          overflow: 'hidden',
          textOverflow: 'ellipsis'
        }
      }, R.a({
        href: denormalize(this.state.vidkey, {
          target: '_blank'
        })
      }, this.state.title)));
    } else {
      document.title = "" + channel + " - jam with friends";
      return R.div(null);
    }
  },
  getvolume: function() {
    return {
      volume: this.state.volume,
      muted: this.state.muted
    };
  },
  setvolume: function(volume, muted) {
    this.setState({
      volume: volume,
      muted: muted
    });
    this.props.audio.volume = volume;
    return this.props.audio.muted = muted;
  },
  skip: function() {
    var vidkey;
    vidkey = this.state.vidkey;
    if (vidkey) {
      this.props.audio.pause();
      this.setState({
        vidkey: null
      });
      return this.props.sock.emit('stop', {
        vidkey: vidkey,
        reason: 'skip'
      });
    }
  }
});

PlaylistItem = React.createClass({
  getInitialState: function() {
    return {
      title: this.props.vidkey,
      minutes: 0,
      seconds: 0
    };
  },
  componentDidMount: function() {
    return fetchdata(this.props.vidkey).done((function(_this) {
      return function(data) {
        var ex;
        try {
          return _this.setState({
            title: data.title,
            minutes: parseInt(data.duration / 60),
            seconds: parseInt(Math.round(data.duration % 60))
          });
        } catch (_error) {
          ex = _error;
        }
      };
    })(this));
  },
  render: function() {
    var enqueued, requested;
    requested = this.props.vidkey in this.props.request;
    enqueued = 'frequency' in this.props && 'threshold' in this.props ? this.props.frequency >= this.props.threshold : false;
    return R.tr({
      style: {
        margin: '0.5em auto'
      }
    }, R.td({
      style: {
        width: '1em'
      }
    }, R.span({
      className: 'label label-' + (requested ? 'success' : 'default'),
      style: {
        fontWeight: 'bold'
      },
      onClick: (function(_this) {
        return function(evt) {
          return (requested ? _this.props.removeFavorite : _this.props.addFavorite)(_this.props.vidkey);
        };
      })(this)
    }, R.i({
      className: 'glyphicon glyphicon-' + (enqueued ? 'heart' : 'heart-empty')
    }), 'frequency' in this.props ? " " + this.props.frequency : ' ')), R.td({
      style: {
        width: '1em'
      }
    }, R.span({
      className: 'label label-default',
      style: {
        fontWeight: 'bold'
      }
    }, R.a({
      href: denormalize(this.props.vidkey, {
        target: '_blank'
      })
    }, R.i({
      className: 'glyphicon glyphicon-link'
    })))), R.td({
      style: {
        width: '1em',
        textAlign: 'right'
      }
    }, R.span(null, "" + this.state.minutes + ":" + (lpad(this.state.seconds, 2)))), R.td({
      onClick: (function(_this) {
        return function(evt) {
          return (requested ? _this.props.removeFavorite : _this.props.addFavorite)(_this.props.vidkey);
        };
      })(this)
    }, this.state.title));
  }
});

Playlist = React.createClass({
  getInitialState: function() {
    return {
      query: '',
      resultset: [],
      queue: [],
      threshold: 0,
      history: []
    };
  },
  componentDidMount: function() {
    this.props.sock.on('queue', (function(_this) {
      return function(msg) {
        return _this.setState({
          queue: msg.queue,
          threshold: msg.threshold
        });
      };
    })(this));
    this.props.sock.on('history', (function(_this) {
      return function(msg) {
        return _this.setState({
          history: msg.play
        });
      };
    })(this));
    return this.props.sock.on('played', (function(_this) {
      return function(msg) {
        var history, idx;
        history = _this.state.history;
        idx = history.indexOf(msg);
        if (idx >= 0) {
          history.splice(idx, 1);
        }
        history.unshift(msg);
        while (history.length > 16) {
          history.pop();
        }
        return _this.setState({
          history: history
        });
      };
    })(this));
  },
  render: function() {
    var item;
    return R.div(null, R.div({
      className: 'input-group'
    }, R.i({
      className: 'input-group-addon glyphicon glyphicon-search'
    }), R.input({
      type: 'text',
      className: 'form-control',
      onChange: (function(_this) {
        return function(evt) {
          return _this.search(evt.target.value);
        };
      })(this),
      onKeyUp: (function(_this) {
        return function(evt) {
          var vidkey;
          if (evt.keyCode === 27) {
            return _this.searchclear();
          } else if (evt.keyCode === 13 && _this.state.resultset.length > 0) {
            vidkey = _this.state.resultset[0];
            if (vidkey in _this.props.request) {
              return _this.props.removeFavorite(vidkey);
            } else {
              return _this.props.addFavorite(vidkey);
            }
          }
        };
      })(this),
      placeholder: 'Search or URL: YouTube | SoundCloud',
      value: this.state.query
    }), R.div({
      className: 'input-group-btn'
    }, R.button({
      className: 'btn btn-default',
      onClick: this.searchclear
    }, R.i({
      className: 'glyphicon glyphicon-remove-circle'
    })))), R.table({
      className: 'table',
      style: {
        display: (this.state.resultset.length > 0 ? 'block' : 'none'),
        fontSize: '1em'
      }
    }, R.tbody(null, (function() {
      var _i, _len, _ref, _results;
      _ref = this.state.resultset;
      _results = [];
      for (_i = 0, _len = _ref.length; _i < _len; _i++) {
        item = _ref[_i];
        _results.push(PlaylistItem({
          key: item,
          request: this.props.request,
          vidkey: item,
          addFavorite: this.props.addFavorite,
          removeFavorite: this.props.removeFavorite
        }));
      }
      return _results;
    }).call(this))), this.state.queue.length > 0 ? R.table({
      className: 'table',
      style: {
        fontSize: '1em'
      }
    }, R.tbody(null, (function() {
      var _i, _len, _ref, _results;
      _ref = this.state.queue;
      _results = [];
      for (_i = 0, _len = _ref.length; _i < _len; _i++) {
        item = _ref[_i];
        _results.push(PlaylistItem({
          key: item[0],
          request: this.props.request,
          vidkey: item[0],
          frequency: item[1],
          threshold: this.state.threshold,
          addFavorite: this.props.addFavorite,
          removeFavorite: this.props.removeFavorite
        }));
      }
      return _results;
    }).call(this))) : R.h3({
      style: {
        textAlign: 'center'
      }
    }, this.state.history.length > 0 ? R.div(null, 'There are no requests, so I\'m playing random tracks.') : void 0, R.div(null, 'Search YouTube using the bar above. Click ', R.span({
      className: 'label label-default',
      style: {
        fontWeight: 'bold'
      }
    }, R.i({
      className: 'glyphicon glyphicon-heart-empty'
    })), ' to request.')), R.div(null, 'Click ', R.span({
      className: 'label label-default',
      style: {
        fontWeight: 'bold'
      }
    }, R.i({
      className: 'glyphicon glyphicon-heart'
    })), ' to request | Key: ', R.span({
      className: 'label label-success',
      style: {
        fontWeight: 'bold'
      }
    }, R.i({
      className: 'glyphicon glyphicon-heart'
    }), ' requested'), ' ', R.span({
      className: 'label label-default',
      style: {
        fontWeight: 'bold'
      }
    }, R.i({
      className: 'glyphicon glyphicon-heart'
    }), ' queued'), ' ', R.span({
      className: 'label label-default',
      style: {
        fontWeight: 'bold'
      }
    }, R.i({
      className: 'glyphicon glyphicon-heart-empty'
    }), ' needs requests')), R.h1({
      style: {
        display: (this.state.history.length > 0 ? 'block' : 'none')
      }
    }, 'History'), R.table({
      className: 'table',
      style: {
        display: (this.state.history.length > 0 ? 'block' : 'none'),
        fontSize: '1em'
      }
    }, R.tbody(null, (function() {
      var _i, _len, _ref, _results;
      _ref = this.state.history;
      _results = [];
      for (_i = 0, _len = _ref.length; _i < _len; _i++) {
        item = _ref[_i];
        _results.push(PlaylistItem({
          key: item,
          request: this.props.request,
          vidkey: item,
          addFavorite: this.props.addFavorite,
          removeFavorite: this.props.removeFavorite
        }));
      }
      return _results;
    }).call(this))));
  },
  search: function(query) {
    this.setState({
      query: query
    });
    query = trim(query);
    if (query) {
      return this.searchexec(query);
    } else {
      return this.setState({
        resultset: []
      });
    }
  },
  searchclear: function() {
    return this.search('');
  },
  searchexec: _.debounce(function(query) {
    var vidkey;
    vidkey = normalize(query);
    if (vidkey) {
      return this.setState({
        resultset: [vidkey]
      });
    } else {
      return $.getJSON('http://gdata.youtube.com/feeds/api/videos?q=' + encodeURIComponent(query) + '&max-results=5&v=2&alt=json&callback=?').then((function(_this) {
        return function(data) {
          var result;
          if (query === _this.state.query) {
            return _this.setState({
              resultset: (function() {
                var _i, _len, _ref, _results;
                _ref = data.feed.entry;
                _results = [];
                for (_i = 0, _len = _ref.length; _i < _len; _i++) {
                  result = _ref[_i];
                  _results.push(normalize(result.link[0].href));
                }
                return _results;
              })()
            });
          }
        };
      })(this));
    }
  }, 500)
});

Preset = React.createClass({
  render: function() {
    return R.div(null, R.button({
      className: 'btn btn-default',
      onClick: (function(_this) {
        return function(evt) {
          return _this.addRick();
        };
      })(this)
    }, '+Rick'), ' ', R.button({
      className: 'btn btn-default',
      onClick: (function(_this) {
        return function(evt) {
          return _this.addKHS();
        };
      })(this)
    }, '+KHS'), ' ', R.button({
      className: 'btn btn-default',
      onClick: (function(_this) {
        return function(evt) {
          return _this.addEDM();
        };
      })(this)
    }, '+EDM'));
  },
  addRick: function() {
    this.props.addFavorite('youtube:dQw4w9WgXcQ');
    return this.props.addFavorite('youtube:5zFh5euYntU');
  },
  addKHS: function() {
    this.props.addFavorite('youtube:a2RA0vsZXf8');
    this.props.addFavorite('youtube:n-BXNXvTvV4');
    return this.props.addFavorite('youtube:6y1aOg_UO_A');
  },
  addEDM: function() {
    this.props.addFavorite('youtube:RIXcWo1DBSE');
    this.props.addFavorite('youtube:vIM3tVCi0wg');
    return this.props.addFavorite('youtube:j5U8lXoW2EM');
  }
});

ChatInput = React.createClass({
  getInitialState: function() {
    return {
      body: ''
    };
  },
  render: function() {
    return R.div({
      className: 'chatinput input-group'
    }, R.input({
      type: 'text',
      className: 'form-control',
      onChange: (function(_this) {
        return function(evt) {
          return _this.setState({
            body: evt.target.value
          });
        };
      })(this),
      onKeyUp: (function(_this) {
        return function(evt) {
          if (evt.keyCode === 27) {
            return _this.setState({
              body: ''
            });
          } else if (evt.keyCode === 13) {
            return _this.sendChat();
          }
        };
      })(this),
      value: this.state.body,
      placeholder: 'Send a message'
    }), R.div({
      className: 'input-group-btn'
    }, R.button({
      className: 'btn btn-default',
      onClick: this.sendChat
    }, R.i({
      className: 'glyphicon glyphicon-envelope'
    }))));
  },
  sendChat: function() {
    var val;
    val = trim(this.state.body);
    if (val.length > 0) {
      this.props.sock.emit('chat', {
        body: val
      });
      return this.setState({
        body: ''
      });
    }
  }
});

MessagelistItem = React.createClass({
  getInitialState: function() {
    return {
      title: this.props.playing
    };
  },
  componentDidMount: function() {
    if (this.props.playing) {
      return fetchdata(this.props.playing).done((function(_this) {
        return function(data) {
          return _this.setState({
            title: data.title
          });
        };
      })(this));
    }
  },
  render: function() {
    var namebar;
    namebar = [];
    if (this.props.snick) {
      namebar.push(R.strong(null, this.props.snick));
      namebar.push(' ');
    }
    if (this.props.playing) {
      namebar.push(R.span({
        className: 'label label-default'
      }, R.i({
        className: 'glyphicon glyphicon-headphones'
      }), ' ', R.a({
        href: denormalize(this.props.playing, {
          target: '_blank'
        })
      }, this.state.title)));
    }
    return R.div({
      className: 'row',
      style: {
        borderBottom: '1px solid #777'
      }
    }, R.div({
      className: 'col-sm-2'
    }, R.img({
      src: 'http://robohash.org/' + this.props.src + '.png?size=48x48'
    })), R.div({
      className: 'col-sm-10',
      style: {
        margin: '0.5em auto'
      }
    }, R.div({
      style: {
        whiteSpace: 'nowrap',
        overflow: 'hidden',
        textOverflow: 'ellipsis'
      }
    }, namebar), this.props.body));
  }
});

Messagelist = React.createClass({
  getInitialState: function() {
    return {
      history: []
    };
  },
  componentDidMount: function() {
    this.props.sock.on('history', (function(_this) {
      return function(msg) {
        var $chatinput, tailchat;
        $chatinput = $(_this.getDOMNode()).find('.chatinput');
        tailchat = isInViewport($chatinput);
        msg.chat.reverse();
        _this.setState({
          history: msg.chat
        });
        if (tailchat) {
          return $chatinput[0].scrollIntoView();
        }
      };
    })(this));
    return this.props.sock.on('chat', (function(_this) {
      return function(msg) {
        var $chatinput, tailchat;
        $chatinput = $(_this.getDOMNode()).find('.chatinput');
        tailchat = isInViewport($chatinput);
        _this.state.history.push(msg);
        while (_this.state.history.length > 32) {
          _this.state.history.shift();
        }
        _this.setState({
          history: _this.state.history
        });
        if (tailchat) {
          return $chatinput[0].scrollIntoView();
        }
      };
    })(this));
  },
  render: function() {
    var msg;
    return R.div(null, R.h1({
      style: {
        marginTop: '0'
      }
    }, 'Messages'), R.div(null, (function() {
      var _i, _len, _ref, _results;
      _ref = this.state.history;
      _results = [];
      for (_i = 0, _len = _ref.length; _i < _len; _i++) {
        msg = _ref[_i];
        _results.push(MessagelistItem({
          key: msg.src + msg.time + msg.body,
          time: msg.time,
          src: msg.src,
          snick: msg.snick,
          playing: msg.playing,
          body: msg.body
        }));
      }
      return _results;
    }).call(this)), ChatInput({
      sock: this.props.sock
    }));
  }
});

App = React.createClass({
  getInitialState: function() {
    var jam, r;
    r = {
      sock: null,
      audio: document.createElement('audio'),
      id: '',
      cid: randomid(),
      nick: 'User',
      connected: false,
      favorite: [],
      nickname: {},
      channels: [],
      lastpersist: 0
    };
    jam = $.cookie('jam.' + this.props.channel);
    if (jam && jam.v >= 1) {
      r.favorite = jam.f;
      if (jam.t) {
        r.lastpersist = jam.t;
      }
      if (jam.cid) {
        r.cid = jam.cid;
      }
      if (jam.nick) {
        r.nick = jam.nick;
      }
    }
    return r;
  },
  persist: function() {
    return $.cookie('jam.' + this.props.channel, {
      v: 1,
      t: time.time(),
      cid: this.state.cid,
      nick: this.state.nick,
      f: this.state.favorite
    }, {
      expires: 14
    });
  },
  sendRequest: function() {
    this.state.sock.emit('tdelta', time.time());
    return this.state.sock.emit('request', this.state.favorite);
  },
  addFavorite: function(vidkey, propagate) {
    var idx;
    if (propagate == null) {
      propagate = true;
    }
    idx = this.state.favorite.indexOf(vidkey);
    if (idx < 0) {
      this.state.favorite.push(vidkey);
      this.setState({
        favorite: this.state.favorite
      });
      if (propagate) {
        this.sendRequest();
      }
      return this.persist();
    }
  },
  removeFavorite: function(vidkey, propagate) {
    var idx;
    if (propagate == null) {
      propagate = true;
    }
    idx = this.state.favorite.indexOf(vidkey);
    if (idx >= 0) {
      this.state.favorite.splice(idx, 1);
      this.setState({
        favorite: this.state.favorite
      });
      if (propagate) {
        this.sendRequest();
      }
      return this.persist();
    }
  },
  setupSock: function() {
    var sock;
    sock = io.connect('/channel');
    sock.on('connect', (function(_this) {
      return function() {
        _this.persist();
        _this.setState({
          connected: true
        });
        sock.emit('user', {
          cid: _this.state.cid,
          nick: _this.state.nick
        });
        sock.emit('join', channel);
        return _this.sendRequest();
      };
    })(this));
    sock.on('disconnect', (function(_this) {
      return function() {
        return _this.setState({
          connected: false
        });
      };
    })(this));
    sock.on('user', (function(_this) {
      return function(msg) {
        return _this.setState({
          id: msg.id
        });
      };
    })(this));
    sock.on('tdelta', function(msg) {
      time.tdeltalist.push(msg);
      return time.tdelta = (time.tdeltalist.reduce(function(a, b) {
        return a + b;
      })) / time.tdeltalist.length;
    });
    sock.on('nicks', (function(_this) {
      return function(msg) {
        return _this.setState({
          nickname: msg
        });
      };
    })(this));
    sock.on('join', (function(_this) {
      return function(msg) {
        _this.state.nickname[msg.id] = 'User';
        return _this.setState({
          nickname: _this.state.nickname
        });
      };
    })(this));
    sock.on('part', (function(_this) {
      return function(msg) {
        delete _this.state.nickname[msg.id];
        return _this.setState({
          nickname: _this.state.nickname
        });
      };
    })(this));
    sock.on('nick', (function(_this) {
      return function(msg) {
        _this.state.nickname[msg.id] = msg.nick;
        _this.setState({
          nickname: _this.state.nickname
        });
        if (msg.id === _this.state.id) {
          _this.setState({
            nick: msg.nick
          });
          return _this.persist();
        }
      };
    })(this));
    sock.on('play', (function(_this) {
      return function() {
        return _this.persist();
      };
    })(this));
    return this.setState({
      sock: sock
    });
  },
  clickSetup: function() {
    var audio;
    audio = this.state.audio;
    audio.src = '/silence.mp3';
    audio.load();
    audio.play();
    audio.pause();
    return this.setupSock();
  },
  componentDidMount: function() {
    if (time.time() - this.state.lastpersist < 900 && !isMobile()) {
      this.setupSock();
    }
    return $.getJSON('/a/recentchannels', (function(_this) {
      return function(data) {
        return _this.setState({
          channels: data.channels
        });
      };
    })(this));
  },
  render: function() {
    var count, i, k, request, _i, _len, _ref;
    request = {};
    _ref = this.state.favorite;
    for (_i = 0, _len = _ref.length; _i < _len; _i++) {
      i = _ref[_i];
      request[i] = true;
    }
    count = 0;
    for (k in this.state.nickname) {
      count++;
    }
    return R.div(null, Navbar({
      nick: this.state.nick,
      channels: this.state.channels,
      sock: this.state.sock
    }), this.state.sock ? R.div({
      className: 'container'
    }, R.div({
      className: 'row'
    }, R.div({
      id: 'left',
      className: 'col-md-8'
    }, R.div({
      className: 'row',
      style: {
        marginBottom: '1.2em'
      }
    }, R.div({
      className: 'col-md-6'
    }, Titleblock({
      connected: this.state.connected,
      count: count,
      sock: this.state.sock
    })), R.div({
      className: 'col-md-6',
      style: {
        marginTop: '1em'
      }
    }, Player({
      request: request,
      addFavorite: this.addFavorite,
      removeFavorite: this.removeFavorite,
      sock: this.state.sock,
      audio: this.state.audio
    }))), R.div({
      className: 'row'
    }, R.div({
      className: 'col-md-12'
    }, Playlist({
      request: request,
      addFavorite: this.addFavorite,
      removeFavorite: this.removeFavorite,
      sock: this.state.sock
    }))), R.div({
      className: 'row'
    }, R.div({
      className: 'col-md-12'
    }, Preset({
      addFavorite: this.addFavorite
    })))), R.div({
      id: 'right',
      className: 'col-md-4'
    }, Messagelist({
      nick: this.state.nick,
      sock: this.state.sock
    })))) : R.div({
      className: 'container'
    }, R.h2({
      style: {
        textAlign: 'center'
      }
    }, R.button({
      className: 'btn btn-success',
      onClick: this.clickSetup
    }, R.span({
      style: {
        fontSize: '3em'
      }
    }, "" + window.location.host + "/c/" + channel), R.br(null), R.span({
      style: {
        fontSize: '2em',
        fontWeight: 'bold'
      }
    }, 'click to jam with friends'))), R.h2({
      style: {
        textAlign: 'center'
      }
    }, 'what is this?'), R.div({
      className: 'row'
    }, R.div({
      className: 'col-lg-4 col-lg-offset-4 col-md-6 col-md-offset-4 col-sm-8 col-sm-offset-3'
    }, R.div({
      style: {
        fontSize: '1.25em'
      }
    }, R.div(null, R.i({
      className: 'glyphicon glyphicon-refresh'
    }), ' Synchronize online music with friends!'), R.div(null, R.i({
      className: 'glyphicon glyphicon-music'
    }), ' Request from YouTube and SoundCloud'), R.div(null, R.i({
      className: 'glyphicon glyphicon-heart'
    }), ' Upvote your favorites')))), R.h2({
      style: {
        textAlign: 'center'
      }
    }, 'works best with'), R.div({
      style: {
        textAlign: 'center'
      }
    }, R.a({
      title: 'Google Chrome',
      href: 'https://www.google.com/chrome/',
      target: '_blank'
    }, R.img({
      alt: 'Google Chrome',
      src: 'https://raw.githubusercontent.com/alrra/browser-logos/master/chrome/chrome_64x64.png'
    })), R.a({
      title: 'Mozilla Firefox',
      href: 'https://www.mozilla.org/firefox/',
      target: '_blank'
    }, R.img({
      alt: 'Mozilla Firefox',
      src: 'https://raw.githubusercontent.com/alrra/browser-logos/master/firefox/firefox_64x64.png'
    })), R.a({
      title: 'Apple Safari',
      href: 'https://www.apple.com/safari/',
      target: '_blank'
    }, R.img({
      alt: 'Apple Safari',
      src: 'https://raw.githubusercontent.com/alrra/browser-logos/master/safari/safari_64x64.png'
    }))), R.div({
      style: {
        textAlign: 'center',
        fontStyle: 'italic'
      }
    }, 'codec support may vary')));
  }
});

React.renderComponent(App({
  channel: channel
}), document.getElementById('app'));
