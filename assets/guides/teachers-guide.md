# Wi-Fi Classroom · Teacher's Guide

The Wi-Fi Classroom is the part of the WLAN Pros Toolbox built for teaching. It holds interactive simulators, three guided lessons, and the course handouts I use in class. It ships in the same free app your students already have, so whatever you show on the projector, they can open on their own laptop or tablet after class and work through at their own pace.

This guide covers how to present it, what each tool teaches, and a few lesson sequences that work well.

## Before class

**Use a computer or a tablet.** The simulators are designed for a large screen. On a phone they open behind a short notice that says so, with a Continue anyway button. The guided lessons and the handouts work on any screen.

**No Internet needed.** The simulators compute everything on the device, and the lessons and handouts are built into the app, so a room with poor Wi-Fi does not stop the lesson. (It is a good room to teach Wi-Fi in.)

**Set the scene first.** Open a tool, set it up the way you want to start (a wall material, a channel plan, a number of stations), then press Present. Presenter mode opens the same scene you set up, and when you exit it, your settings are still there.

## Presenting

Every simulator has a **Present** button in its title bar. It appears whenever the window is at least 720 by 480 pixels, so you will see it on a laptop or tablet but not on a phone.

Present gives you one screen with no scrolling: the animation fills about two-thirds of the width, the controls sit in a panel on the right, and the most important number moves onto the stage in large type so the back of the room can read it. On a Mac it goes full screen. Text and lines scale up with the window, because a projector makes any window the same size on the wall.

**The keys work the same way in every simulator:**

| Key | What it does |
|---|---|
| Space | Play or pause |
| Right arrow | Step forward one step (a slot, a frame, a message, a segment) |
| R | Reset |
| Up and Down | Move the tool's main control (distance, SNR, channel width, and so on) |
| F | Switch full screen on or off |
| ? | Show every key for this tool |
| Esc | Leave presenter mode |

A few tools add their own keys, and ? always lists them: 1 to 4 switch modes in Fourier and FFT, D fires a radar event in DFS and Radar, Left takes a message back in the 802.1X ladder, and N draws new traffic in Multi-Link Operation. Tools that do not animate simply ignore Space and the Right arrow.

The bar at the top (title, a light and dark switch, and Exit) hides itself when the mouse is still and comes back when you move it. If the projector washes out the dark theme, switch to light.

## A teaching pattern that works: predict, then reveal

Before you press a key, ask the room what will happen. "If I move this client twice as far from the AP, how much signal do we lose?" "If one client drops to 6 Mbps, what happens to everyone else?" Take the guesses, then press the key. The simulators are built so one control makes one visible change, which is exactly what you need for this. Students remember the moment they were wrong far longer than a slide that told them the answer.

## What each shelf teaches

### Guided Lessons

- **Antenna Fundamentals.** A read-along lesson on what an antenna does (it shapes where the energy goes; it does not add power), gain against beamwidth, polarization, downtilt, and how to read a radiation pattern. Pair it with Antenna Pattern.
- **Spectrum Analysis.** A read-along lesson on why a spectrum analyzer sees energy a Wi-Fi adapter cannot, how the instrument works, and the signatures of common interferers. Pair it with the Swept vs FFT race in Fourier and FFT.
- **Find My, Explained.** How Apple finds your people, your phone and your things, including the AirTag in your suitcase, and what you should turn on before your next trip.

### RF and Propagation

- **FSPL Simulator.** Free-space path loss against distance for 2.4, 5 and 6 GHz on one chart, with a Why panel that splits each band's loss into the part every band shares and the part that changes with frequency. Up and Down double and halve the distance, so each press shows the 6 dB per doubling rule.
- **Wi-Fi Through a Wall.** One wave meets one wall: part reflects, the wave gets smaller as the material absorbs it, and the same wave continues behind the wall, smaller. The frequency never changes. Up and Down change the thickness.
- **Multipath Simulator.** Why the signal changes when you move a few centimeters: the direct signal and its reflections arrive with different phases and add like arrows. Up and Down move the receiver a sixteenth of a wavelength, so a few presses walk from a peak into a null.
- **Room Propagation.** An AP, walls and doorways on a floor plan, colored by received power, with the loss at a spot split into free space, walls and diffraction for each band.
- **Antenna Pattern.** A radiation pattern in 3D beside the two cuts a datasheet prints. Space spins it. Turn up the gain on an omni and watch it flatten, then flip between ceiling and wall mounting.
- **Rate vs Range.** One ring per MCS around an AP, and the cell edge set by the minimum basic rate. Up and Down move the client out and in.
- **6 GHz Power and PSD.** The most power each 6 GHz device class may radiate, and the SNR it leaves, against channel width. Up and Down step the width, which shows when a wider channel keeps its SNR and when it loses 3 dB per doubling.

### Signals and PHY

- **Modulation Simulator.** How bits become a radio wave: each group of bits picks a point on the constellation, and noise pushes the received point toward its neighbors. Up and Down move the SNR; watch the errors appear.
- **Fourier and FFT.** Four modes: build a signal from sines, see how an FFT analyzer measures it, race a swept analyzer against an FFT analyzer on Bluetooth and a microwave oven, and see OFDM as an inverse FFT. Keys 1 to 4 switch modes.
- **OFDMA Resource Units.** One channel split into resource units so an AP can serve several clients in one transmission, compared with sending to each in turn.
- **MIMO and Beamforming.** Why a 4x4 AP and a 2x2 client use two streams, what the spare antennas do instead, what beamforming costs, and why a capture taken nearby misses beamformed frames. Up and Down steer the client.
- **PHY Preamble Reference.** Every PPDU format's preamble drawn to scale, with each SIG field's bits. The Which PHY? mode walks the room through how a receiver tells the formats apart.

### Airtime and Access

- **Medium Access Simulator.** Stations sharing one channel, slot by slot: backoff, collisions, the contention window doubling, EDCA priority, hidden nodes and RTS/CTS.
- **Airtime Anatomy.** One transmit opportunity drawn to scale, microsecond by microsecond. The Right arrow walks it one segment at a time. Compare one frame against 32 aggregated frames and ask how much of the air carried data.
- **Airtime Fairness.** Why one slow client drags every fast client down, and how airtime fairness changes that. Up and Down switch the sharing rule.
- **Rate Adaptation.** A link learning its best rate frame by frame, the way Linux rate control does. Walk the client away and back and watch the rate step down and recover.
- **Spatial Reuse.** Two networks on one channel, and what BSS coloring and OBSS_PD let an AP do. Up and Down move the threshold, and the links show what each step costs.
- **Power Save.** Beacons, DTIM, and four ways a client sleeps, with awake time, battery and latency for each. Up and Down change the DTIM period.
- **Multi-Link Operation.** Wi-Fi 7 MLO modes compared on the same traffic, including cases where using more links is worse. N draws new traffic.

### Network Design and Security

- **Channel Planner.** Access points on a floor with channels and widths, showing which ones share airtime. Up and Down change the channel width for every AP at once; try the Auto-plan.
- **Roaming Walk.** A client walks a floor of APs, and the screen shows when it roams and what each roam costs. Up and Down move the roam trigger, so you can make a sticky client and a client that bounces between APs.
- **DFS and Radar.** One AP on a simulated one-hour clock: the channel availability check, a radar event (press D), the move, and the 30-minute lockout.
- **802.1X and EAP Ladder.** An 802.1X connection one message at a time across the client, the AP and the RADIUS server, for EAP-TLS, PEAP, EAP-TTLS, and PSK and SAE for contrast. Right sends the next message; Left takes one back.

### Course Handouts

Built-in, zoomable copies of my published reference cards: the 2.4, 5 and 6 GHz channel allocations (including the 6 GHz card with GVP), the MCS index, Troubleshooting Causes, the Bubble Diagram, and the four checklists. Put one on the projector while you talk through it, and students have the same card in their own copy of the app.

## Lesson sequences that work

These are starting points. Each takes about half an hour of demonstration and discussion.

- **Why 6 GHz behaves differently.** FSPL Simulator (the extra loss comes from the antenna, not the air), then Wi-Fi Through a Wall, then 6 GHz Power and PSD.
- **Why the signal jumps when you move.** Multipath Simulator, then Room Propagation's close-up of the nulls near a wall.
- **Why is the Wi-Fi slow?** Medium Access Simulator, then Airtime Anatomy, then Airtime Fairness, then Rate Adaptation.
- **Antennas.** The Antenna Fundamentals lesson, then Antenna Pattern.
- **Spectrum analysis.** The Spectrum Analysis lesson, then the Swept vs FFT race and OFDM modes in Fourier and FFT.
- **From bits to rate.** Modulation Simulator, then Rate vs Range, then PHY Preamble Reference.
- **Designing a cell plan.** Channel Planner, then Roaming Walk, then DFS and Radar.
- **Wi-Fi 6 and 7 features.** OFDMA Resource Units, Spatial Reuse, then Multi-Link Operation.
- **Enterprise security.** 802.1X and EAP Ladder, run once for EAP-TLS and once for PEAP, then SAE for contrast.

## What the numbers are, and what they are not

The simulators are built from the IEEE 802.11 standard, ITU recommendations and FCC and ETSI rules, and each tool's help says where its numbers come from. Some values are teaching models rather than measurements, and the screens say so where that is the case: a success curve that stands in for a real radio, a timing chosen to illustrate, the receiver sensitivities that are conformance floors real radios beat. When a student asks "is that what my AP does?", the answer is often "this is the mechanism; your AP's numbers will differ", and the tool's help tells you which parts are which.

## After class

Students have the same app. Point them to the Wi-Fi Classroom on a laptop or tablet, and suggest they repeat the demonstrations you did, changing one control at a time. The handouts give them the cards to keep, and the Field Manual in the app documents every tool in detail. 
