/* ARexx script to create wireless.prefs with error checking */

filename = "sys:Prefs/Env-Archive/sys/wireless.prefs"

Say "Utility to create Wireless.prefs file for wifipi.device for PiStorm"
Say "You must have a compatible Wifi Network. This needs to be WPA2-AES (NOT mixed mode). Ideally this is 2.4ghz band"
Say "Mesh Networks and mixed 2.4/5ghz networks can be problematic!"
Say "Both the SSID and the passsword are case sensitive! If you get this wrong, rerun this utility"
Say ""

IF EXISTS(filename) THEN DO
    SAY "The file 'wireless.prefs' already exists."
    SAY "Do you want to overwrite it? (Y/N)"
    PULL confirm
    IF confirm ~= "Y" THEN DO
        SAY "Operation cancelled."
        EXIT 0
    END
    /* Delete the file to ensure a clean write */
    ADDRESS COMMAND "Delete " filename " QUIET"
END

ssid = ""
DO WHILE ssid = ""
    SAY "Enter SSID of your wireless network"
    PARSE PULL ssid
    IF ssid = "" THEN SAY "SSID cannot be empty. Please try again."
END

password = ""
DO WHILE password = ""
    SAY "Enter Password"
    PARSE PULL password
    IF password = "" THEN SAY "Password cannot be empty. Please try again."
END

IF OPEN(filehandle, filename, "W") THEN DO
    WRITELN(filehandle, "network={")
    WRITELN(filehandle, 'ssid="' || ssid || '"')
    WRITELN(filehandle, 'psk="' || password || '"')
    WRITELN(filehandle, "}")
    CLOSE(filehandle)
    SAY "Configuration successfully written to" filename
END
ELSE DO
    SAY "Error: Could not open file for writing."
    EXIT 10
END

EXIT