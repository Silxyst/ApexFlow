ApexFlow Web — remote panel (v0.31.2)

REMOTE PANEL (live, talks to the in-game app)
Requires Python 3 (standard library only, nothing to install).

  a) In game: open ApexFlow > System > "Remote Web UI" and ENABLE it.
     Note the token if you set one (empty = no password).
  b) On the PC, run:
       python panel_server.py
     and open  http://localhost:8080/panel.html
  c) On your phone (same Wi-Fi): open  http://<pc-ip>:8080/panel.html
     (the server prints the address on startup).
  d) For streaming/OBS: add panel.html as a Browser Source.

What you can do: live position/lap/speed/gaps/penalty points,
adjust AI aggression/pace/difficulty, toggle rolling start and
strategy, save/reset the config.

Files exchanged with the game (Documents/Assetto Corsa folder):
  ApexFlow_webui_status.json  (app -> panel, every 0.5s)
  ApexFlow_webui_cmd.json      (panel -> app, commands)
