var express = require('express');
var path = require('path');
var cookieParser = require('cookie-parser');
var logger = require('morgan');
var cors = require('cors');
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
app.use(express.static(path.join(__dirname, 'public'), {etag: true, index: false, lastModified: true, setHeaders(res, path, stat) { res.set('Content-Type', 'text/plain'); } }));

app.use('/', indexRouter);

module.exports = app;
