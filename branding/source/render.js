// Renders every out/*.svg to PNG at its native size (and 2x for logos) with headless Chromium.
const { chromium } = require('playwright-core');
const fs = require('fs');
const path = require('path');

(async () => {
  const browser = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const page = await browser.newPage();
  for (const file of fs.readdirSync('out').filter(f => f.endsWith('.svg'))) {
    const svg = fs.readFileSync(path.join('out', file), 'utf8');
    const [, w, h] = svg.match(/width="([\d.]+)" height="([\d.]+)"/);
    const scale = file.startsWith('offgrid-') ? 4 : 1;
    await page.setViewportSize({ width: Math.round(+w), height: Math.round(+h) });
    const transparent = !file.startsWith('banner') && !file.startsWith('app-icon');
    await page.setContent(`<html><body style="margin:0;background:${transparent ? 'transparent' : '#000'}">${svg}</body></html>`);
    await page.evaluate(s => { document.querySelector('svg').style.display = 'block'; }, scale);
    const el = await page.$('svg');
    if (scale > 1) {
      await page.setViewportSize({ width: Math.round(+w * scale), height: Math.round(+h * scale) });
      await page.evaluate(([w, h]) => { const s = document.querySelector('svg'); s.setAttribute('width', w); s.setAttribute('height', h); },
        [Math.round(+w * scale), Math.round(+h * scale)]);
    }
    await (await page.$('svg')).screenshot({ path: path.join('out', file.replace('.svg', '.png')), omitBackground: transparent });
    console.log('rendered', file);
  }
  await browser.close();
})();
