@echo off

echo "Building Client..."
odin build test_client/ -out:bin/test_client.exe -vet-semicolon -debug -collection:soln=.
echo "Done Building Client..."

if %errorlevel% neq 0 exit echo Build failed. && /b %errorlevel%

"bin/test_client.exe"