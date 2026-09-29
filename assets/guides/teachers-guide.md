# Wireless Classroom · Teacher's Guide

The Wireless Classroom is the part of the WLAN Pros Toolbox built for teaching. It holds interactive simulators, guided lessons, and the course handouts I use in class. It ships in the same free app your students already have, so whatever you show on the projector, they can open on their own laptop or tablet after class and work through at their own pace.

This guide covers how to present it, what each tool teaches, and a few lesson sequences that work well.

## Before class

**Use a computer or a tablet.** The simulators are designed for a large screen. On a phone they open behind a short notice that says so, with a Continue anyway button. The guided lessons and the handouts work on any screen.

**No Internet needed during class.** The simulators compute everything on the device, and the lessons and handouts are built into the app, so a room with poor Wi-Fi does not stop the lesson. Install or update the app before class, and open the Wireless Classroom once to check it is all there.

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

Some tools add their own keys, and ? always lists them:

| Tool | Its own keys |
|---|---|
| Fourier and FFT | 1 to 4 switch modes; W changes the FFT window |
| DFS and Radar | D fires a radar event |
| 802.1X and EAP Ladder; Association, Frame by Frame | Left takes a message back |
| Multi-Link Operation | N draws new traffic |
| Uplink vs Downlink | P reveals the answer; M turns the AP down to match, and back |
| Body Loss | Left and Right turn the holder; P reveals the answer |
| Channel Utilization Meter | B adds a one-second burst; W skips ahead one window |
| Heat Map Builder | E switches heat map, truth and error; W shows the hidden wall; P steps the power; N is the next step |
| Predict, Then Measure | Space reveals the truth; M steps through the maps; B walks both sides of every wall; O walks one side |
| Where Am I? | M (or Tab) switches the method; B blocks one AP's direct path; P steps the -70 dBm question |

Tools with nothing to play or step ignore Space and the Right arrow.

The bar at the top (title, a light and dark switch, and Exit) hides itself when the mouse is still and comes back when you move it. If the projector washes out the dark theme, switch to light mode.

## A teaching pattern that works: predict, then reveal

Before you press a key, ask the room what will happen. "If I move this client twice as far from the AP, how much signal do we lose?" "If one client drops to 6 Mbps, what happens to everyone else?" Take the guesses, then press the key. The simulators are built so one control makes one visible change, which is exactly what you need for this. Students remember the moment they were wrong far longer than a slide that told them the answer.

## Where each tool is explained

Every tool in the Wireless Classroom has a full entry in the Field Manual, in Educational Resources: what it does, how to drive it, the numbers behind it, and a Teaching it section with what each control is there to show, a three-minute demo that works in front of a room, what to pair it with and what it leaves out on purpose. This guide covers how to run a class; the Field Manual covers each tool.

The Classroom has six shelves: Guided Lessons (read-along lessons, each with one interactive stage or a set of figures), RF and Propagation, Signals and PHY, Airtime and Access, Network Design and Security, and Course Handouts (the WLAN Pros printed reference cards).

## About the labs

The appendix has one lab per simulator. Each lab walks a student through the tool click by click, with a screenshot of every step and a close-up of what to click, so it works without an instructor in the room. Each exercise asks for a prediction first, then shows the answer on screen. Every lab comes in two versions: a student version without the answers, and an instructor version with them.

Use a lab after you have demonstrated the tool in class, as a small-group activity, or as homework. The lesson sequences below list the labs that go with each one.

## Lesson sequences that work

These are starting points. Each takes about half an hour of demonstration and discussion.

- **Why 6 GHz behaves differently.** FSPL Simulator (the extra loss comes from the antenna, not the air), then Wi-Fi Through a Wall, then 6 GHz Power and PSD. Suggested labs: FSPL Simulator, Wi-Fi Through a Wall, 6 GHz Power and PSD.
- **RF math and the link budget.** FSPL Simulator, then the Antenna Fundamentals lesson and Antenna Pattern, then Rate vs Range, then Uplink vs Downlink. Suggested labs: FSPL Simulator, Antenna Pattern, Rate vs Range, Uplink vs Downlink.
- **Why the signal jumps when you move.** Multipath Simulator, then Combine in Many paths to show what extra antennas fix, then Room Propagation's close-up of the nulls near a wall. Suggested labs: Multipath Simulator, Room Propagation.
- **Why is the Wi-Fi slow?** The One Talker per Channel lesson, then Medium Access Simulator, then Airtime Anatomy, then Airtime Fairness, then Rate Adaptation. Suggested labs: Airtime Anatomy, Airtime Fairness.
- **Troubleshooting slow or unstable Wi-Fi.** Channel Utilization Meter, then Rate Adaptation, Airtime Fairness, Multicast at the Basic Rate and Legacy Protection Cost, then Roaming Walk and Why Two Devices Disagree. Suggested labs: Channel Utilization Meter, Multicast at the Basic Rate, Legacy Protection Cost, Why Two Devices Disagree.
- **QoS and contention.** Medium Access Simulator with EDCA priority, then Airtime Anatomy with a different access category, then Power Save for voice latency, then Channel Utilization Meter. Suggested labs: Medium Access Simulator, Airtime Anatomy, Power Save.
- **Antennas.** The Antenna Fundamentals lesson, then Antenna Pattern, then Polarization, then Antenna Pattern's Floor coverage view for mounting height. Suggested lab: Antenna Pattern.
- **Spectrum analysis.** The Spectrum Analysis lesson, then the Swept vs FFT race and OFDM modes in Fourier and FFT. Suggested lab: Fourier and FFT.
- **From bits to rate.** Modulation Simulator, then Rate vs Range, then PHY Preamble Reference. Suggested labs: Modulation Simulator, Rate vs Range.
- **Channels and the rules.** The 2.4, 5 and 6 GHz channel cards in Course Handouts, then Channel Planner, DFS and Radar, 6 GHz Power and PSD, and Adjacent Channels and AP Stacking. Suggested labs: Channel Planner, DFS and Radar, Adjacent Channels and AP Stacking.
- **Designing a cell plan.** Channel Planner, then Roaming Walk, then DFS and Radar. Suggested labs: Channel Planner, Roaming Walk.
- **Wi-Fi 6 and 7 features.** OFDMA Resource Units, then OFDMA vs MU-MIMO, Spatial Reuse, then Multi-Link Operation. Suggested labs: OFDMA Resource Units, Spatial Reuse, Multi-Link Operation.
- **Association and roaming.** The scan, authentication, association and the 4-way handshake, one frame at a time. Association, Frame by Frame, then the 802.1X ladder in roam mode, then Roaming Walk. Suggested labs: Association, Frame by Frame; Roaming Walk.
- **Wi-Fi security modes.** Association, Frame by Frame for the 4-way handshake, then 802.1X and EAP Ladder run once for EAP-TLS and once for PEAP, then PSK and SAE for contrast. Suggested lab: 802.1X and EAP Ladder.
- **Why won't it connect?** Association, Frame by Frame in Why won't it associate?, then Break it in 802.1X and EAP Ladder, then the Rate set panel in Rate vs Range for a client refused over basic rates. Each one stops at the frame where it fails, which is what to look for in a capture.
- **Why clients misbehave.** Why Two Devices Disagree, then Uplink vs Downlink, then Band Steering. Suggested labs: Why Two Devices Disagree, Band Steering.
- **Where the airtime goes.** Multicast at the Basic Rate, then Channel Utilization Meter, then Legacy Protection Cost. Suggested labs: Multicast at the Basic Rate, Legacy Protection Cost.
- **Surveys and heat maps.** Survey Walk, then Heat Map Builder, then Predict, Then Measure. Suggested labs: Survey Walk; Heat Map Builder; Predict, Then Measure.
- **Find My.** The Find My, Explained lesson, with Figure 3 (where the dot on the map comes from) as the Wi-Fi hook for a Wi-Fi audience.
- **Starlink.** The Starlink, Explained lesson, with Figure 9 (two networks in one house) as the Wi-Fi hook for a Wi-Fi audience.

## What the numbers are, and what they are not

The simulators are built from the IEEE 802.11 standard, ITU recommendations and FCC and ETSI rules, and each tool's help says where its numbers come from. Some values are teaching models rather than measurements, and the screens say so where that is the case: a success curve that stands in for a real radio, a timing chosen to illustrate, the receiver sensitivities that are conformance floors real radios beat. When a student asks "is that what my AP does?", the answer is often "this is the mechanism; your AP's numbers will differ", and the tool's help tells you which parts are which.

## After class

Students have the same app. Point them to the Wireless Classroom on a laptop or tablet, and suggest they repeat the demonstrations you did, changing one control at a time. The handouts give them the cards to keep, and the Field Manual in the app documents every tool in detail.

For homework, assign the student version of one lab from the day's sequence. Ask for the predictions they wrote down and one sentence on what surprised them.

## Feedback and new lessons

We will be adding more guided lessons in the future. If there are other lessons you like to teach your students, please contact Keith@wlanpros.com and he'll work with you to get your ideas incorporated into a future update.

