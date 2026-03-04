/*
**  Miami offline - arexx script for Miami TCP/IP
**
**  $VER: MiamiOffline 1.0 (9.11.96)
**
**  By Kenneth C. Nilsen (kennecni@IDGonline.no)
**
*/

options results

if ~show('p', 'MIAMI.1') then do
	Say "Miami is already offline!"
	Exit 0
end

address 'MIAMI.1'

ISONLINE
IF RC=0 then do
	Say "Miami is already offline!"
	Exit 0
END

OFFLINE

ISONLINE
IF RC=1 then do
	Say "Couldn't get Miami offline!"
	Say "Please terminate TCP/IP clients and try again." 
	Exit 0
END

QUIT	/* remove this line if you want Miami to still run after the
	   offline procedure. The Online script will however start Miami
	   again if the miami port is not found */

exit 0
