Brand kit generator. Text is converted to outlines, so the SVGs need no fonts installed.

```sh
npm i @fontsource/inter-tight @fontsource/instrument-serif @fontsource/jetbrains-mono playwright-core
pip install fonttools brotli
python3 make_brand.py && node render.js   # writes out/*.svg and out/*.png
```
