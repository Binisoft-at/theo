// Renders SVG files to PNG with the preinstalled Chromium.
// usage: node render.js in.svg out.png size [in2.svg out2.png size2 ...]
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');
(async () => {
  const args = process.argv.slice(2);
  const browser = await chromium.launch();
  const page = await browser.newPage({ deviceScaleFactor: 1 });
  for (let i = 0; i < args.length; i += 3) {
    const [input, output, sizeStr] = args.slice(i, i + 3);
    const size = parseInt(sizeStr, 10);
    const svg = fs.readFileSync(input, 'utf8');
    await page.setViewportSize({ width: size, height: size });
    await page.setContent(`<!doctype html><html><head><style>html,body{margin:0;padding:0;background:transparent}svg{display:block;width:${size}px;height:${size}px}</style></head><body>${svg}</body></html>`);
    await page.screenshot({ path: output, omitBackground: true, clip: { x: 0, y: 0, width: size, height: size } });
    console.log('rendered', path.basename(output), size);
  }
  await browser.close();
})();
