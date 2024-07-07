@echo off

echo "Building Client..."
odin build client/ -out:bin/client.exe -vet-semicolon -debug -collection:soln=.
echo "Done Building Client..."

if %errorlevel% neq 0 exit echo Build failed. && /b %errorlevel%

"bin/client.exe"