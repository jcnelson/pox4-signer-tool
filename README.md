# How to Use

## 0. Prerequisites

You will need basic knowledge of the UNIX command line.

You will need to install Node.js, and the node packages `elliptic` and `c32check`.
You can do this via `npm`, for example:

```
$ sudo npm install -g c32check elliptic
```

You will also need to install `clarity-cli`.  You can get this by building it
from the Stacks blockchain repository.  You will need a recent copy of the Rust
toolchain, which you can get via [rustup](https://rustup.rs/).

```
$ git clone https://github.com/stacks-network/stacks-core
$ cd stacks-core/stackslib
$ cargo build
$ ls ../target/debug/clarity-cli
clarity-cli
```

Make sure `clarity-cli` is in your `$PATH`.

Finally, you will need `jq` and `sed`.  These can be obtained from your package
manager.  It is overwhelmingly likely that `sed` is already installed, but you
may need to install `jq` manually.

## 1. Generate a signer secret key

Put this secret key into the file `signer.privkey`.  For example:

```bash
$ cat ./signer.privkey
7bfc16242cc84551b401a4dcef596da3998be52931c227d174701071ddcae791
```

Note that it must be a 64-character hex string.  Some tools will append `01` to
the end of the key in order to indicate that the key will be compressed.  If
your key generator does this, then you need to _remove_ that trailing `01`.

### Tip

If you built `clarity-cli` from source, then you will have also built
`blockstack-cli` (which will be in `./target/debug/blockstack-cli`, along with
`clarity-cli`).  You can use that to generate a private key as follows:

```bash
$ blockstack-cli generate-sk
{ 
  "secretKey": "1302424aab58cfe21a92320d069a51d4a68038857de33a0b591477e307b7b72d01",
  "publicKey": "02ff9b4ad9d996ab6992ebe352feeb9fdee79163fdd11bb1f887a2ad3faa9185eb",
  "stacksAddress": "SP22PYD7QSNQVXGY8TP81TXCBJ1MZBQ5X2J6044A4"
}
```

To get the properly-formatted secret key, you can use this one-liner (this
requires that you have the `jq` and `sed` commands).  This will extract the
`.secretKey` field and strip the trailing `01`.

```
$ blockstack-cli generate-sk | jq -r '.secretKey' | sed -r 's/^([0-9a-f]{64})(.+)$/\1/g'
1302424aab58cfe21a92320d069a51d4a68038857de33a0b591477e307b7b72d
```

## 2. Set up the script

Edit the `run.sh` file and change the following variables:

```bash
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
```

## 3. Run the generator

If everything works, you'll see something like this output.  The only line that
matter is the last one:

```bash
$ ./run.sh
Initializing Clarity DB
INFO [1714574704.806508] [src/chainstate/stacks/index/file.rs:275] [main] Migrate 0 blocks to external blob storage at ./db/marf.sqlite.blobs
INFO [1714574704.806566] [src/chainstate/stacks/index/file.rs:204] [main] Preemptively vacuuming the database file to free up space after copying trie blobs to a separate file
{"message":"Database created.","network":"mainnet"}
Checking signer tools
{"message":"Checks passed."}
Launching signer tools
{"events":[],"message":"Contract initialized!"}
Setup complete!
{"pubkey": "033fcef99a5a3e8df383e751dd5945389c6d1f888fce08fe028b4f287e47590df7", "signature": "bb8eaec05457ccc3d73b5b0e2b6e25883256b2f764090a7afac084596e9832c932e744e4138ba6f75b8c12d75d3808fce11e43f5adc974d391ee53e202d958a101"}
```

That last line with the JSON is the part you'll need.  The `pubkey` field is
your signer public key, which you can paste into lockedstacks.com or your
referred stacking wallet.  The `signature` field is your signer signature, which
you'd also paste into lockedstacks.com.

# Limitations

Right now, only legacy PoX addresses are supported.
