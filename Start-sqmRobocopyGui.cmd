@echo off
:: sqmRobocopyGui - startet die GUI direkt aus diesem Ordner (ohne Installation)
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -Command "Import-Module '%~dp0sqmRobocopyGui.psd1' -Force; Show-sqmRobocopyGui"
