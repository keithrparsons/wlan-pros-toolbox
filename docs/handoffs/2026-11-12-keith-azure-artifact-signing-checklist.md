# Keith's checklist: add Azure Artifact Signing for the Windows installer

Keith's words, 12 Nov 2026, 10:47 AM MT, via Lead: "Yes - please check the prices and then give me the instructions - step by step please - and I'll go and add one so this will be an option for Windows users."

This is for you to do yourself. Nobody else will buy or sign up on your behalf. When you finish, you hand Larry the names listed at the end. Do not put passwords, keys, or secrets in chat or in a file.

Official guides this checklist follows: [Set up Artifact Signing](https://learn.microsoft.com/en-us/azure/artifact-signing/quickstart) and [Assign roles](https://learn.microsoft.com/en-us/azure/artifact-signing/tutorial-assign-roles), both checked 12 Nov 2026. Where I could not verify an exact button label from those pages, it is marked unverified.

## The cheapest option (prices checked 12 Nov 2026)

**Azure Artifact Signing, Basic plan, is the cheapest.** Cost: $9.99 per month per account ($119.88 if you keep it for 12 months), 5,000 signatures a month, then $0.005 each. No hardware token. Works with GitHub Actions.

The Azure pay-as-you-go subscription itself has no monthly fee. You pay only for what you use. Artifact Signing is that usage. A free, trial, or sponsored Azure account will not work; you need a paid pay-as-you-go (or enterprise) subscription. Billing for Artifact Signing starts in full when you create the Artifact Signing account, even before validation finishes, and is not pro-rated.

Sources, all fetched 12 Nov 2026:

- $9.99 / $99.99 figures: [SKU page](https://learn.microsoft.com/en-us/azure/artifact-signing/how-to-change-sku) and [Azure product page](https://azure.microsoft.com/en-us/products/artifact-signing). The [Azure pricing-details page](https://azure.microsoft.com/en-us/pricing/details/artifact-signing/) hides the dollar amounts unless you are signed in.
- Billing start and not pro-rated; paid subscription required: [Artifact Signing FAQ](https://learn.microsoft.com/en-us/azure/artifact-signing/faq).
- Pay-as-you-go has no upfront commitment and charges only for what you use: [Pay as you go](https://azure.microsoft.com/en-us/pricing/purchase-options/pay-as-you-go) ("It costs nothing to start"; "you'll be charged only for what you use beyond your monthly free amounts"; a temporary $1 card authorization may appear and then be removed).

Other official CA prices, for comparison. All need a hardware token or a cloud signing add-on (rule since 1 Jun 2023):

| Option | What the official page says | About per year | Date and source |
| --- | --- | --- | --- |
| Azure Artifact Signing Basic | $9.99 per month, 5,000 signatures | $119.88 | 12 Nov 2026, links above |
| SSL.com OV | $129 per year for the certificate. Key storage is extra: eSigner cloud, cheapest annual tier $180 per year ($15/month, 240 signings), first 30 days free; or a YubiKey at $379 | About $309 per year with eSigner after the free month, or $508 in year one with a YubiKey then $129 | 12 Nov 2026, [SSL.com OV](https://www.ssl.com/products/software-integrity/code-signing/ov/) and [eSigner pricing](https://www.ssl.com/guide/esigner-pricing-for-code-signing/) |
| Certum Standard (company name on the cert) | "price from €139.00" on the product page. Their shop was down (HTTP 503) when checked, so whether a cloud key (SimplySign) costs extra is unverified | From €139, still more than $119.88 at any normal exchange rate | 12 Nov 2026, [Certum code signing](https://www.certum.eu/en/code-signing-certificates/) |
| Sectigo OV | "starts at $536.25 per year" on the five-year plan; shorter terms cost more. A FIPS token is included and shipped each year | $536.25 and up | 12 Nov 2026, [Sectigo code signing](https://www.sectigo.com/ssl-certificates-tls/code-signing) |
| DigiCert OV | Official page was blocked by bot protection on a second fetch. Earlier the same day, the same official page showed a 12-month OV subscription at $528 ($44/month) and EV at $744, with token or KeyLocker options that add more | About $528 and up (fairly sure; could not re-read the live page in the afternoon) | 12 Nov 2026, [DigiCert code signing](https://www.digicert.com/signing/code-signing-certificates) |

**Sure:** Azure Artifact Signing Basic is the cheapest complete option for this job. The next complete CI-friendly package I could fully price is SSL.com OV plus eSigner, about $309 per year.

## Eligibility for Wireless LAN Professionals, Inc.

Use **Organization**, **Public** validation, not Individual. You are signing as the company.

From the official [quickstart prerequisites](https://learn.microsoft.com/en-us/azure/artifact-signing/quickstart), checked 12 Nov 2026:

- Public Trust certificates are available to organizations in the United States, Canada, the European Union, the United Kingdom, Australia, New Zealand, Japan, South Korea, Singapore, Switzerland, Norway, and Israel.
- Individual developers must be in the United States or Canada. That path is not the one you want.
- Organization validation does not require the Azure billing account to be typed as "Organization."
- A D-U-N-S number is not required by this official page. The form asks for "a business identifier." For a US company, your EIN is the usual value. A D-U-N-S number is optional and fine if you already have one.
- The official quickstart does not state a minimum years-in-business or three-year tax-history rule. A Microsoft team comment on 4 Aug 2026 said the three-year rule "is no longer applicable" for organizations in the supported countries ([GitHub issue](https://github.com/Azure/artifact-signing-action/issues/72)). An older Microsoft page, [Sign an MSIX package](https://learn.microsoft.com/en-us/windows/msix/package/signing-package-overview) (still live on 12 Nov 2026), still says organizations need three or more years of verifiable tax history. Those two official pages disagree. Wireless LAN Professionals, Inc. has been operating well over three years, so this is not a blocker either way.
- The service is generally available (Microsoft announced GA on 12 Jan 2026). You are not joining a public preview.
- Processing takes 1 to 20 business days, longer if they ask for more documents. Email verification links expire in seven days. You get three tries to upload extra documents. Documents must have been issued in the last 12 months, and any expiry date must be at least two months away.

I do not see a hard blocker for Wireless LAN Professionals, Inc. Things that can slow or fail validation, from the official page: public records that do not match the legal name and street address you enter; a primary email that is not on a domain the company owns; a website that is not the company's; a name on the ID check that does not match the government ID exactly; email links that expire. Keep legal name, address, website, and emails consistent and current.

## What to have ready

- [ ] Exact legal name: **Wireless LAN Professionals, Inc.** (include the comma and "Inc."). This is what will appear on the certificate. It cannot be customized later.
- [ ] Legal street address (the business address, not a P.O. box).
- [ ] Company website that belongs to the company (for example wlanprofessionals.com).
- [ ] Primary email on a domain the company owns (for example keith@wlanpros.com). This inbox must accept mail with links from outside senders. You will watch it for seven-day links.
- [ ] A different secondary email, on the **same** domain (for example support@wlanpros.com). Distribution lists are allowed.
- [ ] Business identifier: your EIN (or a D-U-N-S number if you prefer).
- [ ] Optional: Microsoft Store Seller ID, from Partner Center, if you want to fill that field. This is not the Store product ID `9NCVHM6ZL4X0`.
- [ ] Government-issued photo ID for you (passport, driver's license, or state ID), in the exact name you will type as first and last name. You will photograph it with your phone.
- [ ] A phone that can take photos and scan QR codes, and the **Microsoft Authenticator** app installed on it.
- [ ] A credit or debit card in your or the company's name (not a prepaid card). Azure may place a temporary $1 hold and then remove it.
- [ ] Company registration papers to have on hand if they ask: articles of incorporation or a current business registration that lists the company name and address, plus a domain registration or renewal invoice. Issued in the last 12 months.

Suggested names (you can change them; write down whatever you actually use):

- Resource group: `rg-wlanpros-signing`
- Artifact Signing account: `wlanpros` (3 to 24 letters and numbers, must start with a letter, must be globally unique; if that name is taken, try `wlanprosinc` or `wlanprostoolbox`)
- Certificate profile: `WLANProsPublic` (5 to 100 letters and numbers)
- Region: **East US** (this is the region Microsoft uses in its own examples). Endpoint you will give Larry: `https://eus.codesigning.azure.net`. Any other supported US region is fine if you prefer; if you pick a different region, use the matching endpoint from the table in the [quickstart](https://learn.microsoft.com/en-us/azure/artifact-signing/quickstart) (West US 3, closer to Utah, is `https://wus3.codesigning.azure.net`).

## Step 1. Create a paid Azure pay-as-you-go account (or use one you already have)

If you already have a **paid** pay-as-you-go or enterprise Azure subscription, skip to Step 2. A free, trial, or sponsored account will be rejected. Whether you already have a paid subscription is unverified.

- [ ] Open [Azure pay as you go](https://azure.microsoft.com/en-us/pricing/purchase-options/pay-as-you-go).
- [ ] Choose **Pay as you go**, not the free account. The free account cannot create Artifact Signing resources until you upgrade, and it is simpler to start on pay-as-you-go.
- [ ] Sign in with your Microsoft account (the one you want to own this Azure subscription).
- [ ] Fill in country or region to match your billing address, then your name, email, phone, and billing address. Official signup details: you need a phone number, a credit or debit card (not prepaid), and a Microsoft or GitHub account ([pay-as-you-go FAQ](https://azure.microsoft.com/en-us/pricing/purchase-options/pay-as-you-go)).
- [ ] Verify the phone (text or call). Avoid a VoIP number if you can. Exact on-screen button labels on the signup form are **unverified** (I did not run the signup). Follow the labels you see.
- [ ] Enter the card. A temporary $1 authorization may appear and then come off.
- [ ] Accept the agreement and finish. There is no monthly fee for the subscription itself. You will be charged only for usage, which here is the $9.99 Artifact Signing plan once you create that account in Step 3.
- [ ] Sign in at [portal.azure.com](https://portal.azure.com) and confirm you can see a subscription. A new signup creates a Microsoft Entra directory (tenant) for you; you do not need to create a tenant first. If a "create directory" screen appears, follow it. That last point is **unverified** against a live signup.

Write down: **subscription name**, **subscription ID** (Overview of the subscription), and **tenant (directory) ID** (Microsoft Entra ID, Overview). Larry will need these. They are identifiers, not secrets.

## Step 2. Register the Artifact Signing resource provider

From the official quickstart, Azure portal tab:

- [ ] Sign in to the [Azure portal](https://portal.azure.com).
- [ ] In the search box at the top, type `Subscriptions` and select **Subscriptions**.
- [ ] Select the subscription you will use.
- [ ] On the left, under **Settings**, select **Resource providers**.
- [ ] In the list, find and select **Microsoft.CodeSigning**. The status is usually **NotRegistered**.
- [ ] Select the ellipsis (the three dots), then select **Register**. Wait until the status is **Registered**.

## Step 3. Create the Artifact Signing account (Basic)

**This is the step that starts the $9.99 monthly bill**, in full for that month, even if validation is still running. From the official quickstart:

- [ ] In the portal search box, type `Artifact Signing Accounts` and select **Artifact Signing Accounts**.
- [ ] Select **Create**.
- [ ] **Subscription:** select your paid subscription.
- [ ] **Resource group:** select **Create new**, and enter `rg-wlanpros-signing` (or your chosen name).
- [ ] **Account name:** enter `wlanpros` (or your chosen unique name). Rules: 3 to 24 letters and numbers, starts with a letter, ends with a letter or number, no consecutive hyphens, not starting with "one", must be globally unique, not case-sensitive.
- [ ] **Region:** select **East US** (or your chosen supported region).
- [ ] **Pricing:** select **Basic** ($9.99 per month). Do not select Premium ($99.99) unless you later need it.
- [ ] Select **Review + Create**, then create the account. After it succeeds, select **Go to resource**.

Write down: **account name**, **resource group name**, and the **endpoint URL** for your region (`https://eus.codesigning.azure.net` for East US).

## Step 4. Assign yourself the Identity Verifier role

The official role table is important: **Owner** and **Contributor** do not include identity validation. You must give yourself the **Artifact Signing Identity Verifier** role or the **New Identity** button will be dimmed. You also need at least **Reader** on the subscription; as the subscription owner you already have more than that.

From the official [role tutorial](https://learn.microsoft.com/en-us/azure/artifact-signing/tutorial-assign-roles):

- [ ] On your Artifact Signing account, on the left, select **Access Control (IAM)**.
- [ ] Select the **Roles** tab and search for `Artifact Signing`. You should see **Artifact Signing Identity Verifier** and **Artifact Signing Certificate Profile Signer**.
- [ ] Select **Add**, then **Add role assignment**.
- [ ] Select **Artifact Signing Identity Verifier**. The rest of the role-assignment wizard (Members, select your user, Review + assign) follows Azure's general "assign roles" flow. Exact labels on those later screens are **unverified** against a live account; follow the on-screen labels, and assign the role to your own user.
- [ ] Wait a few minutes and refresh if **New Identity** is still dimmed. A known delay is that the role can take a short time to apply.

Do not assign the Signer role to a bot or to GitHub yet. You will do that later, after Larry sets up federated login, and only to the identity Larry names. Never create a client secret to paste into chat.

## Step 5. Create the identity validation (Public, Organization)

Identity validation can be done only in the Azure portal, not in a command line. From the official quickstart, Organization tab:

- [ ] Go to your Artifact Signing account.
- [ ] Confirm you have the Identity Verifier role (Step 4).
- [ ] On the Overview pane, or on the left under **Objects**, select **Identity validations**.
- [ ] Select **Organization**, select **New Identity**, then select **Public**. (Public is the one that works with a Public Trust certificate. Private is for a different certificate type and is not what you want.)
- [ ] On **New organization validation**, fill in:
  - **Organization Name:** `Wireless LAN Professionals, Inc.`
  - **Organizational Unit:** leave blank unless you have a reason to fill it. (The official page lists this field; it does not say it is required. If the form requires it, **unverified**, enter something simple such as `Toolbox`.)
  - **Website url:** the company website.
  - **Primary Email:** your watched company-domain address.
  - **Secondary Email:** a different address on the same domain.
  - **Business Identifier:** your EIN (or D-U-N-S).
  - **Seller ID:** optional, from Partner Center.
  - **Street, City, Country/Region, State/Province, Postal code:** the legal business address.
  - **First Name** and **Last Name:** your name exactly as it appears on your government ID. You will do a photo ID check as the person representing the company.
- [ ] Select **Certificate subject preview** and check that the company name looks right.
- [ ] Select **Create**. The status should change to **In Progress**.
- [ ] If anything is wrong after this, you cannot edit the request. You have to start a new one. Get it right the first time.

## Step 6. Complete the emails and the photo ID check

The official Organization steps say: when the status becomes **Action Required**, follow the Individual Developer steps from step 9 onward. A link is also sent to the primary email. Those official steps, in order:

- [ ] Watch the primary inbox (and spam). Open the mail and use the link within seven days.
- [ ] In the Azure portal, when status is **Action Required**, select your name. A pane opens on the right. Select the link under **Please complete your verification here**.
- [ ] Sign in with the same email you put on the request.
- [ ] Select **Get verified here through our trusted ID-verifiers**.
- [ ] The official walkthrough uses the partner **AU10TIX**, on a third-party site. Select **Let's Begin**. (If you see a different trusted partner name, that path is **unverified**; follow its on-screen steps, which should be a similar ID check.)
- [ ] Enter the same primary email. They send a PIN. Enter the PIN.
- [ ] Enter your phone number when asked, then select **Start**.
- [ ] On the computer, leave that screen open. Use your phone camera to scan the QR code.
- [ ] On the phone, select **Start**, and photograph your government ID when asked. Use good light, no flash, no crop, no editing. Official accepted IDs: passport, driver's license, or state ID. Not a library card or similar.
- [ ] When AU10TIX on the phone is done, select **Open Authenticator**.
- [ ] Back on the computer, scan the next QR code with the phone. In Microsoft Authenticator, select **Add** to add a verified ID.
- [ ] The computer shows **Present your Verified ID**. Scan that QR code.
- [ ] Select **Verifiable Credential**, then **Share**, to share it with Artifact Signing.
- [ ] The computer should show **Verification Successful**. After a few minutes, the Azure portal status should move on. For the individual part, a successful verified ID shows as **Completed**. For the organization request, status goes back to **In Progress** and the company check continues.

If they need more company documents, you will get email and the status will be **Action Required** again. Upload in the portal (three attempts). Use current documents: issued in the last 12 months, expiry at least two months away. Typical asks: articles of incorporation or a current registration that lists name and address, and a domain registration or renewal invoice that lists the company and the domain. Official page: keep public records up to date for a faster process.

When it is finished you get email, and the status becomes **Completed** (success) or **Failed**. If it fails, read the reason, fix the mismatch, and start a new request. If you cannot get through and want to stop charges, the FAQ says to delete the Artifact Signing account (that stops new billing; it does not undo months already billed).

## Step 7. Create the Public Trust certificate profile

Only after identity validation is **Completed**. From the official quickstart:

- [ ] Go to your Artifact Signing account.
- [ ] On Overview, or on the left under **Objects**, select **Certificate profiles**.
- [ ] On the command bar, select **Create**, and select the **Public Trust** profile type.
- [ ] **Certificate Profile Name:** `WLANProsPublic` (or your chosen name). Rules: 5 to 100 letters and numbers, starts with a letter, ends with a letter or number, no consecutive hyphens, unique inside the account.
- [ ] **Certificate Type** is filled in for you.
- [ ] **Program Type:** leave the default **None**. Change it only if you are in a Windows endpoint-security or recovery-environment program (you are not).
- [ ] **Verified CN and O:** select the completed organization identity (`Wireless LAN Professionals, Inc.`).
- [ ] You can leave **Include street address** and **Include postal code** unchecked unless you want those on the certificate.
- [ ] Check the certificate subject preview, then select **Create**.

Write down the **certificate profile name**.

## Step 8. What to hand Larry (no secrets)

Send Larry (or Lead, to pass to Larry) only these identifiers. Do not send passwords, card numbers, certificate files, or client secrets.

Copy and fill:

```
Azure tenant (directory) ID:
Azure subscription name:
Azure subscription ID:
Resource group name:
Artifact Signing account name:
Account endpoint URL:  (example for East US: https://eus.codesigning.azure.net)
Certificate profile name:
```

Larry will then set up GitHub Actions login with **federated credentials** (an app registration or managed identity that GitHub can assume, with no password in the repo). Microsoft's signing-integrations page points Larry at the [Artifact Signing GitHub Action](https://github.com/marketplace/actions/artifact-signing). After Larry tells you the identity's name, you (or Larry with your OK) assign it the **Artifact Signing Certificate Profile Signer** role on the account or on the certificate profile, from **Access Control (IAM)** the same way as Step 4, or with the Azure CLI scope shown in the [role tutorial](https://learn.microsoft.com/en-us/azure/artifact-signing/tutorial-assign-roles). Do not create a client secret to paste into chat.

Larry still does not build, publish, or deploy the Windows installer until the other decisions in the Larry handoff are settled and you say yes to those steps.

## If something looks wrong

- **New Identity is dimmed:** the Identity Verifier role is missing or still applying. Repeat Step 4, wait, refresh.
- **Free-subscription error when creating the account:** the subscription is still free, trial, or sponsored. Switch to pay-as-you-go and try again ([FAQ](https://learn.microsoft.com/en-us/azure/artifact-signing/faq)).
- **Email link expired:** those links last seven days. The official page says you must start a new identity validation request.
- **Questions for Microsoft:** open an Azure support ticket in the portal, or use [Microsoft Q&A, Artifact Signing tag](https://learn.microsoft.com/en-us/azure/artifact-signing/faq).
