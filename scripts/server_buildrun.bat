@echo off

echo "Building Server..."
odin build server/ -out:bin/server.exe -debug
echo "Done Building Server..."

if %errorlevel% neq 0 exit echo Build failed. && /b %errorlevel%

"bin/server.exe"