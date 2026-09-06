# shellcheck shell=sh
# shellcheck disable=SC2034  # every value here is read by whatever sources this
# The three YubiKeys, sourced by the tools that need to name one.
#
# Here rather than hardcoded in each tool, because a serial repeated in two places is one
# that gets updated in one of them. Nothing in it is secret: a serial is printed on the
# key and reported by any tool that can see it, and a fingerprint is public by definition.
#
# Not in bin/, because install.sh links that file by file into ~/bin and this is data, not
# a command.

# All three carry the same GPG key. Which one is inserted is what these tell apart.
YUBIKEY_A_SERIAL=38532913
YUBIKEY_B_SERIAL=38532914
YUBIKEY_C_SERIAL=38532776

# The one certify key behind all three, generated 2026-09-03. Also user.signingkey in
# .gitconfig.d/common, and what proves an imported public key is the right one.
GPG_FINGERPRINT=B92C14F32704628ADC98CA92A9B6327CEDF47732
