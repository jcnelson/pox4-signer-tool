#!/bin/bash

TOOLDIR="."
ADDR="SP3HA2DDR75MVBZW5F37C0N5BTBJY8PPE8S6YVEQE"

function exit_error() {
   echo >&2 "$1"
   exit 1
}

for cmd in clarity-cli node; do
   command -v "$cmd" >/dev/null || exit_error "Command not found: $cmd"
done

for component in "pox-4.clar"; do
   test -f "$TOOLDIR/$component" || exit_error "Component not found: $component"
done

for nodepkg in 'elliptic' 'crypto' 'process' 'c32check'; do
   echo "require('$nodepkg')" | node >/dev/null 2>&1
   rc=$?
   if [ $rc != 0 ]; then
      exit_error "Missing node package '$nodepkg'"
   fi
done

set -uoe pipefail 

function setup() {
   local db_path="$TOOLDIR/db"
   local tmp_path="$TOOLDIR/tmp"
   if [ -d "$db_path" ]; then
      return 0;
   fi

   mkdir -p "$tmp_path"

   echo "Initializing Clarity DB"
   clarity-cli initialize "$db_path" || exit_error "Failed to initialize Clarity DB to $db_path"

   echo "Checking signer tools"
   clarity-cli check "$TOOLDIR"/pox-4.clar || exit_error "Failed to check $TOOLDIR/pox-4.clar"

   echo "Launching signer tools"
   clarity-cli launch "$ADDR.pox-4" "$TOOLDIR/pox-4.clar" "$db_path" || exit_error "Failed to launch $TOOLDIR/pox-4.clar"

   echo "Setup complete!"
   return 0
}

function clean() {
   local db_path="$TOOLDIR/db"
   local tmp_path="$TOOLDIR/tmp"
   if ! [ -d "$db_path" ]; then
      return 0;
   fi
   rm -r "$db_path"
   rm -r "$tmp_path"
   return 0
}

function sign() {
   local key="$1"
   local payload="$2"
   cat <<EOF | node
#!/usr/bin/env node

const EC = require('elliptic').ec;
const secp256k1 = new EC('secp256k1');
const crypto = require('crypto');
const process = require('process');

const keybuff = "${key}"
const msghashbuff = "${payload}"

if (keybuff.length !== 64) {
  console.error("Key must be 64 bytes");
  process.exit(1);
}

if (msghashbuff.length !== 64) {
  console.error(\`Message hash must be 32 bytes (got '\${msghashbuff}')\`);
  process.exit(1);
}

const key = secp256k1.keyFromPrivate(Buffer.from(keybuff, 'hex'))
const hash = Buffer.from(msghashbuff, 'hex')

const sig = key.sign(hash)

const rbuff = sig.r.toBuffer().toString('hex')
const sbuff = sig.s.toBuffer().toString('hex')
const vbuff = Buffer.from([sig.recoveryParam]).toString('hex')

console.log(\`\${rbuff}\${sbuff}\${vbuff}\`);
EOF
    return 0;
}

function get_public_key() {
   local key="$1"
   cat <<EOF | node
#!/usr/bin/env node

const EC = require('elliptic').ec;
const secp256k1 = new EC('secp256k1');
const process = require('process');

const keybuff = "${key}"

if (keybuff.length !== 64) {
  console.error("Key must be 64 bytes");
  process.exit(1);
}

const key = secp256k1.keyFromPrivate(Buffer.from(keybuff, 'hex'))
console.log(key.getPublic().encodeCompressed('hex'))
EOF
    return 0;
}

function decode_pox_addr() {
   local addr="$1"
   cat <<EOF | node
const c32 = require('c32check');
const process = require('process');
const asC32 = c32.b58ToC32("$addr");
const parts = c32.c32addressDecode(asC32);
let pox_version = null;
if (parts[0] === 22) {
  pox_version = '00';
}
else if (parts[0] == 20) {
  pox_version = '01';
}
else {
  process.exit(1);
}
console.log(\`{ version: 0x\${pox_version}, hashbytes: 0x\${parts[1]} }\`);
EOF
    return 0;
}

function get_signer_message_hash() {
   local pox_addr="$1"
   local reward_cycle="$2"
   local period="$3"
   local max_amount="$4"
   local auth_id="$5"

   local db_path="$TOOLDIR/db";
   local tmp_path="$TOOLDIR/tmp"
   local topic="stack-stx"
   if ! [ -d "$db_path" ]; then
      exit_error "No such file or directory: $db_path. You may need to run 'setup' first."
   fi
   if ! [ -d "$tmp_path" ]; then
      exit_error "No such file or directory: $tmp_path. You may need to run 'setup' first."
   fi
   pox_addr="$(decode_pox_addr "$1")"
   echo "(print (get-signer-key-message-hash $pox_addr u${reward_cycle} \"$topic\" u${period} u${max_amount} u${auth_id}))" > "$tmp_path/get-signer-key-message-hash.clar"
   clarity-cli eval "$ADDR.pox-4" "$tmp_path/get-signer-key-message-hash.clar" "$db_path" |
      jq -r '.output_serialized' |
      sed -r 's/^([0-9a-f]{10})(.+)$/\2/g'
}

function consume_signer_key_authorization() {
   local pox_addr="$1"
   local reward_cycle="$2"
   local period="$3"
   local max_amount="$4"
   local auth_id="$5"
   local pubkey="$6"
   local sig="$7"
   local amount="$8"
   local output=
   local output_serialized=
   
   local db_path="$TOOLDIR/db";
   local tmp_path="$TOOLDIR/tmp"
   local topic="stack-stx"
   if ! [ -d "$db_path" ]; then
      exit_error "No such file or directory: $db_path. You may need to run 'setup' first."
   fi
   if ! [ -d "$tmp_path" ]; then
      exit_error "No such file or directory: $tmp_path. You may need to run 'setup' first."
   fi
   pox_addr="$(decode_pox_addr "$1")"
   echo "(print (consume-signer-key-authorization $pox_addr u${reward_cycle} \"$topic\" u${period} (some 0x${sig}) 0x${pubkey} u${amount} u${max_amount} u${auth_id}))" > "$tmp_path/consume-signer-key-authorization.clar"
   output="$(clarity-cli eval "$ADDR.pox-4" "$tmp_path/consume-signer-key-authorization.clar" "$db_path")";
   output_serialized="$(echo "$output" | jq -r '.output_serialized')";
   if [[ "$output_serialized" != "0703" ]]; then 
      exit_error "Failed to verify signature: got result $output_serialized"
   fi
   return 0;
}

name="$0"
cmd="$1"
shift 1

if [ -z "$cmd" ]; then 
   cmd="?"
fi

case "$cmd" in 
   setup)
      setup
      ;;

   clean)
      clean
      ;;

   signer-hash | signer_hash)
      usage="Usage: $name signer-hash [-p POX_ADDR] [-r REWARD_CYCLE] [-s STX_AMOUNT] [a AUTH_ID]"
      pox_addr=
      reward_cycle=
      duration=
      amount=
      auth_id=
      while getopts ":p:r:d:s:a:" opt; do
         case "$opt" in
            p)
               pox_addr="$OPTARG"
               ;;
            r)
               reward_cycle="$OPTARG"
               ;;
            d)
               duration="$OPTARG"
               ;;
            s)
               amount="$OPTARG"
               ;;
            a)
               auth_id="$OPTARG"
               ;;
            :)
               echo >&2 "$usage"
               exit_error "Option -${OPTARG} requires an argument"
               ;;
            ?)
               echo >&2 "$usage"
               exit_error "Invalid option: -${OPTARG}"
               ;;
         esac
      done
      if [ -z "$pox_addr" ] || [ -z "$reward_cycle" ] || [ -z "$amount" ] || [ -z "$auth_id" ]; then
         echo >&2 "$usage"
         exit_error "Missing one or more options"
      fi
      signer_hash="$(get_signer_message_hash "$pox_addr" "$reward_cycle" "$duration" "$amount" "$auth_id")"
      get_signer_message_hash "$pox_addr" "$reward_cycle" "$duration" "$amount" "$auth_id"
      ;;

   sign)
      usage="Usage: $name sign SECRET_KEY SIGNER_HASH\nSECRET_KEY can be a 64-byte hex-encoded private key, or a path to one on disk\n"
      secretkey="$1"
      signer_hash="$2"

      if [ -z "$secretkey" ]; then
         printf >&2 "%s" "$usage"
         exit_error "Missing secret key"
      fi
      if [ -z "$signer_hash" ]; then
         printf >&2 "%s" "$usage"
         exit_error "Missing signer hash"
      fi

      if [ -f "$secretkey" ]; then
         secretkey="$(cat "$secretkey")"
      fi
      sign "$secretkey" "$signer_hash"
      ;;

   get-public-key | get_public_key)
      usage="Usage: $name get-public-key SECRET_KEY\nSECRET_KEY can be a 64-byte hex-encoded private key, or a path to one on disk\n"
      secretkey="$1"
      
      if [ -z "$secretkey" ]; then
         printf >&2 "%s" "$usage"
         exit_error "Missing secret key"
      fi
      if [ -f "$secretkey" ]; then
         secretkey="$(cat "$secretkey")"
      fi
      get_public_key "$secretkey"
      ;;

   check-signature | check_signature)
      usage="Usage: $name check-signature [-p POX_ADDR] [-r REWARD_CYCLE] [-s STX_AMOUNT] [a AUTH_ID] [-P public_key] [-S signature]"
      pox_addr=
      reward_cycle=
      duration=
      amount=
      auth_id=
      pubkey=
      signature=
      while getopts ":p:r:d:s:a:P:S:" opt; do
         case "$opt" in
            p)
               pox_addr="$OPTARG"
               ;;
            r)
               reward_cycle="$OPTARG"
               ;;
            d)
               duration="$OPTARG"
               ;;
            s)
               amount="$OPTARG"
               ;;
            a)
               auth_id="$OPTARG"
               ;;
            P)
               pubkey="$OPTARG"
               ;;
            S)
               signature="$OPTARG"
               ;;
            :)
               echo >&2 "$usage"
               exit_error "Option -${OPTARG} requires an argument"
               ;;
            ?)
               echo >&2 "$usage"
               exit_error "Invalid option: -${OPTARG}"
               ;;
         esac
      done
      if [ -z "$pox_addr" ] || [ -z "$reward_cycle" ] || [ -z "$amount" ] || [ -z "$auth_id" ] || [ -z "$signature" ] || [ -z "$pubkey" ]; then
         echo >&2 "$usage"
         exit_error "Missing one or more options"
      fi
      consume_signer_key_authorization "$pox_addr" "$reward_cycle" "$duration" "$amount" "$auth_id" "$pubkey" "$signature" "$amount"
      ;;

   ?)
      echo >&2 "Usage: $name command [options]"
      echo >&2 "Where command is one of:"
      echo >&2 ""
      echo >&2 "     setup              Sets up the local Clarity DB for signing and verifying"
      echo >&2 "     signer-hash        Generates a signer hash"
      echo >&2 "     sign               Signs a signer hash"
      echo >&2 "     get-public-key     Gets the public key of the signer's secret key"
      echo >&2 "     check-signature    Verifies a signer hash using a copy of .pox-4"
      echo >&2 "     clean              Clean up transient state"
      echo >&2 ""
      ;;
esac

