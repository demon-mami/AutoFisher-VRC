@echo off
title AutoFisher-VRC Update
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0_update.ps1"
