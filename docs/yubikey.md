# YubiKey

Hardware-backed signing and authentication: the decisions, their reasoning, and what
moving to this setup involves.

YubiKey 5C NFC throughout. USB-C for the machine, NFC so a phone can reach the key
without a cable, which the Nano and 5Ci form factors cannot do. A Nano also sits flush,
making the per-signature touch a fingernail operation.

## Three keys, by write frequency

**FIDO2 credentials cannot be copied between keys.** Not exported, not cloned, not
backed up. Each service holds a separate credential per key, so every key must be
registered at every service, by hand, and a key can only be enrolled while you still have
access. Enrol a service with one key present and that service has a single point of
failure.

That forces the layout, because the credentials divide on how often they are *written*
while being identical in how often they are *read*.

| Credential | Read | Written |
|---|---|---|
| GPG signing key | Every commit | Once, ever |
| Core passkeys: Bitwarden, Apple, Microsoft | Daily | Once per account, and accounts are rare |
| Everyday passkeys | Daily | Every new service |
| OATH seeds | Daily | Every new TOTP-only service |

A credential written once can be sealed away and stay correct indefinitely. A credential
written weekly cannot: a sealed copy is wrong the day after it is made, and the wrongness
is invisible until it is needed. **Both kinds on one device forces the write-once half
into the wrong regime**, because the accruing half drags the device out of storage.

Hence three keys rather than two:

| Key | Role | Holds | Handled |
|---|---|---|---|
| A | Working 1 | GPG, OATH, all passkeys | Carried, used daily |
| C | Working 2 | OATH, everyday passkeys | To hand, present at every new signup |
| B | Archive | GPG, core passkeys | Sealed, written once |

B is the archive because it already holds the core credentials, and those are the
expensive ones to re-create. C takes the accruing work, which is re-enrollable a service
at a time.

Nothing is on three keys. Access needs one key, so a credential needs exactly two: the
one in use and the one that replaces it. A third registration adds nothing.

The archive is opened only when a new core account appears, which is a few times a year
against a few times a week for everyday services. That ratio is the whole justification.

Apple enforces exactly two security keys per account, so core credentials could not be on
all three even if that were wanted.

OATH has no archive. A seed can only be written when the service shows it, so an archived
copy would be permanently stale. TOTP is the recoverable tier by design: losing it means
re-enrolling, not losing access.

## The signals, and what a passphrase costs

Signing happens on behalf of an agent doing development work, so the question is not
whether an operation is authorised but *which* operation is being authorised, at a moment
not chosen by the person authorising it.

Two physical signals carry that, and they discriminate because the caching differs:

| Signal | Means |
|---|---|
| Blink, no dialog | GPG signing. `gpg-agent` has the passphrase cached |
| Dialog, then blink | FIDO2 or OATH. Neither caches anywhere, ever |

The touch itself proves presence, not consent: the chip receives a hash and cannot
display what it represents. So the dialog is the only channel carrying content, and the
discrimination above is the only way to tell one kind of operation from another.

This has a consequence for `forcesig`, the card setting deciding whether GPG asks for the
passphrase once per session or per signature. Set to per signature, every commit would
surface a dialog naming the operation, restoring the informative channel for signing at
the cost of typing the passphrase constantly. Left at once per session, signing is a bare
blink.

**The passphrase is typed far more than expected.** FIDO2 has no cache: not on the key,
not in the browser, not in any agent. Every credential requesting user verification
prompts, every time. A 16-character passphrase read off a card takes several seconds, and
that repeats through the day.

The fix is a shorter passphrase, not a different key. Eight attempts against a chip that
then erases its credentials makes three memorable words as unguessable as sixteen random
characters, and far faster to type. The card and its long read answer a question about
entropy that does not apply here.

### The Bio series

A fingerprint sensor on the key replaces typing the passphrase for user verification,
which is the friction above. What it entails:

- **Bio is FIDO-only.** The FIDO Edition supports FIDO2 and U2F. The Multi-protocol
  Edition adds PIV and is subscription-only. Neither holds OATH or OpenPGP.
- OATH would move to a phone app, so the seed sits in software rather than hardware.
- Passkeys on Bio, with GPG and OATH on 5C, is **five** devices rather than three: each
  role still needs its working pair and its archive.
- Five identical keys holding different things have to be labelled by hand, and reaching
  for the wrong one costs an attempt against a counter that erases credentials.
- The signals separate by device: a blink on the signing key means the agent, a lit
  sensor on the access key means a person.

## What each application holds

| Feature | Imported | Exportable |
|---|---|---|
| OpenPGP | Private key, if generated off-card | Public key |
| FIDO2 | Nothing | Nothing |
| PIV | Private key and certificate, if generated off-card | Certificate |
| OATH-TOTP | Seed | Nothing |
| Yubico OTP | Secret, if programmed externally | Nothing |
| HMAC challenge-response | Secret | Nothing |

## GPG: one key, five UIDs, generated on-card

The OpenPGP application has three slots: one signature, one encryption, one
authentication. **One signing key per YubiKey.** The five identities in `.gitconfig.d/`
do not fit as five separate keys.

One key carries all five UIDs. Exports are filtered so a platform sees only the addresses
relevant to it.

**Why not five SSH keys instead.** Git can sign with `ed25519-sk` keys, which are
FIDO2-backed and unbounded, so five identities would fit. Rejected because an SSH key is
a credential, not an identity: it asserts nothing about who holds it, and the
email-to-key mapping lives outside the artifact in an allowed-signers file maintained by
whoever verifies. A GPG UID is inside the key and self-signed, so the key states its own
identity and verification is self-contained. Five SSH keys would be five anonymous
keypairs plus an external table, which removes the identity concept rather than
separating it.

**Why filter the UIDs.** Separation of concerns, not secrecy. Nothing in a UID is a
secret; the name and address are already plaintext in every commit object. The point is
that a personal GitHub profile should not carry a list of contracting clients. Filtering
is a keyring-and-upload concern only: **UIDs are not on the card at all**, so this never
touches the hardware.

Only GitHub holds a published key. Its export carries two UIDs; the three client
addresses are published nowhere.

**Generated on-card**, so the private key has never existed on disk and there is nothing
to back up or leak. This costs interchangeability: each key holds different key material,
every public key must be published, and switching keys means changing `signingkey` in the
relevant `.gitconfig.d/` file. Both public keys stay in the keyring
permanently, or inserting a card produces a stub for material gpg cannot identify.

## Touch policy: `cached`

Without a touch policy, anything on the machine can sign silently for as long as the key
is plugged in and the passphrase is cached. The touch is enforced by the chip, so nothing
on the host can cache, replay or skip it.

| Policy | Behaviour | Reversible |
|---|---|---|
| `off` | No touch required | Yes, with the admin passphrase |
| `on` | Every signature | Yes, with the admin passphrase |
| `cached` | One touch covers 15 seconds | Yes, with the admin passphrase |
| `fixed` | Every signature, permanently | No. Only by wiping the application and the key with it |

**Why `cached` rather than `on`.** A touch proves presence, not consent. The chip
receives a hash and cannot display what it represents, so there is nothing to inspect and
nothing to approve; you feel a blink and press a finger. Malware timed to a rebase gets
its signature under either policy, because you are touching anyway and cannot tell the
difference. So `on` buys a shorter window in which you equally cannot see what is being
signed, and costs a touch per commit. Interactive rebases, `git-catchup` and `git-spread`
make that a weekly tax for no gain.

**What the touch actually defends** is the key left in the port while nobody is there.
`cached` and `on` are identical for that, and unplugging the key handles it better than
either.

**Never `fixed`.** It behaves as `on` and removes the ability to change your mind.

## Firmware is permanent

YubiKey firmware cannot be updated, on any model. A key that accepts new firmware has a
path for an attacker to load their own, so the secure element is programmed once at
manufacture. The consequence is that a vulnerability cannot be patched, only replaced:
EUCLEAK (2024) was fixed in 5.7, and Yubico ran a replacement programme for ROCA on the
YubiKey 4.

So the firmware version is a permanent property of the physical key, and the newest
available is the right default for a device held for years. 5.8 at time of purchase; 5.7
is the floor, being where EUCLEAK was fixed. Nothing in 5.8 is a security fix. Ordering
direct from Yubico is what makes the version knowable, since it is stated at the point of
sale and appears nowhere on the packaging or the SKU.

## Passphrases

The specs call these PINs. ISO 7816 named the field in the 1980s when the reader was a
bank terminal with a numeric keypad, and OpenPGP and PIV inherited the name while
relaxing the constraint. Every tool still prompts for a "PIN". Only PIV's is actually
length-constrained; the rest are passphrases.

**There is no YubiKey passphrase.** The applications share nothing: separate storage,
separate credentials, separate counters. Unlocking one does nothing for another, and
there is no master credential above them.

Two strings in total, used on every key:

| | Read from | Used for | Needed when |
|---|---|---|---|
| **P1** | Card User | FIDO2, OpenPGP user | Signing a commit, registering a key with a service |
| **P2** | Card Admin | OpenPGP admin | Configuring a key, and unblocking P1 after three failures |

**Every key carries the same P1 and P2.** A passphrase is worthless to anyone not holding
that specific key, so reuse across them creates no shared point of failure. Different
strings on identical objects does create one: three wrong attempts kills the OpenPGP
application, and confidently typing the wrong key's passphrase twice gets you most of the
way there.

**P2 must differ from P1.** Its job is unblocking P1 after three failures, so if they
match, the situation it exists for is the situation where you do not know it. That is
also why they come from different cards.

Card Admin therefore lives in the sealed envelope rather than at the desk: P2 is needed
only when configuring a key, and its other role is recovery.

| Credential | Length | Attempts | On lockout |
|---|---|---|---|
| FIDO2 | 4 to 63 | 8 | All FIDO2 credentials erased, re-register everywhere |
| OpenPGP user | 6 to 127 | 3 | Admin unblocks it |
| OpenPGP admin | 8 to 127 | 3 | OpenPGP application wiped, signing key gone |
| PIV PIN | 6 to 8 | 3 | PUK unblocks it |
| PIV PUK | 6 to 8 | 3 | Certificates gone |

FIDO2 has no admin credential, so every FIDO2 operation including enrolment uses P1.
Deregistering a key is done on the service's own site and needs neither.

PIV's 8-character ceiling against OpenPGP admin's 8-character floor means a single string
usable everywhere would have to be exactly 8. PIV is not enabled here, so the ceiling does
not apply.

**Memorable beats strong**, and the reasoning is not the usual one. These are
access-control gates checked by the chip, not key material, and the chip counts. Entropy
is not what protects them. Forgetting one destroys the credentials as completely as
losing the key, so the failure to design against is memory, not guessing.

**Unused applications sit at published defaults**, `123456` and `12345678`. PIV being
unused does not mean it is off; it means it is open. Set it or accept that.

## The cards

A passphrase is never written down. It is read off a printed grid along a remembered
path, so the printed artifact is inert to anyone who finds it: 1024 positions, times the
directions, times the plausible lengths. Against a chip that erases itself after 3 to 8
attempts, that is not a guessing problem.

`passcard` generates a grid, `passpath` picks a random start position. Both live in
`home/common/bin/`.

The grid reads as one continuous string, row 1 left to right then row 2, wrapping from
the last character back to the first. Without that rule the number of valid start
positions would shrink as the passphrase lengthened and reach zero at the row width.

**Each card derives from a seed**, so a destroyed card can be reprinted. The seed is
emitted to stderr and never into the HTML, so a printed card cannot reproduce itself.
Dimensions are a required argument rather than a default, which keeps a leaked seed
insufficient on its own.

The derivation is HMAC-SHA256 over a counter rather than a seeded PRNG. A PRNG is built
to be reproducible, not unpredictable: small state, recoverable from partial output, and
not stable across implementations. Deterministic yet unpredictable is the definition of a
PRF, so a PRF is what it uses.

## TOTP

Three tiers, in order of preference:

1. **FIDO2 where the service supports it**, and delete TOTP entirely. TOTP is relayable
   by a proxy phishing site inside its window; a WebAuthn credential is bound to the
   origin and cannot be relayed.
2. **The key's 64 OATH slots** for frequently used TOTP-only services. The seed never
   leaves the hardware and producing a code needs the physical key. Read over NFC with
   Yubico Authenticator.
3. **A dedicated phone** for the long tail, kept off the daily-driver device.

A seed can only be written to a key while the service is displaying it. There is no
copying afterwards, which is why OATH has no archive copy.

## Bitwarden

Five accounts, one per context, for separate logins rather than secrecy. **Families**
(6 seats) rather than five Premium accounts, on cost.

Hardware-key 2FA is a paid feature at Bitwarden, Dashlane, Keeper and LastPass, and
included at every tier at 1Password. The gate is commercial, not technical.

**The accounts stay cryptographically independent.** Account recovery, where a member's
encryption key is escrowed against the organization's public key so an admin can reset
it, is Enterprise-only. Families has no admin path into a member vault.
See `https://bitwarden.com/help/account-recovery/`.

Use **FIDO2 WebAuthn**, not the YubiKey OTP option: OTP validates against Yubico's
servers, WebAuthn stays between the browser and the key.

## Moving to this setup

**Both keys in hand before starting.** Every enrolment below has to happen twice, and
the second key cannot be added retrospectively. Doing this once is the entire point of
the ordering.

**1. Cards first, printed, before anything is set.** Generate both with `passcard`,
capture the seeds, pick the paths with `passpath`, and print. A passphrase that exists
only in a browser tab and short-term memory is lost to a reboot, which costs a full
factory reset of both applications and everything built on them.

**2. Passphrases on every key.** P1 from card User on FIDO2 and OpenPGP user, P2 from
card Admin on OpenPGP admin. Add PIV's pair only if PIV is enabled, and note PIV caps at
8 characters where the others do not.

**3. GPG, per key.** Set the key attributes to ed25519 first, since a card at factory
defaults generates RSA-2048 without asking. Generate on-card, which creates the key with
one UID; add the remaining four with `--quick-add-uid`; set the signature slot's touch
policy to `cached`. Key B repeats it and produces different key material, which is
inherent to on-card generation.

**4. Write the public key onto the card.** A card holds the private key, and the
public key only if it is put there:

```
gpg-card --no-history writecert --openpgp OPENPGP.3 <fingerprint>
```

Without it a machine that has never seen the key cannot build the stub that points at
the card, so the card is unusable there. Once per key, and
`gpg-setup.sh --configure --hardware` takes it back off.

The card has three certificate slots, one per key. 1 and 2 belong to the signature and
encryption keys and are free for certificates on those; 3 belongs to the authentication
key, which is unused here, so it is the slot least likely to be wanted for anything
else. `gpg-setup.sh` reads the same slot from `CERT_SLOT`.

One keyblock goes in, carrying the primary key, both subkeys and every UID, so the slot
holds the whole key rather than one key's public half.

**5. Publish the public keys.** One GitHub account covers both `github.com/shellicar` and
the `Hellicar-Solutions` organisation, so it takes a single export carrying those two
UIDs. The three client UIDs are exported nowhere, which achieves the separation more
completely than filtering per platform would.

Publishing is not what makes a signature worth having. The signature lives in the commit
object and is verified by tooling, so a platform that displays no badge changes nothing.
GitHub's own "require signed commits" is weaker than it looks: it checks a signature
resolves to some verified key on the account, not that the commit was signed with a key
you control. A workflow that validates against known fingerprints before a merge is what
actually proves it.

Both keys go up at this point rather than when one fails, and the old keys stay: they are
what verifies every commit signed before the switch.

**6. Update `.gitconfig.d/`.** All five files take the same `signingkey`, since the five
identities now share one key. The `includeIf` selection still picks the right email per
remote, which is what it is actually for.

**7. Bitwarden.** Create the Families organization, bring the five accounts in, enable
WebAuthn on each with both keys, and print every recovery code.

**8. The credential pass.** The real work, and the reason for the ordering above.
Microsoft Authenticator has no clean seed export, so every credential is a manual
re-enrolment regardless of destination.

One visit per service, doing all of it: register both keys via FIDO2 and delete TOTP
where supported, otherwise place the TOTP by tier, and drop SMS 2FA wherever it is still
enabled. Walking a hundred services twice is the outcome to avoid.

## Splitting into three keys

From a two-key build, where A and B both hold everything, to the three-key layout:

**1. Enrol C as Working 2.** Passphrases from the same cards, then everyday passkeys and
OATH. No GPG key: signing stays on A and B. Each OATH seed has to come from the service
again, since seeds cannot be copied between keys.

**2. Strip C's work from B.** `ykman fido credentials delete` for everyday passkeys,
`ykman oath accounts delete` for OATH seeds. B keeps GPG and the core passkeys, which is
what makes it the archive.

**3. Remove B from the services it no longer serves**, or they still believe it has
access. Not urgent while B is in your possession.

**4. Seal B.** With card Admin, the revocation certificates and the recovery codes.

The order matters: C has to be working before B is stripped, or there is a window with
only one key holding the everyday credentials.

## Operating notes

**One key plugged in at a time.** `scdaemon` binds to a single card, so two present at
once means signing requests can address the wrong one and stall. `gpgconf --kill
gpg-agent` clears a stale binding.

**The agent's cache and the card's own state are separate gates, and either one prompts.**
`gpg-agent`'s `default-cache-ttl` governs only how long the agent holds the passphrase.
The card verifies PW1 itself and holds that verified state in volatile memory, so
unplugging the key or the machine sleeping clears it regardless of the agent. The
practical cadence is therefore once per insertion, not once per TTL, and a prompt after
the key has been out is expected rather than a broken cache.

The card's `forcesig` is a third gate on the same path: set to forced, it demands the
passphrase per signature and the agent cache stops mattering entirely.

**There is no infinite cache value.** Both TTLs are plain seconds and `0` means no
caching at all, which is the opposite of what it reads as. 400 days stands in for
forever, since the agent dies at logout long before it elapses.

**The touch is easy to miss.** After the passphrase prompt closes, the contact blinks and
waits about fifteen seconds. No touch reads as `gpg: signing failed: Timeout`, which does
not mention touching at all.

**`gpg.conf` carries `no-tty`**, which is right for signing through pinentry and blocks
`--card-edit` outright. `--no-options` skips the config for one invocation.

**Resets are per application.** `ykman openpgp reset --force` and `ykman fido reset
--force` are separate, and there is no command that resets the whole key. The `card-edit`
factory-reset needs a typed confirmation that some terminals fail to submit, so it can
silently do nothing; `gpg --card-status` is how you tell, since a real reset returns the
key attributes to `rsa2048` and zeroes the signature counter.

## Deliberately not here

The service inventory (which account uses which method) and any physical location. The
first is a map of where the setup is weakest, the second is a map to the backup key.
Neither is a cryptographic secret and neither belongs in a public repo.

Recovery codes live on paper with the stored key, never in Bitwarden, because the
scenario they exist for is being locked out of Bitwarden.
