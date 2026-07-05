# WLAN Pros Toolbox: How This App Works

_A 5-minute tour of the app · app v1.5.4 · updated 2026-07-05_

This is a quick map of the app: what's in it, where things live, and which parts are for you. It is not a Wi-Fi lesson. If you want to understand and fix your own Wi-Fi, open the free book "Fix Your Own Wi-Fi" from the front page; that book does the teaching. This guide just shows you around the software.

I built the WLAN Pros Toolbox so that the next time your video call freezes or a page won't load, you have a friendly, honest tool in your pocket that tells you what is actually going on. You do not need to be a network engineer. You do not need an account. You do not need to pay. Open it, tap, read the answer.

## What this app is, and who it's for

The WLAN Pros Toolbox is a free app for iPhone and Mac. It is packed with more than 100 small tools that read your connection, run quick tests, and look things up. Some of those tools are for full-time Wi-Fi professionals, and they are deep. Some of them, though, are for anyone who has ever stared at a spinning loading wheel and wondered why.

This guide is written for the rest of us. The teacher whose classroom Wi-Fi drops every afternoon. The office manager fielding "the internet is down again" for the third time today. The small-business owner whose card reader keeps timing out. The curious person who just wants to know where to tap. If that's you, you're in the right place.

A few things worth knowing up front:

- The app is free. There is no paid version waiting to upsell you.
- There is no account and no login. Nothing to sign up for, nothing to remember.
- Most of it works with no internet at all. The reference cards, the calculators, and the lookups that don't need a live connection all keep working on a plane, in a basement, or anywhere your signal drops.
- It does not collect your personal data. It reads your own connection to answer your own questions, and that stays on your device.

## Start here: Check My Connection

When you open the app, you'll see a "Check My Connection" button right on the front page. Tap it. It takes you to a tool called Test My Connection, and this is the one I'd point almost everyone to first.

Here is what it does. It runs two quick checks at the same time. One looks at your Wi-Fi, the wireless link between your device and the box on your wall or ceiling that broadcasts your network. The other looks at your internet, the connection that box has to the wider world. Then it tells you, in a single plain headline, which side looks healthy and which side looks like the problem.

You'll see two small status labels, one for Wi-Fi and one for Internet, and a headline at the top. The headline is one of a few honest answers:

- "Looks like your Wi-Fi" means the wireless link in your space is the weak point.
- "Looks like your Internet" means the connection coming into your building is the weak point.
- "Both look fine" means the app couldn't find anything wrong with either side, which usually points you toward the specific app or website you were using, not your connection at all.
- "Couldn't check everything" or "Make sure you're on Wi-Fi and try again" means the app couldn't get a full reading, so rather than guess and risk being wrong, it tells you so. I'd rather give you an honest "I'm not sure" than a confident wrong answer.

When something is wrong, the tool also tells you what to say when you call support. No more "it's just slow." You'll have a clear starting point.

### One note for iPhone owners

Apple limits what any app is allowed to read about your live Wi-Fi connection on an iPhone. To work around that fairly, the app uses a small free helper from Apple's own Shortcuts app. The first time you run a live Wi-Fi test on iPhone, the app will offer to set this helper up for you. It's a one-time step. Once it's in place, the live readings flow through cleanly. On a Mac, you don't need any of this; the readings come straight through.

If you skip the helper on iPhone, the tool still works. It just measures your internet honestly and tells you it couldn't read the Wi-Fi side, rather than pretending.

## Wi-Fi vs Cellular vs Internet: what's the difference?

Most people use "Wi-Fi" and "the internet" as the same word. They are two different things, and cellular is a third. Knowing which of the three is having a bad day is the difference between a 30-second fix and a wasted afternoon on hold with someone who can't help you.

Here they are, plain:

- Wi-Fi is the wireless link between your device and your router, inside your home or office.
- The internet is the worldwide network your provider delivers to your building.
- Cellular is your phone's connection to the carrier's towers, a separate path to that same internet.

Three different things. Let's walk each one.

### Think of it as roads

Picture your street.

Wi-Fi is the road inside your neighborhood. It connects your house to the entrance and no farther.

The internet is the highway system out past that entrance, the roads that reach every other town.

Cellular is a different on-ramp to those same highways, one you can take when you're away from the neighborhood or the neighborhood road is blocked.

One set of roads. That picture will carry you through the rest.

### Wi-Fi: the link inside your building

Wi-Fi covers the short hop from your phone or laptop to your router. That's it. It's the neighborhood road.

Strong Wi-Fi means that short hop is clean and fast. Your device and your router are talking clearly.

Here's what trips everyone up: Wi-Fi does not reach the internet on its own. It carries your traffic to the router, and the router hands that traffic to the internet feed. Full Wi-Fi bars tell you the hop to the router is good. They tell you nothing about whether the internet behind the router is working.

### The internet: the feed from outside

The internet is the connection your provider, your ISP, runs into your building. One connection comes in. Your router shares that one connection with every device in the house, over Wi-Fi and over the network cables.

This is the highway system. When people say "the internet is down," they usually mean this feed is blocked, even though every road inside the neighborhood is perfectly fine.

You pay your ISP for a certain speed on this feed. If that speed is slow, or the feed drops, no amount of great Wi-Fi will fix it. The neighborhood road can be freshly paved and empty. If the highway is jammed, you still don't get anywhere.

### Cellular: a different road to the same place

Your phone has a second way to reach the internet that has nothing to do with your Wi-Fi or your router. It talks to your carrier's cell towers over the air, and the carrier connects it to the same internet everyone else uses.

That's the other on-ramp. When your Wi-Fi is off, or you walk out of range of your router, your phone switches to cellular on its own. Same highways, different way in.

### Look at the top of your screen

Glance at the top of your phone. You read two little meters up there all day without thinking about them, and there is a third you never get to see.

![A diagram titled "Two signals you can see. One you can't." The top row shows the Wi-Fi signal meter climbing from no bars to full arcs; the middle row shows the cellular signal meter climbing from none to four bars. A highlighted panel shows a third meter, a dashed globe for the internet feed, that your phone never displays, which is why full bars can still mean nothing loads, and why the Test My Connection tool exists.](assets/guides/signal-meters.png)

The Wi-Fi symbol, those stacked arcs, measures the strength of the hop to your router. More arcs, a cleaner link to the neighborhood road. It tells you nothing about the internet behind it.

The cellular bars measure the strength to the nearest tower. More bars, a stronger path to the carrier.

Here is the catch that explains everything: there is no internet meter. Your phone will happily show full Wi-Fi arcs and full cellular bars while the internet itself is down, because it has no icon for the health of the feed coming into the building. That missing third meter is exactly why "full bars, nothing loads" fools people, and it is the gap the Test My Connection tool fills. It runs the check your status bar cannot.

### The confusions this clears up

**Full Wi-Fi bars, but nothing loads.** Your phone has a clean link to the router, and the internet feed behind the router is down or crawling. The bars measure the neighborhood road, not the highway. This exact question is what the Toolbox's Test My Connection answers for you.

**Great signal, still slow.** Same idea, gentler. Your Wi-Fi is fine and the page still takes forever. The limit is the internet plan or the provider, not the Wi-Fi in your living room. Standing closer to the router won't help, because the router was never the problem.

**Turning Wi-Fi off "fixes" it.** You've probably done this. A page won't load, you switch Wi-Fi off, and suddenly your phone works. Wi-Fi didn't break anything. When you turned it off, your phone stopped trying the dead Wi-Fi path and jumped to cellular, which had a working road to the internet the whole time.

### Modem, router, ISP: who does what

Three pieces sit between your phone and the wider internet. One line each:

- The ISP is the company you pay to deliver the internet to your building.
- The modem is the box that turns the ISP's incoming signal into data your network can use.
- The router is the box that shares that one internet connection with all your devices and creates your Wi-Fi.

In many homes the modem and router are the same box, which is part of why the two jobs blur together. They are still two jobs.

### How to tell which one is your problem

When something's wrong, ask one question first: is the neighborhood road bad, or is the highway bad?

- If one device is slow but the others are fine, look at that device and its Wi-Fi.
- If everything on the Wi-Fi is slow at once, suspect the internet feed or the provider.
- If your phone works the moment you turn Wi-Fi off, the Wi-Fi path is the trouble, not the internet.

You don't have to guess at it. The Test My Connection tool in the WLAN Pros Toolbox runs the check and tells you plainly: is it your Wi-Fi, or is it your internet? That one answer decides who you call and saves you the afternoon on hold.

Wi-Fi, the internet, and cellular are three different things. Get clear on which one is failing, and you fix the right problem the first time.

## A tour of the app, section by section

The Toolbox is organized into four areas. I'll walk you through them in the order that matters most to a normal user, spending the most time on the tools you'll actually touch.

### Test Network: the everyday answers

This is the heart of the app for most people. Four tools, all about your live connection right now.

**Test My Connection** is the front-door tool we just covered. For most questions, start and end here.

**Network Quality** is the next step up. Where Test My Connection gives you a plain verdict, this one shows you the details behind it, grading several things about your internet at once. Each gets its own grade, from Excellent down to Poor, with no single combined "score." Reach for this tool when "is it fast?" isn't a specific enough question.

**Wi-Fi Information** shows what your wireless connection is actually doing right now: which network you're on, how strong the signal is, which channel it's using, and how fast the link is running. If you've ever wanted to confirm that you're really on the fast network and not the slow guest one, this is the tool. On iPhone it uses the same one-time Shortcuts helper described above.

**Cellular Information** (iPhone only) shows what your phone's mobile connection is doing: your carrier, whether you're on 5G or LTE, your signal bars, and whether you're roaming. Handy when you want to know whether your phone quietly fell back to cellular because the Wi-Fi gave out.

### Networking Tools: looking things up and tracking things down

This is the largest working section, and it leans more technical. Most people won't need most of them, but a handful are genuinely useful for anyone, so I'll call those out.

**Interface Information** answers "what's my address on this network?" It's the first thing a tech-support person often asks for.

**Device Info** is the companion: what device is this, how much memory it has, and how long it's been running since the last restart. Useful when support asks, or when you just want to confirm the model.

**Network Discovery** and **Ping Sweep** find the other devices on your local network, the printers, smart speakers, cameras, and computers all sharing your Wi-Fi. Network Discovery is the friendlier of the two; it tries to name each device and guess what it is. If you've ever wondered "what is actually connected to my network?", start there.

**Ping (TCP)** and **Ping Plotter** test whether a website or device is reachable and how quickly it responds. Ping Plotter draws the response as a live graph over time, so you can watch whether a connection is steady or flaky.

**My Current Location** and **IP Geolocation** deal with where things are. The first reads your device's own location. The second looks up roughly where an internet address is in the world and who runs it.

The rest of this section, the various lookups, scanners, and inspectors, are built for IT folks chasing specific problems: checking a website's security certificate, tracing the path data takes across the internet, looking up who owns a domain name. If you're not chasing that kind of problem, you can happily ignore this corner.

### Calculators and Tools: the math, done for you

The bulk of this section is radio-engineering calculators, the kind a Wi-Fi professional uses to plan a network. If those words mean nothing to you, that's fine, they're not meant for you, and you'll lose nothing by skipping them.

A few in this section, though, are useful to anyone:

- **Metric Conversion** and **Unit Converter** convert between units, the everyday kind plus a few technical ones.
- **QR Code Generator** turns any text or web address into a QR code you can show or share. Handy for sharing your guest Wi-Fi, a link, or your contact info.
- **DTMF Generator** plays the tones a phone keypad makes. A small thing, occasionally exactly what you need.

For the professionals reading this, the rest of this section is your link-budget and propagation kit: free space path loss, EIRP, Fresnel zone, link budget, noise floor, rain fade, point-to-point checks, throughput, downtilt, earth curvature, attenuation, PoE budget, and the coordinate and conversion helpers. Each one shows the formula it runs and a worked example.

### Quick Reference: the cheat sheets

This is the biggest section by count, and most of it is exactly what the name says: lookup tables for working professionals. Channel charts, cable pinouts, protocol codes, connector types, command cheat sheets, and more. If you fix Wi-Fi for a living, you already know which ones you want.

For everyone else, a few of these cards are genuinely worth a look:

- **How Strong Is Wi-Fi, Really?** and **Signal Thresholds** explain signal strength in plain terms and answer "is my signal good enough for video calls?"
- The **Wi-Fi Glossary** defines the jargon you'll run into anywhere, in plain language. If a word in another app or a support call confuses you, look it up here.
- The **checklists**, like the Wi-Fi Connection Checklist, walk you through what to check when something's wrong, step by step.

The rest of the reference cards are deep professional material. They're there when you need them and out of the way when you don't.

## Where to go next

That's the whole app in five minutes: tap Check My Connection on the front page for the everyday answer, and dip into the four sections when you want more. Most of the time, that one tap on the front page tells you whether to restart your router, move closer to it, or call your internet provider.

If you want to actually understand your Wi-Fi, and fix it yourself, open the free book "Fix Your Own Wi-Fi" from the front page. This guide maps the app; the book teaches the Wi-Fi. Between the two, you've got the answer and the understanding.

Welcome to the Toolbox. I hope it makes your Wi-Fi a little less mysterious.

Keith R. Parsons  
Wireless LAN Professionals, Inc.
