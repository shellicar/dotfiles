# YubiKey

Hardware-backed signing and authentication: the decisions, their reasoning, and what
moving to this setup involves.

YubiKey 5C NFC throughout. USB-C for the machine, NFC so a phone can reach the key
without a cable, which the Nano and 5Ci form factors cannot do. A Nano also sits flush,
making the per-signature touch a fingernail operation.

## Three keys, and why not two

**A backup that has to be opened is not a backup.** FIDO2 credentials cannot be copied
between keys: not exported, not cloned, not backed up. Each service holds a separate
credential per key, so every key must be registered at every service by hand, and a key
can only be enrolled while you still have access. On two keys, every new signup opens
the envelope, and a sealed key that comes out weekly is sealed in name only.

So the layout follows the **write** cadence, not the read cadence. Everything here is
read daily. What differs is how often it is written, and that splits the accounts on
recoverability.

Apple, Microsoft, Bitwarden and Gmail are the identity roots. There is no email path
back to them because they are the email path back to everything else, and they are also
the accounts that never change. Every other service recovers by email, and is where the
weekly enrolments land.

| Layer | Pair | Written | Second key |
|---|---|---|---|
| Core: Apple, Microsoft, Bitwarden, Gmail | A + B | Rarely | Sealed, opened in an emergency |
| Everyday: passkeys, OATH | A + C | Weekly | To hand, used on demand |

Two pairs sharing A. Three keys rather than two because each layer needs its own
redundant pair and the two cadences cannot share one: put the accruing half on B and B
stops being a backup.

| Key | Role | Holds | Handled |
|---|---|---|---|
| A | Primary | GPG, core, everyday | Carried, used daily |
| B | Backup | GPG, core | Sealed, opened when a core account appears |
| C | Secondary | GPG, everyday | To hand, present at every new signup |

B is the sealed one rather than C because the core credentials are the expensive ones to
re-create, and C's everyday work is re-enrollable a service at a time.

Apple requires at least two security keys and allows up to six, so A and B for the core
layer is a choice rather than a limit.

**A third registration adds nothing, and closes nothing.** Access needs one key, so a
credential needs exactly two: the one in use and the one that replaces it. Anything
platform-managed can still go onto a third key later on a whim, because adding it is
plug in and enrol, on any day, from anywhere.

**GPG is the exception, and not because it is hard.** Adding it to a card later means
repeating the whole key-generation session. The decision is expensive to revisit rather
than expensive to make, so all three carry it and it is settled once, at generation.

OATH has no archive. A seed can only be written when the service shows it, so an
archived copy would be permanently stale. TOTP is the recoverable tier by design: losing
it means re-enrolling, not losing access.

## The signals, and what a passphrase costs

With `sig` at `off`, GPG signing produces no blink. FIDO2 requires a touch of its own and
has no setting to change that, so a blinking contact means one thing: a credential is
being used to get into an account.

That is the whole of what leaving the OpenPGP touch off buys. A blink meaning two
different things means nothing.

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

## GPG: one identity, five UIDs, three cards

The OpenPGP application has three key slots: one signature, one encryption, one
authentication. The five identities in `.gitconfig.d/` do not fit as five separate keys.

One key carries all five UIDs. Exports are filtered so a platform sees only the
addresses relevant to it.

**The primary key certifies and nothing else.** It signs the UIDs onto itself and signs
the subkeys into the key, and that is the whole of what it can do. It cannot sign a
commit, so it has no reason to be on a card, so it is never on one. Three subkeys do the
work and those are what fill the three slots.

That split is what the setup turns on. A primary that can also sign has to be on a card
in order to sign with, which puts the identity on the card, which means every card needs
its own. **Two cards therefore meant two identities**, both asserting the same five
addresses, and a commit signed on one traced back to a different key than a commit
signed on the other. Collapsing that into a single identity behind all three cards is
what this is.

**Why not five SSH keys instead.** Git can sign with `ed25519-sk` keys, which are
FIDO2-backed and unbounded, so five identities would fit. Rejected because an SSH key is
a credential, not an identity: it asserts nothing about who holds it, and the
email-to-key mapping lives outside the artifact in an allowed-signers file maintained by
whoever verifies. A GPG UID is inside the key and self-signed, so the key states its own
identity and verification is self-contained. Five SSH keys would be five anonymous
keypairs plus an external table, which removes the identity concept rather than
separating it.

**Generated off-card, then written to all three.** One shared key gives one fingerprint,
one `signingkey` across all five `.gitconfig.d/` files, one public key to publish, and
any card in the port signs.

The cost is that private key material exists off a card at all, so there is something
to back up and something to lose. It is never on a daily machine, and the backup is
encrypted and offline.

**Nothing expires.** The primary key is offline, so its exposure is physical rather than
time-based. An expiry only earns its place where a key is compromised and you cannot tell
anyone, and every place a signature of yours is verified is a place you control: GitHub,
and a workflow checking fingerprints. Revocation reaches all of them the same afternoon,
so a standing appointment to renew buys nothing.

**One keygrip, one stub, one serial.** All three cards hold the same key, so gpg keeps a
single stub for it and that stub records whichever card it last saw. Pinentry names that
serial when it asks for the passphrase.

**The named serial is not a requirement.** Any of the three signs, whichever card the stub
happens to be bound to, so the serial in the dialog is a label rather than a demand.
Nothing has to be rebound after a swap.

Should a stub ever need rebinding, `gpg-connect-agent "scd serialno" "learn --force" /bye`
does it. It replaces an on-disk secret with a shadow stub when the card reports the same
keygrip, so it belongs only where the secret is never on disk, which is every machine this
repo configures.

Superseded on-card public keys stay in the keyring and stay published. They are what
verifies every commit signed before they were replaced.

## Touch policy: `off`

A touch is a presence check and nothing else. The chip receives a hash and cannot display
what it represents, so it confirms a person was at the desk, never what they agreed to.

| Policy | Behaviour | Reversible |
|---|---|---|
| `off` | No touch required | Yes, with the admin passphrase |
| `on` | Every signature | Yes, with the admin passphrase |
| `cached` | One touch covers 15 seconds | Yes, with the admin passphrase |
| `fixed` | As `on`, permanently | No. Only by wiping the application and the key with it |
| `cached-fixed` | As `cached`, permanently | No. Same as `fixed` |

The policy is set per key slot, so `sig` governs commits and `dec`, `aut` and `att` are
independent of it.

**Why `off`.** FIDO2 requires a touch of its own and has no setting to change that. With
the OpenPGP touch on as well, every blink looks identical and nothing on the key says
whether it is a commit or a login. Commits are frequent, so most blinks would be commits,
and touching without looking becomes the habit. That habit carries to the FIDO2 blinks,
which are the ones guarding access to accounts.

**What separates `on` from `cached`** is how often you have to be there, not what being
there proves. `on` is a touch per signature. `cached` covers fifteen seconds after one, so
a twelve-commit rebase is one touch rather than twelve, and `git-catchup` and `git-spread`
are one rather than several. Both attest the same thing about the same signature.

**Presence is controlled by unplugging the key.** Nothing signs while it is out of the
port, which is the property the touch offered, without a blink per commit.

**Never `fixed` or `cached-fixed`.** Both remove the ability to change your mind.

## Firmware is permanent

YubiKey firmware cannot be updated, on any model. A key that accepts new firmware has a
path for an attacker to load their own, so the secure element is programmed once at
manufacture. The consequence is that a vulnerability cannot be patched, only replaced:
EUCLEAK (2024) was fixed in 5.7, and Yubico ran a replacement programme for ROCA on the
YubiKey 4.

So the firmware version is a permanent property of the physical key, and the newest
available is the right default for a device held for years. A, B and C are 5.8; 5.7 is the
floor, being where EUCLEAK was fixed. Ordering direct from Yubico is what makes the
version knowable, since it is stated at the point of sale and appears nowhere on the
packaging or the SKU.

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

Five accounts, one per context, for separate logins rather than secrecy. All free:
nothing used here needs a paid tier.

FIDO2 WebAuthn two-step login is free on Bitwarden. YubiKey OTP and Duo are the two
methods that need Premium, and OTP is the one ruled out below for validating against
Yubico's servers. See `https://bitwarden.com/help/setup-two-step-login/`.

**Families would not cost the accounts their independence.** Account recovery, where a
member's encryption key is escrowed against the organization's public key so an admin can
reset it, is Enterprise-only, so a Families organisation has no admin path into a member
vault. See `https://bitwarden.com/help/account-recovery/`.

Use **FIDO2 WebAuthn**, not the YubiKey OTP option: OTP validates against Yubico's
servers, WebAuthn stays between the browser and the key.

## Building this

**All three keys in hand before starting.** Every FIDO2 enrolment happens on two keys
and the second cannot be added retrospectively, and the GPG session writes all three
cards at once. Doing this once is the entire point of the ordering.

**1. Cards first, printed, before anything is set.** Generate both with `passcard`,
capture the seeds, pick the paths with `passpath`, and print. A passphrase that exists
only in a browser tab and short-term memory is lost to a reboot, which costs a full
factory reset of both applications and everything built on them.

**2. Passphrases on every key.** P1 from card User on FIDO2 and OpenPGP user, P2 from
card Admin on OpenPGP admin. Add PIV's pair only if PIV is enabled, and note PIV caps
at 8 characters where the others do not.

**3. GPG, all three cards at once.** The primary key and its subkeys are made away from
any daily machine and written to all three cards in one go.

Everything needing the primary key happens then, because reaching it again is expensive:
the five UIDs, the revocation certificate, and the subkeys on every card.

Nothing else has to. Passphrases and the certificate slot below work on any machine with
the card in hand.

**4. Write the public key onto each card.** A card holds the private key, and the
public key only if it is put there:

```
gpg-card --no-history writecert --openpgp OPENPGP.3 <fingerprint>
```

Without it a machine that has never seen the key cannot build the stub that points at
the card, so the card is unusable there. This is what makes a machine disposable:
`gpg-setup.sh --configure --hardware` reads the key back off the card and rebuilds
everything from it, so nothing on a working machine's disk is worth keeping. One
keyblock, written to all three cards.

The card's three certificate references are storage separate from the three key slots,
despite sharing their numbering. **Only reference 3 accepts an OpenPGP keyblock**: 1 and
2 are rejected with `Invalid argument`, and 4 with `CERTREF must be OPENPGP.N or just N
with N being 1..3`. So the choice is not open, and `gpg-setup.sh` reads the same slot
from `CERT_SLOT`.

Writing it needs the card authenticated, and `gpg-card` has no way to be given a PIN
without a pinentry dialog. Where there is none, it only succeeds because the subkey
transfers immediately before it have already authenticated the card.

One keyblock goes in, carrying the primary key, all three subkeys and every UID, so the
slot holds the whole key rather than one key's public half.

**5. Publish the public key.** The UIDs are filtered at export, so what a platform
receives carries only the addresses relevant to it. Not for secrecy: nothing in a UID is
secret, and the name and address are already plaintext in every commit object. It keeps
per-platform disclosure a live decision rather than a consequence of having published
once. UIDs are not on the card at all, so none of this touches the hardware.

One GitHub account covers both `github.com/shellicar` and the `Hellicar-Solutions`
organisation, so it takes a single export carrying those two UIDs. The three client UIDs
are exported nowhere.

Publishing is not what makes a signature worth having. The signature lives in the
commit object and is verified by tooling, so a platform that displays no badge changes
nothing. GitHub's own "require signed commits" is weaker than it looks: it checks a
signature resolves to some verified key on the account, not that the commit was signed
with a key you control. A workflow that validates against known fingerprints before a
merge is what actually proves it.

Superseded keys stay up alongside it. They are what verifies every commit signed before
they were replaced.

**6. `signingkey` moves into `.gitconfig.d/common`.** One identity means one value, and
repeating it across five files is five places to get wrong. The per-org files keep
`user.email` and their `[cleanup]` block, so `includeIf` selects the identity per remote,
which is the thing it is for. Signing is not per-org, because it is not per-key.

**7. Bitwarden.** Create the Families organization, bring the five accounts in, enable
WebAuthn on each with A and B, and print every recovery code.

**8. The credential pass.** The real work, and the reason for the ordering above.
Microsoft Authenticator has no clean seed export, so every credential is a manual
re-enrolment regardless of destination.

One visit per service, doing all of it: register the layer's pair via FIDO2, A and B
for a core account and A and C for everything else, delete TOTP where FIDO2 is
supported and otherwise place it by tier, and drop SMS 2FA wherever it is still
enabled. Walking a hundred services twice is the outcome to avoid.

**9. Seal B.** With card Admin, the revocation certificates and the recovery codes.

The order matters: C has to be carrying the everyday credentials before B is sealed, or
there is a window with only one key holding them.

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
