@echo off

echo "Building Server..."
mkdir bin
odin build server/ -out:bin/server.exe -strict-style -vet-semicolon -debug -collection:soln=.
echo "Done Building Server..."

if %errorlevel% neq 0 exit echo Build failed. && /b %errorlevel%

"bin/server.exe"