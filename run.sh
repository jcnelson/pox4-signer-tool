#!/bin/bash

# This is your PoX address.  Right now, only legacy addresses are supported.
# Hit me up if you need segwit addresses.
pox_addr="12qdRgXxgNBNPnDeEChy3fYTbSHQ8nfZfD"

# This is the reward cycle in which you want to start stacking.
reward_cycle=84

# This is the number of reward cycles for which you want to stack.
# Valid values are between 1 and 12.
duration=12

# This is the amount of uSTX (micro-STX) you want to stack.  This is
# synonymous with the maximum amount to delegate to the signer.
# This example value below will stack 1,234,567.000000 STX
amount=1234567000000

# This is the authorization ID.  It can be any unsigned 128-bit number, but 
# it has to be unique per stacking transaction.  You can start with 1 and just
# increment it each time you stack if you want.
auth_id=12345

set -uoe pipefail 

if ! [ -f './signer.privkey' ]; then
   echo >&2 "You must first generate your signer.privkey file. See the README.md for details"
   exit 1
fi

./signer-helper.sh setup
signer_hash="$(./signer-helper.sh signer-hash -p "$pox_addr" -r "$(( reward_cycle - 1 ))" -d "$duration" -s "$amount" -a "$auth_id")"
signature="$(./signer-helper.sh sign ./signer.privkey "$signer_hash")"
pubkey="$(./signer-helper.sh get-public-key ./signer.privkey)"
./signer-helper.sh check-signature -p "$pox_addr" -r "$(( reward_cycle - 1 ))" -d "$duration" -s "$amount" -a "$auth_id" -S "$signature" -P "$pubkey"

echo "{\"pubkey\": \"$pubkey\", \"signature\": \"$signature\"}"

