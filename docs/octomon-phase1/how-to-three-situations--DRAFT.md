# How to use the Toolbox in three situations (DRAFT)

Draft for Keith's review, from octomon review recommendation 6(a). Not published. It uses only what the app does today (version 1.14.0 plus this branch). Situation 1 is written for doing it by hand; if Phase 2 (remembering what is normal for each network) is built, that section gets shorter.

---

## 1. Learn your home network

You can't tell whether 41 ms is bad until you know what your network usually does. Learn that on a good day, before something goes wrong.

1. **Run Check My Connection when things feel normal.** Do it in the rooms you use most, at a quiet time and again in the evening when everyone is streaming.
2. **Keep a copy each time.** Tap "Copy these details" and paste it into a note with the date and the room. A few of these are your "normal."
3. **Trace the path once.** On a Mac or PC, run Traceroute (System) to `1.1.1.1`. Hop 1 is your router. If hop 1 shows no response but the hops after it answer, that's normal for many routers: it ignores probes sent to itself and still passes your traffic. The app says so in a note under the hops.
4. **Write down your router's address.** Ping, Ping Plotter and Traceroute offer it as a one-tap target, so you will recognize it later. If you ping it and it never answers, the app tells you that many routers ignore pings sent to themselves and suggests Traceroute to check the path past it.

## 2. Diagnose a problem right now

Something is slow or dropping. Find out which side it is on before you call anyone.

1. **Run Check My Connection where the problem is happening.** The verdict tells you whether it looks like your Wi-Fi, your internet, both, or neither. "How the verdict is judged" explains exactly how it decides.
2. **Compare with your normal.** Hold the new numbers up against the copies you kept. "Delay 41 ms, usually 9 ms here" is something you can act on.
3. **Watch it for a few minutes if it comes and goes.** Ping Plotter charts every reply as it happens, so a burst of loss or a jump in delay shows up as it happens. Run it to your router first, then to `1.1.1.1`. Trouble on both points at the Wi-Fi; trouble only on the second points past your router.
4. **Pass it on.**
   - To your IT team or internet provider: "Copy these details" gives them the full report.
   - To a forum or social post: "Copy for a public post" gives the same report with your public IP address, approximate location, network name, AP name and BSSID taken out.

## 3. A network you don't trust

A hotel, an airport, a conference, a coffee shop. You didn't set it up and you don't know who did.

1. **Run Check My Connection first.** If it says "Sign in to this network," there is a sign-in page between you and the internet. Open a browser and finish signing in, then run the check again. The lesson "Connected, No Internet: Captive Portals" explains why full bars can still mean no internet.
2. **Look at the Security row** in the Wi-Fi details. "Open (no encryption)" means anyone nearby can see your traffic that isn't already encrypted. The Public Wi-Fi lesson shows what that person can and can't see.
3. **Expect the router to ignore you.** Many hotel and conference routers don't answer pings or traceroute probes sent to themselves, by policy. If the hops past it answer, the router is passing your traffic.
4. **If you post about it,** use "Copy for a public post" so the network name, your address and your location stay out of the post.

---

## Notes for the reviewer

- Situation 3 stops short of "which ports does this network let out" (VPN, video calls). That is the Phase 3 outbound port check; it does not exist yet, so this page doesn't promise it.
- Ping Plotter's step in situation 2 assumes it is available on the platform; it is listed per platform in its own help entry.
- Keith ruled on 13 November that "Check My Connection" is the name everywhere. The help file, the in-app guides, the "Open" buttons and the lesson links now say so. The screen's own title bar says "Check My Connection" too (checked on main e264bd92, 17 November); the App Store description and release notes were renamed on 17 November.
