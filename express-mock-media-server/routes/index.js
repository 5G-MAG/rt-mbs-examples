var express = require('express');
var router = express.Router();

/* GET /object2 - temporary redirect to /real-object2 */
router.get('/object2', function(req, res, next) {
  res.redirect(302, '/real-object2');
});

/* GET /object3 - permanent redirect to /perm-object3 */
router.get('/object3', function(req, res, next) {
  res.redirect(301, '/perm-object3');
});

/* GET /perm-object3 - temporary redirect to /real-object3 */
router.get('/perm-object3', function(req, res, next) {
  res.redirect(302, '/real-object3');
});

/* GET /object4 - temporary redirect to /temp-object4 */
router.get('/object4', function(req, res, next) {
  res.redirect(302, '/temp-object4');
});

/* GET /temp-object4 - permanent redirect to /real-object4 */
router.get('/temp-object4', function(req, res, next) {
  res.redirect(301, '/real-object4');
});

module.exports = router;
