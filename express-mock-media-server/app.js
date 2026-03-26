var express = require('express');
var path = require('path');
var cookieParser = require('cookie-parser');
var logger = require('morgan');
var cors = require('cors');
var etag = require('etag');
const bodyParser = require('body-parser');
require('body-parser-xml')(bodyParser);

var indexRouter = require('./routes/index');

var app = express();

app.use(logger('dev'));
app.use(express.json());

app.use(express.urlencoded({ extended: false }));
app.use(cookieParser());
app.use(cors());
//app.use(bodyParser.xml());
app.use(bodyParser.text({ type: 'application/xml' }));
app.use(express.static(path.join(__dirname, 'public'), {etag: true, index: false, lastModified: true, setHeaders(res, pth, stat) {
		var not_modified = false;
		var if_modified_since = res.req.get('If-Modified-Since');
		if (if_modified_since !== undefined) {
		    if (stat.mtime <= Date(if_modified_since)) {
			not_modified = true;
		    }
		}
		var if_none_match = res.req.get('If-None-Match');
		if (if_none_match !== undefined) {
		    var e = etag(stat);
		    if (e == if_none_match) {
			not_modified = true;
		    }
		}
		if (not_modified) {
		    res.status(304);
		}
		if (pth == path.join(__dirname, 'public/carousel')) {
		    res.setHeader('Content-Type', 'application/3gpp-mbs-object-manifest+json;version="Rel17"');
		} else {
		    res.setHeader('Content-Type', 'text/plain');
		}
		res.setHeader('Cache-Control', 'max-age=30');
	    }
	}));

app.use('/', indexRouter);

module.exports = app;
