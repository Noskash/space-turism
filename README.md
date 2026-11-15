# Space Tourism

## Play

| Where | How |
|---|---|
| 🌐 **Browser** (PC, Mac) | **https://web-production-c47e249c.up.railway.app** — nothing to install |
| 📱 **Phone / tablet** | Open the **same link** in Chrome or Safari and turn the phone sideways. On-screen joystick and buttons appear automatically. |
| 🪟 **Windows** | **[Download SpaceTourism-windows.zip](https://github.com/Noskash/space-turism/releases/latest/download/SpaceTourism-windows.zip)** · [all releases](https://github.com/Noskash/space-turism/releases) |

**Windows download:** unzip it and run `SpaceTourism.exe`. Nothing to install. The exe isn't signed, so Windows may show
*"Windows protected your PC"* — click **More info → Run anyway**.

**Co-op across devices:** the host creates a room and everyone else types the **4-letter code**, so a phone can join
a friend on a PC. Everyone needs the same game version: the lobby shows a short build code, and it must match.

| Trailer | Gameplay |
|---|---|
| [![Space Tourism – official trailer](https://img.youtube.com/vi/WSROwOI0oCw/maxresdefault.jpg)](https://youtu.be/WSROwOI0oCw) | [![Space Tourism – dev gameplay](https://img.youtube.com/vi/XHM6aNS92Pk/maxresdefault.jpg)](https://youtu.be/XHM6aNS92Pk) |
| [Watch the trailer on YouTube](https://youtu.be/WSROwOI0oCw) | [Watch the gameplay on YouTube](https://youtu.be/XHM6aNS92Pk) |

An educational co-op game about designing and flying a NASA-style Mars mission, made for the
NASA Space Apps Challenge. 1–4 players, each with a crew role, work together like a kitchen crew in
Overcooked — except the kitchen is a spacecraft on its way to Mars.

> There is no single best design: every choice is a trade-off, and fixing one bottleneck exposes the next.

## How a mission goes

1. **Build** — in the hangar, carry parts to the rocket and fit the spacecraft. Every part costs mass, power and budget.
2. **Plan** — pick the launch date and path at the planner console. Mars windows open every 26 months.
3. **Launch** — fly the rocket through max-Q to orbit with the throttle lever.
4. **Cruise** — run between stations: solar storms, comet debris, fires, hull breaches, data downlinks.
5. **Arrive** — brake into Mars orbit, then read the report: why it went that way, and what NASA actually did.

Missions re-fly real NASA robot missions: **Mars Odyssey**, **Mars Reconnaissance Orbiter** and **MAVEN**,
plus a sandbox with every hazard switchable.

## Crew roles

| Role | Job |
|---|---|
| Navigator | course burns, the Mars orbit brake |
| Engineer | power, heat, storm safe mode |
| Comms | downlinks during Deep Space Network passes |
| Scientist | instruments and science windows |

## Controls

| Key | Action |
|---|---|
| WASD / arrows | move (hold Shift to run) |
| SPACE | use / dock / hold to work |
| Q | leave a station or close a window |
| F | hangar: read a part's info card |
| E | Bridge radar (while docked at the Bridge) |
| TAB | hide or show the HUD |
| G | ping your team |
| ESC | menu (codex, briefing, settings) |

On phones and tablets: joystick on the left half of the screen (push to the rim to run), **USE** button on the right.

## Built with

Godot 4 (GDScript). Physics is simplified for gameplay and labelled so on screen; the facts behind every event
were checked against NASA/JPL sources.
