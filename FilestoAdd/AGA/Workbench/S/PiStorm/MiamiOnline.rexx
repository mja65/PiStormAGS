/*
**  Miami online - arexx script for Miami TCP/IP
**
**  $VER: MiamiOnline 1.1 (9.11.96)
**
**  By Kenneth C. Nilsen (kennecni@IDGonline.no)
**  Modified by Matt Alexandre 
**
*/

parse arg configName

options results

if ~show('p', 'MIAMI.1') then do
    address command
    "run <>nil: Miami:miamidx "configName   
    "WaitForPort MIAMI.1"
end

address 'MIAMI.1'

ISONLINE
if RC=1 then exit 5

ONLINE

ISONLINE
if RC=0 then exit 5

ISONLINE
if RC=1 then hide

exit 0
