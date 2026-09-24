var express = require('express');
var path = require('path');
var cookieParser = require('cookie-parser');
var logger = require('morgan');
var cors = require('cors');
var etag = require('etag');
const bodyParser = require('body-parser');
require('body-parser-xml')(bodyParser);

var indexRouter = require('./routes/index');

// Extracted so it can be unit-tested directly (see test/app.test.js) rather than only through
// the live server, where express.static's own built-in `lastModified`/`etag` handling
// (both enabled below) already produces a correct 304/200 decision on its own and would mask
// a broken comparison here entirely -- confirmed directly: with lastModified/etag disabled,
// the original expression (Date(if_modified_since), no `new`) produced the wrong 200 for a
// file mtime genuinely before the requested time; with them enabled as shipped, the server's
// own observable response was unaffected either way. Fixed anyway, since the expression itself
// is objectively wrong regardless of what currently happens to mask it.
//
// Date(x) called without `new` ignores its argument entirely and returns the current time as
// a string (a well-known JS gotcha). A Date object's default ToPrimitive hint is "string" (not
// "number", unlike most other objects), so `stat.mtime <= Date(if_modified_since)` compared two
// strings lexicographically -- not, as first assumed here, a NaN-producing numeric coercion;
// confirmed directly, and that first explanation was wrong (corrected here rather than left
// standing). Lexicographic comparison of `Date.prototype.toString()`'s own
// "Www Mmm DD YYYY ..." format does not track chronological order (the weekday/month
// abbreviation dominates the comparison ahead of the year), so the expression was wrong
// regardless of which specific failure mode explains it.
function isNotModifiedSince(mtime, ifModifiedSinceHeader) {
  if (ifModifiedSinceHeader === undefined) return false;
  return mtime <= new Date(ifModifiedSinceHeader);
}

var app = express();

app.use(logger('dev'));
app.use(express.json());

app.use(express.urlencoded({ extended: false }));
app.use(cookieParser());
app.use(cors());
//app.use(bodyParser.xml());
app.use(bodyParser.text({ type: 'application/xml' }));
app.use(express.static(path.join(__dirname, 'public'), {etag: true, index: false, lastModified: true, setHeaders(res, pth, stat) {
		var not_modified = isNotModifiedSince(stat.mtime, res.req.get('If-Modified-Since'));
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
		if (pth == path.join(__dirname, 'public/carousel') ||
		    pth == path.join(__dirname, 'public/carousel-live') ||
		    pth == path.join(__dirname, 'public/collection-manifest')) {
		    res.setHeader('Content-Type', 'application/3gpp-mbs-object-manifest+json;version="Rel17"');
		} else if (pth.endsWith('.mpd')) {
		    // MBSTF's own DASHManifestHandler (rt-mbs-transport-function/src/mbstf/
		    // DASHManifestHandler.cc) is registered by content-type ("application/dash+xml",
		    // ManifestHandlerFactory::registerManifestHandler) -- serving a .mpd file as the
		    // generic text/plain default below means MBSTF never recognises it as a manifest
		    // at all (confirmed live: it logs "Response Parsed JSON" and "Empty schedule" for
		    // a fetched .mpd instead of discovering any segments from it).
		    res.setHeader('Content-Type', 'application/dash+xml');
		} else {
		    res.setHeader('Content-Type', 'text/plain');
		}
		if (pth.endsWith('.mpd')) {
		    // How long a live MPD may be relied upon is bounded by its own
		    // @minimumUpdatePeriod, which this static file server does not parse, so any
		    // fixed lifetime risks exceeding it. ISO/IEC 23009-1:2026 clause 5.3.9.5.3:
		    // "The MPD shall include URL information for all Segments with an availability
		    // start time less than both (i) the end of the Media Presentation and (ii) the
		    // sum of the latest time at which this version of the MPD is available on the
		    // server and the value of the MPD@minimumUpdatePeriod." A consumer told to hold
		    // this manifest longer than that cannot see the segments published in between:
		    // serving a 5 s presentation with max-age=30 left an MBSTF re-reading it six
		    // times too slowly, delivering exactly every sixth segment. "no-cache" still
		    // permits caching but requires revalidation, which etag and lastModified above
		    // already make cheap, and invents no lifetime of its own.
		    res.setHeader('Cache-Control', 'no-cache');
		} else {
		    res.setHeader('Cache-Control', 'max-age=30');
		}
	    }
	}));

app.use('/', indexRouter);

// Attached to the exported app (an Express app is a function; adding a property to it doesn't
// change how bin/www or anything else consumes it as the app itself) so test/app.test.js can
// exercise the comparison directly, not only through the live server where lastModified/etag
// mask it (see isNotModifiedSince()'s own comment above).
app.isNotModifiedSince = isNotModifiedSince;

module.exports = app;
