@echo off

odin test server/spectrum -out:bin/server_tests.exe -debug -o:none -collection:soln=.
odin test protocol -out:bin/protocol_tests.exe -debug -o:none -collection:soln=.