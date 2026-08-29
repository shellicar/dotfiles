# YubiKey

Hardware-backed signing and authentication: the decisions, their reasoning, and what
moving to this setup involves.

Two YubiKey 5C NFC. USB-C for the machine, NFC so a phone can reach the key without a
cable, which the Nano and 5Ci form factors cannot do.

## Two keys, both enrolled

The keys are peers. There is no master and no recovery key, and neither knows the other
exists. One is carried, one is stored; that is the only difference between them.

**FIDO2 credentials cannot be copied between keys.** Not exported, not cloned, not
backed up. Each service holds a separate credential per key, so both keys must be
registered at every service, by hand.

The consequence that decides the discipline: **a backup key can only be enrolled while
you still have access.** Enrol a new service with only one key present and that service
has a single point of failure. So both keys are present whenever a service is set up.

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
to back up or leak. This costs interchangeability: key A and key B hold different key
material, both public keys must be published, and switching keys means changing
`signingkey` in the relevant `.gitconfig.d/` file. Both public keys stay in the keyring
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

Two strings in total, both used on both keys:

| | Read from | Used for | Needed when |
|---|---|---|---|
| **P1** | Card A | FIDO2, OpenPGP user | Signing a commit, registering a key with a service |
| **P2** | Card B | OpenPGP admin | Configuring a card, and unblocking P1 after three failures |

**Both keys carry the same P1 and P2.** A passphrase is worthless to anyone not holding
that specific key, so reuse across the two creates no shared point of failure. Two
different strings on two identical objects does create one: three wrong attempts kills
the OpenPGP application, and confidently typing the wrong key's passphrase twice gets you
most of the way there.

**P2 must differ from P1.** Its job is unblocking P1 after three failures, so if they
match, the situation it exists for is the situation where you do not know it. That is
also why they come from different cards.

Card B therefore lives with key B rather than at the desk: P2 is needed only when
configuring a card, and its other role is recovery.

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

The seed can be written to both keys only if it is added at enrolment time. There is no
copying afterwards.

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

**2. Passphrases on both keys.** P1 from card A on FIDO2 and OpenPGP user, P2 from card B
on OpenPGP admin. Add PIV's pair only if PIV is enabled.

**3. GPG, per key.** Set the key attributes to ed25519 first, since a card at factory
defaults generates RSA-2048 without asking. Generate on-card, which creates the key with
one UID; add the remaining four with `--quick-add-uid`; set the signature slot's touch
policy to `cached`. Key B repeats it and produces different key material, which is
inherent to on-card generation.

**4. Publish the public keys.** One GitHub account covers both `github.com/shellicar` and
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

**5. Update `.gitconfig.d/`.** All five files take the same `signingkey`, since the five
identities now share one key. The `includeIf` selection still picks the right email per
remote, which is what it is actually for.

**6. Bitwarden.** Create the Families organization, bring the five accounts in, enable
WebAuthn on each with both keys, and print every recovery code.

**7. The credential pass.** The real work, and the reason for the ordering above.
Microsoft Authenticator has no clean seed export, so every credential is a manual
re-enrolment regardless of destination.

One visit per service, doing all of it: register both keys via FIDO2 and delete TOTP
where supported, otherwise place the TOTP by tier, and drop SMS 2FA wherever it is still
enabled. Walking a hundred services twice is the outcome to avoid.

## Operating notes

**One key plugged in at a time.** `scdaemon` binds to a single card, so two present at
once means signing requests can address the wrong one and stall. `gpgconf --kill
gpg-agent` clears a stale binding.

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
