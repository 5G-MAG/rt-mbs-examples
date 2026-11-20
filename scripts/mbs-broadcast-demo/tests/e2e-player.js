// Plays the application's DASH player in Chrome and prints the currentTime samples as JSON (one line).
// PLAYWRIGHT_MODULE: path of a playwright install (default: "playwright"); MANIFEST: the content path to play.
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
(async () => {
  const b = await chromium.launch({ channel: 'chrome', headless: true, args: ['--autoplay-policy=no-user-gesture-required'] });
  const p = await b.newPage({ viewport: { width: 1280, height: 800 } });
  await p.goto((process.env.APP_URL || 'http://localhost:3050') + '/application?p=dash&m=' +
    encodeURIComponent(process.env.MANIFEST || '/api/content/tv_1_live/manifest.mpd'));
  const samples = [];
  for (let i = 0; i < 8; i++) {
    await p.waitForTimeout(2500);
    samples.push(await p.evaluate(() => { const v = document.querySelector('video'); return v ? { t: +v.currentTime.toFixed(2), rs: v.readyState } : null; }));
  }
  console.log(JSON.stringify(samples));
  await b.close();
})();
