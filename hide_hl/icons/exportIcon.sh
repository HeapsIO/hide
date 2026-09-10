LOGO="src/HideLogo.svg"

mkdir -p tmp/
inkscape -w 16 -h 16 -o tmp/16.png $LOGO
inkscape -w 32 -h 32 -o tmp/32.png $LOGO
inkscape -w 48 -h 48 -o tmp/48.png $LOGO
inkscape -w 256 -h 256 -o tmp/256.png $LOGO

CONVERT="C:/Shiro/Projects/shiroTools/tools/ImageMagick/convert.exe"

$CONVERT "tmp/16.png" "tmp/32.png" "tmp/48.png" "tmp/256.png" "../res/hide.ico"

rm -rf tmp/