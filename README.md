# PI-Tracker
An addon (designed for Priests) that whispers that target when they receive PI and tracks their damage or healing done. It also records this data to "rank" each PI. Download from https://addons.wago.io/addons/pi-tracker

PI Tracker for WotLKC

Whispers the target of your PI with a custom message to alert them. At the end of PI, by default, it will message the amount of damage or healing done during PI, whichever is greater. You can optionally include a closing message and whisper the PI statistics you have recorded for that character.

This addon stores all PI healing and damage totals in a sorted list which you can see in your account wide SavedVariables folder, just look for the PITracker.lua file. It records each player's best and average rankings out of those PIs and that is what will be whispered in the PI statistics message.
Accessing Settings

You can access settings normally in the Interface menu in game or with the slash commands

    /pi

    /pitracker

Future Changes:

Do not start "ranking" PI data until a sufficiently large (10-20) list is built from using PIs.
