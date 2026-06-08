# How to add/modify fonts for hide_hl

* Font currently need to be generated in two size, one for 1080p and one for 4k resolutions.
* Font building relies on bmfont64.exe, available here : [https://angelcode.com/products/bmfont/](https://angelcode.com/products/bmfont/). The exe should be available in your path.

## Adding a font
1. Create 2 new .bmfc config files for each new font to generate, one for the 1x font size and one for the 2x font size
2. Add a build step in the `build.sh` for each of the two config files
3. Run the build step. The font will be generated in `hide_hl/res/font/your_font_name.png
4. Add the font with a name and the two size variants inside the `fontPairs` map in `HuiText.hx`
5. Now you can set the font in your .less files with the `base-font` property and the name of your font that you registered in the `fontPair` array
