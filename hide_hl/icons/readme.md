# Icon Guideline / tutorial

It's recommended to use Inkscape for the icon creation

Use `../icon_parts/inkscape_icon_template.svg` as a base

export only one path for each svg, as msdfgen only support one path per svg.

To do that, select all your shapes/objects in inkscape, do Path -> Object to Path and Path -> Stroke to Path, then select all and do a Path -> Union operation (if that fails, check that you don't have groups in the layers and object panel)

Use the Icon preview panel to check the appearence of the icon in 16x16 and up resolution, usually the preview will be 95% accurate to the msdf render even at that resolution

Try to keep a 2px gap between the path and the border of the document (assuming you have a 32x32 pixel document)

Once you have exported your icon, call `make` inside this folder to export each .svg to res/ui/icons/*.sdf.png files. The .sdf.png extension is a trick to differenciate inside of heaps what resources are supposed to be treated as an sdf