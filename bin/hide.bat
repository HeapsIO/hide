@echo off
cd bin 2>NUL
set PATH=nwjs;%PATH%
nw.exe --nwapp package.json