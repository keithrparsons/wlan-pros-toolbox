# WLAN Pros Toolbox: A Guide for Everyone

Most slow Wi-Fi complaints come down to one question: is it the Wi-Fi inside your home or office, or the internet connection coming in from outside? This app answers that question in plain English, with one tap, and it does it without asking you to understand a single piece of Wi-Fi jargon. That is the whole promise. Everything else in here is a bonus.

I built the WLAN Pros Toolbox so that the next time your video call freezes or a page won't load, you have a friendly, honest tool in your pocket that tells you what is actually going on. You do not need to be a network engineer. You do not need an account. You do not need to pay. Open it, tap, read the answer.

## What this app is, and who it's for

The WLAN Pros Toolbox is a free app for your iPhone and your Mac. It is packed with more than 100 small tools that read your connection, run quick tests, and look things up. Some of those tools are for full-time Wi-Fi professionals, and they are deep. Some of them, though, are for anyone who has ever stared at a spinning loading wheel and wondered why.

This guide is written for the rest of us. The teacher whose classroom Wi-Fi drops every afternoon. The office manager fielding "the internet is down again" for the third time today. The small-business owner whose card reader keeps timing out. The curious person who just wants to know what all those numbers mean. If that's you, you're in the right place.

A few things worth knowing up front:

- The app is free. There is no paid version waiting to upsell you.
- There is no account and no login. Nothing to sign up for, nothing to remember.
- Most of it works with no internet at all. The reference cards, the calculators, and the lookups that don't need a live connection all keep working on a plane, in a basement, or anywhere your signal drops.
- It does not collect your personal data. It reads your own connection to answer your own questions, and that stays on your device.

Throughout this guide, when I have to use a technical word, I'll explain it in one plain sentence the first time it shows up. Wi-Fi has a lot of jargon. You don't need most of it. You need a tool that respects your time and tells you the truth.

## Start here: Check My Connection

When you open the app, you'll see a "Check My Connection" button right on the front page. Tap it. It takes you to a tool called Test My Connection, and this is the one I'd point almost everyone to first.

Here is what it does. It runs two quick checks at the same time. One looks at your Wi-Fi, the wireless link between your device and the box on your wall or ceiling that broadcasts your network. The other looks at your internet, the connection that box has to the wider world. Then it tells you, in a single plain headline, which side looks healthy and which side looks like the problem.

You'll see two small status labels, one for Wi-Fi and one for Internet, and a headline at the top. The headline is one of a few honest answers:

- "Looks like your Wi-Fi" means the wireless link in your space is the weak point.
- "Looks like your Internet" means the connection coming into your building is the weak point.
- "Both look fine" means the app couldn't find anything wrong with either side, which usually points you toward the specific app or website you were using, not your connection at all.
- "Couldn't check everything" or "Make sure you're on Wi-Fi and try again" means the app couldn't get a full reading, so rather than guess and risk being wrong, it tells you so. I'd rather give you an honest "I'm not sure" than a confident wrong answer.

Notice the wording: "Looks like." The app hedges on purpose. It is giving you the most likely answer based on what it measured, not a courtroom verdict. The two separate labels for Wi-Fi and Internet are there to teach the single most useful idea in this whole app: your Wi-Fi and your internet are two different things, and only one of them is usually the culprit.

The best part for everyday use: when something is wrong, the tool also tells you what to say when you call support. No more "it's just slow." You'll have a clear starting point.

### One note for iPhone owners

Apple limits what any app is allowed to read about your live Wi-Fi connection on an iPhone. To work around that fairly, the app uses a small free helper from Apple's own Shortcuts app. The first time you run a live Wi-Fi test on iPhone, the app will offer to set this helper up for you. It's a one-time step. Once it's in place, the live readings flow through cleanly. On a Mac, you don't need any of this; the readings come straight through.

If you skip the helper on iPhone, the tool still works. It just measures your internet honestly and tells you it couldn't read the Wi-Fi side, rather than pretending.

## A tour of the app, section by section

The Toolbox is organized into four areas. I'll walk you through them in the order that matters most to a normal user, spending the most time on the tools you'll actually touch.

### Test Network: the everyday answers

This is the heart of the app for most people. Four tools, all about your live connection right now.

**Test My Connection** is the front-door tool we just covered. For most questions, start and end here.

**Network Quality** is the next step up. Where Test My Connection gives you a plain verdict, this one shows you the details behind it. It measures several things about your internet at once and grades each one on its own:

- How fast a request gets answered, the delay before anything happens. Lower is better.
- How steady that delay is. A jumpy connection is worse than a slow-but-steady one, especially for video calls.
- How many requests get lost along the way. You want zero.
- How fast you can download and upload.
- How well the connection holds up when it's busy.

Each of these gets its own grade, from Excellent down to Poor. There is no single combined "score," and that's deliberate. A connection can be excellent at one thing and poor at another, and lumping them into one number would hide exactly the detail you need. Reach for this tool when "is it fast?" isn't a specific enough question.

One honest note printed right on the screen: these are the app's own measurements, not a reading from any other speed-test service. The numbers are real and the method is sound. They just won't always match the exact figure another app gives you, because every tester measures a little differently.

**Wi-Fi Information** shows what your wireless connection is actually doing right now: which network you're on, how strong the signal is, which channel it's using, and how fast the link is running. If you've ever wanted to confirm that you're really on the fast network and not the slow guest one, this is the tool. On iPhone it uses the same one-time Shortcuts helper described above. The signal strength reading here is the one I'll teach you to read in the next section.

**Cellular Information** (iPhone only) shows what your phone's mobile connection is doing: your carrier, whether you're on 5G or LTE, your signal bars, and whether you're roaming. Handy when you want to know whether your phone quietly fell back to cellular because the Wi-Fi gave out. The signal here is shown as bars, the same 0-to-4 scale you already know from the top of your screen, and the app is careful never to dress those bars up as something more precise than they are.

### Networking Tools: looking things up and tracking things down

This is the largest working section, 22 tools, and it leans more technical. Most people won't need most of them, but a handful are genuinely useful for anyone, so I'll call those out.

**Interface Information** answers "what's my address on this network?" Every device on a network has an address, the way every house on a street has a number. This tool shows yours, along with the name of your network and which connection you're using. It's the first thing a tech-support person often asks for.

**Device Info** is the companion: what device is this, how much memory it has, and how long it's been running since the last restart. Useful when support asks, or when you just want to confirm the model.

**Network Discovery** and **Ping Sweep** find the other devices on your local network, the printers, smart speakers, cameras, and computers all sharing your Wi-Fi. Network Discovery is the friendlier of the two; it tries to name each device and guess what it is. If you've ever wondered "what is actually connected to my network?", start there. The app is honest when it can't identify something; it will say "Unknown" rather than make up a name.

**Ping (TCP)** and **Ping Plotter** test whether a website or device is reachable and how quickly it responds. "Ping" is just a quick knock on the door to see if anyone answers and how long they take. Ping Plotter goes further and draws the response as a live graph over time, so you can watch whether a connection is steady or flaky. If your video calls drop intermittently, a Ping Plotter graph pointed at a reliable site will often show the dropouts as they happen.

**My Current Location** and **IP Geolocation** deal with where things are. The first reads your device's own location. The second looks up roughly where an internet address is in the world and who runs it.

The rest of this section, the various lookups, scanners, and inspectors, are built for IT folks chasing specific problems: checking a website's security certificate, tracing the path data takes across the internet, looking up who owns a domain name. They're powerful and they're honest about their limits. If a tool can't read something on your particular device, it says so plainly instead of faking a result. If you're not chasing that kind of problem, you can happily ignore this corner.

### Calculators and Tools: the math, done for you

26 tools here. The bulk of them are radio-engineering calculators, the kind a Wi-Fi professional uses to plan a network: signal loss over distance, antenna aiming, power budgets, coverage math. If those words mean nothing to you, that's fine, they're not meant for you, and you'll lose nothing by skipping them.

A few in this section, though, are useful to anyone:

- **Metric Conversion** and **Unit Converter** convert between units, the everyday kind plus a few technical ones.
- **QR Code Generator** turns any text or web address into a QR code you can show or share. Handy for sharing your guest Wi-Fi, a link, or your contact info.
- **DTMF Generator** plays the tones a phone keypad makes. A small thing, occasionally exactly what you need.

For the professionals reading this, the rest of this section is your link-budget and propagation kit: free space path loss, EIRP, Fresnel zone, link budget, noise floor, rain fade, point-to-point checks, throughput, downtilt, earth curvature, attenuation, PoE budget, and the coordinate and conversion helpers. Each one shows the formula it runs and a worked example. They put the whiteboard math in your pocket.

### Quick Reference: the cheat sheets

This is the biggest section by count, 49 reference cards, and most of it is exactly what the name says: lookup tables for working professionals. Channel charts, cable pinouts, protocol codes, connector types, command cheat sheets, and more. For the pros, these put years of memorized tables at your fingertips, offline, in the field. If you fix Wi-Fi for a living, you already know which ones you want.

For everyone else, a few of these cards are genuinely worth a look:

- **How Strong Is Wi-Fi, Really?** explains signal strength in plain terms, the same idea I'll cover in the next section.
- **Signal Thresholds** is the quick "is my signal good enough for video calls?" reference.
- The **Wi-Fi Glossary** defines the jargon you'll run into anywhere, in plain language. If a word in another app or a support call confuses you, look it up here.
- The **checklists**, like the Wi-Fi Connection Checklist, walk you through what to check when something's wrong, step by step.

The rest of the reference cards are deep professional material. They're there when you need them and out of the way when you don't.

## How to read the results

A few numbers in this app come up again and again. Once you can read them, the whole app gets friendlier. Here are the two that matter most.

### Signal strength

Wi-Fi signal strength is measured on a scale that runs in negative numbers, and the unit is called dBm. Here's the only thing you need to remember: the number is negative, and closer to zero is stronger. So -55 is a stronger signal than -75, the same way 5 degrees below zero is warmer than 25 degrees below zero. A bigger negative number is a weaker signal.

Here is the plain-English scale for what those numbers mean:

| Signal reading | What it means |
|---|---|
| Stronger than -55 | Excellent. Everything will work, including video calls and large downloads. |
| -55 to -65 | Good. Comfortable for normal use, including streaming and calls. |
| -65 to -75 | Fair. Fine for browsing and email; calls and video may start to struggle at the lower end. |
| -75 to -80 | Weak. Expect slowdowns and dropped connections. Time to move closer or improve coverage. |
| Weaker than -80 | Poor. Often unusable. You're too far from the source or there's too much in the way. |

If your signal is sitting in the Weak or Poor range, the most common fixes are simple: get closer to the box that broadcasts your Wi-Fi, remove obstructions between you and it, or, if a whole area is always weak, that's a sign the coverage in your space needs help.

### Speed and responsiveness

When the Network Quality tool grades your connection, two ideas drive most of what you'll feel day to day.

Speed is how fast data moves, usually shown in Mbps. Higher is better. For a single person browsing and on calls, you need far less than most people assume. Speed only becomes the problem when many people or devices are all pulling at once, or when you're moving very large files.

Responsiveness is how quickly the connection reacts, especially when it's busy. This is the quiet hero. A connection with big speed numbers can still feel terrible on video calls if it reacts slowly under load, and a modest connection that stays responsive can feel great. When calls stutter but speed tests "look fine," responsiveness is usually where the truth is hiding.

The grades, Excellent through Poor, are calibrated for normal household and small-office use. Read each grade on its own. A connection that's Excellent on speed and Poor on responsiveness is telling you something specific, and that's the point of grading them separately.

## A friendly closing

The next time your connection acts up, you don't have to guess and you don't have to call someone and say "it's just slow." Open the WLAN Pros Toolbox, tap Check My Connection, and read the answer. Most of the time, that one tap tells you whether to restart your router, move closer to it, or call your internet provider, and that alone saves you a frustrating afternoon.

Everything past that first tap is there when you're ready for it. The signal readings, the device list, the quality grades, the cheat sheets. You can learn as much or as little as you like, at your own pace, and the app will always tell you the truth about what it can and can't see. That honesty was the point from the start.

Welcome to the Toolbox. I hope it makes your Wi-Fi a little less mysterious.

Keith R. Parsons  
Wireless LAN Professionals, Inc.
