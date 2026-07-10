@echo off
cd /d %~dp0

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\start-image-stack.ps1