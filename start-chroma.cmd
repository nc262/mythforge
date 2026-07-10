@echo off
cd /d %USERPROFILE%

chroma run --host 0.0.0.0 --port 8100
pause