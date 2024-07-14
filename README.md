# pulse-palette

A server/client app that visualises audio.
The goal is to let other devices on the network also visualise all audio coming from the server's device.

## building and running

1. install the latest odin compiler (https://odin-lang.org/docs/install/)
2. build and run the server `./scripts/server_buildrun.bat`
3. build and run any client `./scripts/test_client_buildrun.bat`

## TODO server
1. additional postprocessing of the freq spectrum
   1. normalise freq from 0 to 1 range
   2. log scaling of freq data (should this happen on the server or clients?)
   3. cast data to 16 bit (u16) samples and freq 
2. debug crc check failing on client
3. cbor protocol?
4. cleanup build scripts

## TODO test client
1. make pretty

## TODO game client
1. 

## TODO esp client
1. 