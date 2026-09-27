# Wi-Fi Classroom · Teacher's Guide

The Wi-Fi Classroom is the part of the WLAN Pros Toolbox built for teaching. It holds interactive simulators, three guided lessons, and the course handouts I use in class. It ships in the same free app your students already have, so whatever you show on the projector, they can open on their own laptop or tablet after class and work through at their own pace.

This guide covers how to present it, what each tool teaches, and a few lesson sequences that work well.

## Before class

**Use a computer or a tablet.** The simulators are designed for a large screen. On a phone they open behind a short notice that says so, with a Continue anyway button. The guided lessons and the handouts work on any screen.

**No Internet needed.** The simulators compute everything on the device, and the lessons and handouts are built into the app, so a room with poor Wi-Fi does not stop the lesson.

**Set the scene first.** Open a tool, press the 'Present' button on the top right to have it go full screen. Then set it up the way you want to start (a wall material, a channel plan, a number of stations). I've found it easier to set the various options while already in Presenter mode.

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

A few tools add their own keys, and ? always lists them: 1 to 4 switch modes in Fourier and FFT, D fires a radar event in DFS and Radar, Left takes a message back in the 802.1X ladder, and N draws new traffic in Multi-Link Operation. The newer simulators add a few more, such as P to reveal the answer after the room has guessed, and ? lists them in every tool. Tools that do not animate simply ignore Space and the Right arrow.

The bar at the top (title, a light and dark switch, and Exit) hides itself when the mouse is still and comes back when you move it. If the projector washes out the dark theme, switch to light mode.

## A teaching pattern that works: predict, then reveal

Before you press a key, ask the room what will happen. "If I move this client twice as far from the AP, how much signal do we lose?" "If one client drops to 6 Mbps, what happens to everyone else?" Take the guesses, then press the key. The simulators are built so one control makes one visible change, which is exactly what you need for this. Students remember the moment they were wrong far longer than a slide that told them the answer.

## What each shelf teaches

### Guided Lessons

- **Antenna Fundamentals.** A read-along lesson on what an antenna does (it shapes where the energy goes; it does not add power), gain against beamwidth, polarization, downtilt, and how to read a radiation pattern. Pair it with Antenna Pattern.
- **Spectrum Analysis.** A read-along lesson on why a spectrum analyzer sees energy a Wi-Fi adapter cannot, how the instrument works, and the signatures of common interferers. Pair it with the Swept vs FFT race in Fourier and FFT.
- **Find My, Explained.** How Apple finds your people, your phone and your things, including the AirTag in your suitcase, and what you should turn on before your next trip.

We will be adding more of these guided lessons in the future. If there are other lessons you like to teach your students, please contact Keith@wlanpros.com and he'll work with you to get your ideas incorporated into a future update.

### RF and Propagation

- **FSPL Simulator.** Free-space path loss against distance for 2.4, 5 and 6 GHz on one chart, with a Why panel that splits each band's loss into the part every band shares and the part that changes with frequency. Up and Down double and halve the distance, so each press shows the 6 dB per doubling rule. Log and Linear switch the distance axis: on log the bands are straight lines, on linear they are the curve students usually expect.
- **Wi-Fi Through a Wall.** One wave meets one wall: part reflects, the wave gets smaller as the material absorbs it, and the same wave continues behind the wall, smaller. The frequency never changes. Up and Down change the thickness.
- **Multipath Simulator.** Why the signal changes when you move a few centimeters: the direct signal and its reflections arrive with different phases and add like arrows. Up and Down move the receiver a sixteenth of a wavelength, so a few presses walk from a peak into a null.
- **Room Propagation.** An AP, walls and doorways on a floor plan, colored by received power, with the loss at a spot split into free space, walls and diffraction for each band.
- **Antenna Pattern.** A radiation pattern in 3D beside the two cuts a datasheet prints. Space spins it. Turn up the gain on an omni and watch it flatten, then flip between ceiling and wall mounting.
- **Rate vs Range.** One ring per MCS around an AP, and the cell edge set by the minimum basic rate. Up and Down move the client out and in.
- **6 GHz Power and PSD.** The most power each 6 GHz device class may radiate, and the SNR it leaves, against channel width. Up and Down step the width, which shows when a wider channel keeps its SNR and when it loses 3 dB per doubling.
- **Why Two Devices Disagree.** Two devices at the same spot, hearing the same AP, report different signal strength. The true power is held fixed and each device reports it its own way, with an offset, grip and orientation loss. Ask the room which one is right before you press Reveal. Space re-samples; Up and Down move the AP a meter.
- **Uplink vs Downlink.** Both directions of one link at once: the two ends usually transmit at different power, so each can hear the other over a different distance, and the shaded band between the two rings is where the link is lopsided. Up and Down move the client; M turns the AP down to match and back, which answers "should I just turn the AP down?"
- **Body Loss.** An auditorium, one AP, a person holding a device and up to 50 other people. Turn the holder's back to the AP and watch their own body take the signal; fill the room and watch the crowd take more. Left and Right turn the holder; Space empties or fills the room.

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
- **Multicast at the Basic Rate.** Why a multicast stream can eat the channel: it goes at a basic rate with no acknowledgment and no retry, so the same bytes take many times the airtime of unicast. Compare the stream with the same stream converted to unicast. Up and Down change the basic rate.
- **Channel Utilization Meter.** The number an AP puts in its beacon as channel utilization, how it is averaged, and what it does not tell you. Space runs the channel; Up and Down change the number of senders; B adds a one-second burst.
- **Legacy Protection Cost.** What one silent 802.11b device costs a modern network: a slow protection frame in front of every modern frame, and a longer slot time. A 54 Mb/s laptop's ceiling roughly halves. The beacon inspector shows the protection bits switch on.

### Network Design and Security

- **Channel Planner.** Access points on a floor with channels and widths, showing which ones share airtime. Up and Down change the channel width for every AP at once; try the Auto-plan.
- **Roaming Walk.** A client walks a floor of APs, and the screen shows when it roams and what each roam costs. Up and Down move the roam trigger, so you can make a sticky client and a client that bounces between APs.
- **DFS and Radar.** One AP on a simulated one-hour clock: the channel availability check, a radar event (press D), the move, and the 30-minute lockout.
- **802.1X and EAP Ladder.** An 802.1X connection one message at a time across the client, the AP and the RADIUS server, for EAP-TLS, PEAP, EAP-TTLS, and PSK and SAE for contrast. Right sends the next message; Left takes one back. Roam mode plays a roam instead of a first connection, so you can compare a full 802.1X reconnect with a fast roam.
- **Joining a Network, Frame by Frame.** Every frame a client sends and receives to join a network, from the first scan to the first useful packet: authentication, association, the 4-way handshake, DHCP, then ARP and DNS, with a timeline of how long each phase takes. Right sends the next frame; Left takes one back.
- **Adjacent Channels and AP Stacking.** Why a channel that does not overlap yours still hurts when the other radio is close: its transmit mask leaks into your channel, and distance is what saves you. Start with the question of two APs 30 cm apart. Up and Down move the neighbor.
- **Band Steering.** Why a dual-band client so often stays on 2.4 GHz, and what an AP can and cannot do about it. The client chooses; the AP can only hide, refuse or suggest, and none of those stops the 2.4 GHz beacons. Space walks the client; Up and Down move it 5 m.
- **Survey Walk.** Why walking speed matters in a site survey: a scanner visits one channel at a time, so each channel's samples land far apart when you walk fast. White on the map means no data, never no coverage. Up and Down change the walking pace.
- **Heat Map Builder.** Build a heat map from samples you place, and see which cells are measurements and which are guesses. Change the interpolation, average in dB or in milliwatts, and watch the map change. Up and Down move the guess range; E switches between the heat map, the truth and the error.
- **Predict, Then Measure.** Test a predictive design against the building with an AP on a stick. Every wall loss in a prediction is a claim; walk the floor and see which walls the design got wrong, and which your walk never tested. Space reveals the truth; B walks both sides of every wall.
- **Where Am I?** Find a device two ways, by signal strength and by round-trip timing (FTM), and see how far off each one is. B blocks one AP's direct path, which throws both estimates off in different ways.
- **Repeaters and Mesh Backhaul.** What relaying costs: each hop's rate and throughput, and why a same-channel repeater makes every frame cross the air twice while a dedicated backhaul does not. Up and Down add or remove a relay.

### Course Handouts

Built-in, zoomable copies of WLAN Pros published reference cards: the 2.4, 5 and 6 GHz channel allocations (including the 6 GHz card with GVP), the MCS index, Troubleshooting Causes, the Bubble Diagram, and the four checklists. Put one on the projector while you talk through it, and students have the same card in their own copy of the app.

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
- **Why clients misbehave.** Why Two Devices Disagree, then Uplink vs Downlink, then Band Steering.
- **Where the airtime goes.** Multicast at the Basic Rate, then Channel Utilization Meter, then Legacy Protection Cost.
- **Surveys and heat maps.** Survey Walk, then Heat Map Builder, then Predict, Then Measure.
- **Joining and roaming.** Joining a Network, Frame by Frame, then the 802.1X ladder in roam mode, then Roaming Walk.
- **Find My.** The Find My, Explained lesson, with Figure 3 (where the dot on the map comes from) as the Wi-Fi hook for a Wi-Fi audience.

## What the numbers are, and what they are not

The simulators are built from the IEEE 802.11 standard, ITU recommendations and FCC and ETSI rules, and each tool's help says where its numbers come from. Some values are teaching models rather than measurements, and the screens say so where that is the case: a success curve that stands in for a real radio, a timing chosen to illustrate, the receiver sensitivities that are conformance floors real radios beat. When a student asks "is that what my AP does?", the answer is often "this is the mechanism; your AP's numbers will differ", and the tool's help tells you which parts are which.

## After class

Students have the same app. Point them to the Wi-Fi Classroom on a laptop or tablet, and suggest they repeat the demonstrations you did, changing one control at a time. The handouts give them the cards to keep, and the Field Manual in the app documents every tool in detail. 
