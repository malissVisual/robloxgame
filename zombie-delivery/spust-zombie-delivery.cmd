@echo off
rem Dvojklik (Windows): stahne nejnovejsi verzi z GitHubu a spusti synchronizaci hry Zombie Delivery do Studia.
rem Ve Studiu otevri NOVY prazdny place (Baseplate), pak Rojo - Connect - Play. Okno nech bezet.
cd /d "%~dp0.."
echo == Stahuji nejnovejsi verzi z GitHubu ==
git pull
echo.
echo == Spoustim synchronizaci Zombie Delivery (nech toto okno otevrene) ==
node tools\rojo-sync.js zombie-delivery
pause
